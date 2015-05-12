#!/usr/bin/env perl
use warnings;
use strict;

#
# GLOBAL CONFIG (shouldn't have to touch anything else in this file)
#

my $DATADIR = "$ENV{HOME}/.alerts"; # Where we'll look for all related files
my $CONFIGFILE = "$DATADIR/config"; # Where to read configuration from

#
# MODULE IMPORTS
#

# These three must be loaded before we turn a proxy on
use Mail::Sendmail;	# For sending alerts via email
use Config::Simple;	# For reading config files

# We read configuration now to determine if a proxy is needed
my %config;
Config::Simple->import_from($CONFIGFILE, \%config);
validate_config(\%config);

if( lc($config{proxyenabled}) eq "true" )
{
	# Step on IO::Socket, run everything through Tor
	#use IO::Socket::Socks::Wrapper
	#{
		#ProxyAddr => $config{proxyhost},
		#ProxyPort => $config{proxyport},
		#SocksDebug => 1,
		#Timeout => 10
	#};
	#IO::Socket::Socks::Wrapper->import(Mail::Sendmail:: => 0); # direct network access
}

# Here are the modules we would want to be affected by a proxy
use XML::Feed;                  # For parsing RSS feeds
use HTML::Strip;                # For stripping html out of RSS feeds
use Text::Unidecode;            # For removing weird html artifacts
use Encode;                     # For UTF-8 encoding before sending email
use Fcntl qw(:DEFAULT :flock);  # Gives us flock
use File::Slurp;                # Gives us readfile
use Data::Dumper;               # For debugging

#
# INITIALIZING
#

my %feeds;  # Stores all RSS feeds we read from
my @alerts; # Every term we want to alert on
my %sent;   # Every alert we've already sent

Config::Simple->import_from("$DATADIR/$config{feedfile}", \%feeds);

my @alert_lines = read_file("$DATADIR/$config{alertfile}");
foreach( @alert_lines )
{
	chomp;
	next if m!^#!;
	next if m!^\s*$!;
	push (@alerts, $_);
}

my @sent_lines = read_file("$DATADIR/$config{logfile}");
foreach( @sent_lines )
{
	chomp;
	$sent{$_} = 1;
}

# Block errors related to feeds being unavailable
# Disable these during debugging
close STDOUT;
close STDERR; 

#
# FEED PARSING
#

#
# Here we set up a process to handle each feed
#
for my $feedname ( keys( %feeds ) )
{
	# Kick off a child process to handle the feed, parent goes to next feed.
	# This improves performance, and makes sure a 'die' on a client won't kill
	# the entire program.
	my $pid = fork();
	die "Not enough resources to fork!\n" if( !defined($pid) );
	next if( $pid != 0 );
	handle_feed($feedname, $feeds{$feedname});
}

#
# handle_feed - Gets list of headlines from an RSS feed
#
sub handle_feed
{
	my ($feedname, $feedurl) = @_ or die "No feed to handle!\n";

	my $feed = XML::Feed->parse(URI->new($feedurl)) or 
		die XML::Feed->errstr;

	my @articles = ($feed->entries);

	# Debugging
	#print Dumper(@articles);
	#print "Headline count: ", scalar(@headlines), "\n";
	#print "\t", $_->headline . "\n" for @headlines;

	handle_articles($feedname, @articles);
	exit 0; # Kill the child process when done with this feed
}

#
# handle_articles - Gets some information about each entry before handling
#
sub handle_articles
{
	my $feedname = shift;
	my @headlines = @_;

	for( @headlines )
	{
		# Avoid repeated method calls and annoying syntax
		my $headline = $_->title;
		my $description = $_->content->{body};
		my $url = $_->link;
		foreach my $alert ( @alerts )
		{
			handle_alert($feedname, $headline, $description, $url, $alert);
		}
	}	
}

#
# handle_alert - Checks if a single headline warrants an alert to be sent
#
sub handle_alert
{
	my ($feedname, $headline, $description, $url, $alert) = @_ or
		die "Not enough arguments to handle!\n";
	return if already_alerted($feedname, $headline, $alert);

	# If this RSS entry contains our alert phrase	
	if( $headline =~ m/^$alert /i or $headline =~ m/ $alert / or 
		$description =~ m/^$alert / or $description =~ m/ ${alert}[\. ]/ )
	{
		my $message = encode('utf8', $headline . "\n\n" . $description .
			"\n\n" . $url);
		my $subject = "Alert ($alert) from $feedname";
		
		# Check if the alert is in the headline, not just the body
		if( $headline =~ m/^$alert/ or $headline =~ m/ $alert / )
		{
			my $subject = "High $subject"; # Mark as extra important
		}

		send_message($subject, $message);
		log_alert(encode('utf8', "$feedname $alert: $headline"));
	}
}

#
# already_alerted - Checks if we've encountered an alert before
#
sub already_alerted
{
	my ($feedname, $headline, $alert) = @_ or die "Not enough alert data!\n";
	my $alert_string = encode('utf8', "$feedname $alert: $headline");
	chomp($alert_string);
	if( $sent{$alert_string} )
	{
		return 1;  # True, we've encountered this alert before
	}
	else
	{
		return 0;  # False, this is a new alert
	}
}

sub send_message
{
	my ($subject, $message) = @_ or die "No message data!\n";
	
	my $hs = HTML::Strip->new();
	$message = $hs->parse($message);
	$hs->eof;

	sendmail(
		To		=> $config{alert_target},
		From	=> $config{alert_sender},
		Subject	=> $subject,
		Message	=> unidecode($message)
		);
}

#
# validate_config - Verifies necessary config has been set and sets defaults
#
sub validate_config
{
	my $config = shift or die "No configuration given!\n";
	$config->{proxyenabled} = "false" if( !defined($config->{proxyenabled}) );
	$config->{proxyhost} = "localhost" if( !defined($config->{proxyhost}) );
	$config->{proxyport} = "9050" if( !defined($config->{proxyport}) );
	$config->{feedfile} = "feeds" if( !defined($config->{feedfile}) );
	$config->{alertfile} = "alerts" if( !defined($config->{alertfile}) );
	$config->{logfile} = "sent_alerts" if( !defined($config->{logfile}) );
	if( !defined($config->{alert_target}) or !defined($config->{alert_sender}) )
	{
		die "alert_target and alert_sender MUST be defined in $CONFIGFILE!\n";
	}
}

#
# log_alert - Logs that an alert has been emailed (and not to email it again)
#
sub log_alert
{
	my $alert = shift or die "No alert set!\n";
	my $failed = 0;
	# The alert system uses forking for performance.
	# That's great, but if two children try to log at the same time we can lock
	# ourselves out. So we wait with sleep to try the lock repeatedly.
	do
	{
		my $status = 0;
		open( LOGFILE, ">>", "$DATADIR/$config{logfile}" ) || $status++;
		if( $status == 0 )
		{
			# If we opened the file, lock it non-blocking
			flock( LOGFILE, LOCK_EX | LOCK_NB ) || $status++;
		}
		if( $status > 0 )
		{
			$failed++;
			sleep 3; # Wait for other people to finish up
		}
		else
		{
			# Success! Log to disk and return from function
			print LOGFILE "$alert\n";
			close LOGFILE;
			return;
		}
	} while( $failed > 0 and $failed < 10 );
	# If we get here, something has gone wrong.
	die ("Unable to open log file after repeated attempts.\n" . 
			"String was: $alert\n");
}

__END__

=head1 NAME

alert - An RSS News parser and alert system

=head1 USAGE

	./alert

The script looks for a config file in ~/.alerts/config, and uses it to find a list of RSS feeds and alert terms.

=head1 DESCRIPTION

We parse the given rss feeds, and read every entry.
We then check a list of B<alert phrases> against the headlines and articles.
If any alert phrases are found an email is dispatched to B<alert_target> via sendmail.

=head1 LICENSE AND COPYRIGHT

The MIT License (MIT)

Copyright (c) 2014 Milo Trujillo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut

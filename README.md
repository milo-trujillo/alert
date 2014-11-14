alert
=====

Overview
--------

Alert is an RSS monitoring script. It reads a list of RSS feeds, reads a list of alert terms, and if any alert terms appear in the RSS feeds, sends an email to the specified address.

Example email
-------------

> To: some.person@zombo.com
>
> From: alerts@zombo.com
>
> Subject: Alert (Tor) from CNN
> 
>
> Government officials report that hackers may use the Tor network! Oh my!
> 
> https://cnn.com/full-article-here

Usage
-----

The script is intended to be run regularly as a cronjob. It takes no arguments, but expects to find a config file in `~/.alerts/config` and reads a list of RSS feeds and a list of alert trigger terms from two more files. An example of this setup is included in the `alerts` folder. Further technical information is included as POD data at the end of the alert script.

Dependencies
------------

The script is requires a modern version of Perl and the following modules:
* Mail::Sendmail
* Config::Simple
* XML::Feed
* HTML::Strip
* File::Slurp
* Data::Dumper (Only if debugging)
* IO::Socket::Socks::Wrapper (Only if testing an unsupported feature)
* Encode
* Fcntl

Bugs
----

`alert` was initially supposed to support transparently proxying over a SOCKS or HTTP proxy. Right now the proxy code mucks up parsing RSS feeds, so it's been disabled.


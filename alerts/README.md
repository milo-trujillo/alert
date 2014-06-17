To get the script running
-------------------------

Rename this folder to .alerts and change the email addresses in `config`.

To add your own feeds and alert items
-------------------------------------

Add feeds to `feeds` and alert triggers to `alerts`.

Configuration options
---------------------

The following options can be specified in the config file. Most have default values, but **alert_target** and **alert_sender** *must* be defined.

proxyenabled - 'true' or 'false' to enable a proxy (Default: false) (CURRENTLY UNUSED)
proxyhost - What host to proxy through (Default: localhost)
proxyport - Port to proxy on (Default: 9050)
feedfile - What file to read list of feeds from (Default: feeds)
alertfile - What file to read alert triggers from (Default: alerts)
logfile - What file to log sent trigger messages to (Default: sent_alerts)
alert_target - Who to send alarms *to*
alert_sender - Who to send alarms *from*

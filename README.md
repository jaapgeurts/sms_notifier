# Sms Notifier for linux

Show desktop notifications when an SMS message is received on an broadband(gsm/cdma) modem.

If the message contains a number [0-9]+ it will add a "copy to clipboard" button to the notification.

## Building

Install a D (https://dlang.org/) toolchain and run `dub build` in the project root folder.

## Installing

To install run
`$ sh ./install.sh`

To uninstall run
`$ sh ./uninstall.sh`
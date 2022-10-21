#!/bin/bash

echo "Removing SMS Notifier"

systemctl --user stop smsnotifier
systemctl --user disable smsnotifier

rm "$HOME/bin/smsnotifier"
rm "$HOME/.config/systemd/user/smsnotifier.service"

echo "Done"
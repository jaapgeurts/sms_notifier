#!/bin/bash

echo "Installing SMS Notifier"

if [ ! -d "$HOME/bin" ]; then
    mkdir -v -p "$HOME/bin"
fi

cp -v smsnotifier "$HOME/bin"
cp -v "smsnotifier.service" "$HOME/.config/systemd/user"


systemctl --user enable smsnotifier
systemctl --user start smsnotifier

echo "Done"


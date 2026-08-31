#!/usr/bin/env bash

if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
    systemctl reboot
elif command -v loginctl &>/dev/null; then
    loginctl reboot
elif command -v dbus-send &>/dev/null; then
    dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Reboot boolean:true 2>/dev/null
elif command -v openrc-shutdown &>/dev/null; then
    openrc-shutdown -r now
elif command -v dinitctl &>/dev/null; then
    dinitctl reboot
elif command -v reboot &>/dev/null; then
    reboot
fi

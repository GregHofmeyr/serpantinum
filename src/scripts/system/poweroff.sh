#!/usr/bin/env bash

if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
    systemctl poweroff -i
elif command -v loginctl &>/dev/null; then
    loginctl poweroff
elif command -v dbus-send &>/dev/null; then
    dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.PowerOff boolean:true 2>/dev/null
elif command -v openrc-shutdown &>/dev/null; then
    openrc-shutdown -p now
elif command -v dinitctl &>/dev/null; then
    dinitctl shutdown
elif command -v poweroff &>/dev/null; then
    poweroff
fi

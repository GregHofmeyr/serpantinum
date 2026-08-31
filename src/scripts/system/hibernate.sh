#!/usr/bin/env bash

if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
    systemctl hibernate
elif command -v loginctl &>/dev/null; then
    loginctl hibernate
elif command -v dbus-send &>/dev/null; then
    dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Hibernate boolean:true 2>/dev/null
elif command -v ZZZ &>/dev/null; then
    ZZZ
elif [ -w /sys/power/state ]; then
    echo disk > /sys/power/state
fi

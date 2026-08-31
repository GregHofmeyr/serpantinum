#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/lock.sh"

if [ -f "$LOCK_SCRIPT" ]; then
    bash "$LOCK_SCRIPT" &
    sleep 0.5
fi

if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
    systemctl suspend
elif command -v loginctl &>/dev/null; then
    loginctl suspend
elif command -v dbus-send &>/dev/null; then
    dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Suspend boolean:true 2>/dev/null
elif command -v zzz &>/dev/null; then
    zzz
elif [ -w /sys/power/state ]; then
    echo mem > /sys/power/state
fi

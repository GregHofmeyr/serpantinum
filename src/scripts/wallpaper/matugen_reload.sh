#!/usr/bin/env bash

source "$SCRIPT_DIR/../caching.sh"

quickshell -p "$MAIN_QML" ipc call theme reloadColors >/dev/null 2>&1 &

killall -USR1 .kitty-wrapped

# NOTE: ghostty is intentionally NOT signalled here. ghostty 1.3.1-arch does NOT catch
# SIGUSR2 (default action = terminate → it would KILL every open ghostty on each wallpaper
# change; verified 2026-09-22). It also has no external live-reload IPC. So ghostty picks up
# new matugen colors when a NEW window opens (config-file re-read on launch); already-open
# windows keep their colors until reopened (or a manual in-app reload_config). — Greg fork patch.

wait

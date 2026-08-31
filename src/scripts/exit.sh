#!/usr/bin/env bash

systemctl --user stop graphical-session.target
systemctl --user stop graphical-session-pre.target
sleep 0.5
# Upstream uses serp's Lua-config dispatcher `hl.dsp.exit()`, which is invalid on a
# plain .conf Hyprland (our serp session). `exit` is the universal dispatcher and
# works under both the .conf and the Lua config. — Greg fork patch (2026-08-31)
hyprctl dispatch exit

#!/usr/bin/env bash
# kdeconnect.sh — phone status + actions for the ConnectionsHub Phone view.
#   status  -> JSON {reachable,name,battery,charging,sigType,sigStrength}
#   ring    -> ring the phone (findmyphone)
#   clip    -> send the desktop clipboard to the phone
#   share   -> pick a file (kdialog) and send it to the phone
#   files   -> mount the phone over sftp and open it in the file manager
#   cleanup -> lazy-unmount all kdeconnect sshfs + stop adb (teardown safety net; runs on logout)
# Targets the first paired+reachable device. Safe/offline: status never errors.
set -uo pipefail
SVC=org.kde.kdeconnect
# timeout-guarded so a dying kdeconnectd at logout can't hang the cleanup path
D="$(timeout 3 kdeconnect-cli -a --id-only 2>/dev/null | head -1)"
BASE="/modules/kdeconnect/devices/$D"

# read a D-Bus property, stripping the busctl "<type> " prefix + surrounding quotes
getp() { busctl --user get-property "$SVC" "$1" "$2" "$3" 2>/dev/null | sed -E 's/^[a-z] //; s/^"//; s/"$//'; }
need_dev() { [ -n "$D" ] || { notify-send -t 2000 "KDE Connect" "No phone connected"; exit 1; }; }

RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# lazy-unmount a fuse path — fuse-aware, hard fallback; never blocks on a dead remote
_umount() { fusermount3 -u -z "$1" 2>/dev/null || umount -l "$1" 2>/dev/null; }
# Live guard: clear THIS device's sftp mount ONLY if it's stale (phone changed IP →
# dead remote), so KDE Connect remounts fresh against the current IP. Alive mount or
# no mount → no-op. Bounded by a 2s probe so it can never hang on a corpse.
ensure_fresh_mount() {
  local m="$RT/$D"
  mount 2>/dev/null | grep -qF "$m" || return 0          # nothing mounted → fine
  timeout 2 stat "$m/storage" >/dev/null 2>&1 && return 0 # mount responds → alive → fine
  _umount "$m"                                            # stale → drop it, KDE Connect remounts
}

case "${1:-status}" in
  status)
    [ -n "$D" ] || { echo '{"reachable": false}'; exit 0; }
    name="$(getp "$BASE" org.kde.kdeconnect.device name)"
    batt="$(getp "$BASE/battery" org.kde.kdeconnect.device.battery charge)"
    chg="$(getp "$BASE/battery" org.kde.kdeconnect.device.battery isCharging)"
    stype="$(getp "$BASE/connectivity_report" org.kde.kdeconnect.device.connectivity_report cellularNetworkType)"
    sstr="$(getp "$BASE/connectivity_report" org.kde.kdeconnect.device.connectivity_report cellularNetworkStrength)"
    [ "$chg" = "true" ] && chg=true || chg=false
    printf '{"reachable": true, "name": "%s", "battery": %s, "charging": %s, "sigType": "%s", "sigStrength": %s}\n' \
      "${name:-Phone}" "${batt:--1}" "$chg" "${stype:-}" "${sstr:--1}"
    ;;
  ring)  need_dev; kdeconnect-cli --ring -d "$D" ;;
  clip)  need_dev; kdeconnect-cli --send-clipboard -d "$D" && notify-send -t 1500 "KDE Connect" "Clipboard sent to phone" ;;
  share) need_dev
         f="$(kdialog --getopenfilename "$HOME" 2>/dev/null)" || exit 0
         [ -n "$f" ] && kdeconnect-cli --share "$f" -d "$D" && notify-send -t 1500 "KDE Connect" "Sent: $(basename "$f")" ;;
  files)  need_dev; ensure_fresh_mount; setsid -f dolphin "kdeconnect://$D/" >/dev/null 2>&1 ;;
  photos) need_dev; ensure_fresh_mount   # deep-link to DCIM (Camera/Screenshots/WhatsApp) via the sftp mount path
         MOUNT="$RT/$D"; tgt="$MOUNT/storage/emulated/0/DCIM"
         if [ ! -d "$tgt" ]; then kioclient ls "kdeconnect://$D/" >/dev/null 2>&1; for _ in $(seq 1 16); do [ -d "$tgt" ] && break; sleep 0.5; done; fi
         if [ -d "$tgt" ]; then setsid -f dolphin "$tgt" >/dev/null 2>&1
         else setsid -f dolphin "kdeconnect://$D/" >/dev/null 2>&1; fi ;;
  messages)   # open on the CURRENT workspace (kdeconnect-sms is single-instance → it otherwise stays pinned where it first opened)
         cur="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null)"
         addr="$(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class|test("kdeconnect.sms";"i")) | .address' 2>/dev/null | head -1)"
         if [ -n "$addr" ]; then
           [ -n "$cur" ] && hyprctl dispatch movetoworkspace "${cur},address:${addr}" >/dev/null 2>&1
           hyprctl dispatch focuswindow "address:${addr}" >/dev/null 2>&1
         else
           setsid -f kdeconnect-sms >/dev/null 2>&1   # fresh launch opens on the active workspace
         fi ;;
  mirror) if ! command -v scrcpy >/dev/null 2>&1; then notify-send -t 3000 "Screen Mirror" "scrcpy not installed"; exit 0; fi
          # derive the phone's CURRENT LAN IP from kdeconnect (it changes between networks) instead of a hardcoded one
          ip="$(kdeconnect-cli -l 2>/dev/null | grep -F "$D" | grep -oE 'on [0-9.]+' | awk '{print $2}' | head -1)"
          adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{f=1} END{exit !f}' || adb connect "${ip:-192.168.1.224}:5555" >/dev/null 2>&1
          if adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{f=1} END{exit !f}'; then
            setsid -f scrcpy --window-title "Galaxy S26 Ultra" >/dev/null 2>&1
          else
            notify-send -t 5000 "Screen Mirror" "Phone not reachable over adb — re-enable Wireless Debugging on the phone (its port changes each time)"
          fi ;;
  cleanup)  # teardown safety net (systemd ExecStop / manual) — unmount ALL kdeconnect sshfs + stop adb. Idempotent, never hangs.
         for m in $(mount 2>/dev/null | awk '/fuse\.sshfs/ && /kdeconnect@/ {print $3}'); do _umount "$m"; done
         adb kill-server >/dev/null 2>&1
         log="${XDG_STATE_HOME:-$HOME/.local/state}/kdeconnect-cleanup.log"; mkdir -p "$(dirname "$log")" 2>/dev/null
         echo "$(date '+%F %T') cleanup: unmounted kdeconnect sshfs + adb kill-server" >> "$log" 2>/dev/null ;;
  *) echo "usage: kdeconnect.sh status|ring|clip|share|files|photos|messages|mirror|cleanup" >&2; exit 1 ;;
esac

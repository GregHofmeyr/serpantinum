# Serpantinum — Our Fork Changes & Setup Notes

A rundown of what we've customised on top of [ilyamiro/serpantinum](https://github.com/ilyamiro/serpantinum),
plus the Hyprspace overview setup. Written to share with a fellow serp user — steal anything useful.

- **Our fork:** `github.com/GregHofmeyr/serpantinum` (upstream = `ilyamiro/serpantinum`)
- **Base:** upstream `v2.5.1` + the patches/widgets below (last merge 2026-11-13)
- **Hyprland:** 0.57.1 — ⚠️ **Lua config now** (see §6) · **Session:** uwsm-managed Hyprland running the serp shell
- **Runtime deps:** three Rust daemons (NOT bundled) — `serpantinum-core` (metrics/brightness/network/screentime), `serpantinum-audio` (EQ/audio engine, replaces EasyEffects), `serpantinum-gamma` (blue light filter, replaces wl-gammarelay-rs). Install all three; see §6.

---

## 0. How we run + update the fork (the important gotcha)

We **run serp straight from the git clone** (`~/Projects/serpantinum`) via symlinks in `~/.local/bin`
(`bin/serpantinumd` self-locates its source), so nothing is deployed to `~/.local/share`.

⚠️ **Do NOT use serp's in-app updater when you run from a fork** — it deploys to `~/.local/share/serpantinum`
and diverges from the source tree you actually run. Update with git instead:

```bash
cd ~/Projects/serpantinum
git fetch upstream && git merge upstream/master   # resolve conflicts on our patches
# bump ~/.local/state/serpantinum/version so the "update available" nag clears
```

Our patches are small, append-style edits, so upstream merges stay low-conflict. New widgets are
**new files** (can't conflict at all).

---

## 1. Fixes (patches on upstream)

| Commit | What | Why |
|---|---|---|
| `b42e8fd` | **screenshot: satty → swappy** for the edit step | satty (GTK4 0.22) busy-loops at 100% CPU and never draws a window on GTK4 4.22 + Hyprland + NVIDIA (any GSK_RENDERER). swappy (GTK3) just works. |
| `bff7f52` | **volume: active device to top** + a `wheelEnabled` prop on the `Draggable` reusable | (1) default output now sorts to the top of the device list; (2) scrolling the device list no longer drags the per-row sliders under the cursor (which was silently unmuting devices). |
| `2557ae2` | **network: opt-in trusted/known-only Bluetooth filter** | Set `bluetooth.trustedOnly: true` in `settings.json` → the BT list shows only trusted/connected/paired devices instead of the whole untrusted-scan flood. Default off = upstream behaviour (clean merges). |
| `5388b22` `f6d503e` | **github widget: prefer GitHub HTML over the public-only proxy** (+ exact per-day counts from the HTML tooltips) | the jogruber proxy only sees *public* contributions (wrong/low counts if you have private activity) and returns 200 so never falls back; the GitHub HTML (`/users/<u>/contributions`) carries exact counts. Re-asserted in the 2.4.3 merge — upstream adopted the same HTML technique but prefers the proxy first, so we flip the initiating call-sites to HTML-first. |
| `cf8595e` | **theme: matugen themes from the live wallpaper, not the stale `wallpaper` setting** | serp never writes the `wallpaper` setting, so `ThemeBackend.updateColors()` (runs on startup + every settings-change) re-generated matugen from the OLD wallpaper → the theme **reverted** to the old colours on restart while the real wallpaper differed. Now sources `current_wallpaper.png` (what `WallpaperEngine` already themes from). Likely an upstream bug — candidate PR to ilyamiro. |

*(Superseded/dead patches: the screenshot `GSK_RENDERER=ngl` attempt (renderer was never the cause); the
`exit.sh` dispatcher fix (upstream deleted that script); and the **ghostty adaptive-matugen** patch (`1abcaaf`) —
upstream v2.4.x ships native ghostty theming (per-app `apps/ghostty/`, gdbus `reload-config` instead of the
SIGUSR2 that used to kill ghostty), so we dropped ours in the 2.4.3 merge.)*

---

## 2. Custom widgets we built

Both are ports of hand-built HyDE-Quickshell widgets, rebuilt in serp's idiom (ThemeBackend tokens →
matugen-themed, `Scaler.s()` scaling, serp reusables, ambient blur "blobs").

### 🐳 Docker dashboard — `SUPER+D`
`src/quickshell/docker/DockerPanel.qml` + `src/scripts/docker-stats.py`
- Live container dashboard grouped by compose project: overview strip (running/healthy/unhealthy/images/disk),
  per-container live CPU/MEM bars, ports, health.
- Lifecycle control: **Start** = single click (`ClickButton`); **Stop/Restart** = hold-to-confirm
  (serp's `FillButton` liquid-fill), so a stray tap never kills a container. Failure → notification.
- Data via `docker ps`/`docker stats` (no sudo; user in the `docker` group).

### ☁️📱 Connections hub (WARP + KDE Connect) — `SUPER+SHIFT+N`
`src/quickshell/connections/ConnectionsPanel.qml` + `src/scripts/kdeconnect.sh`
- **Cloudflare WARP**: status + toggle + live tunnel stats (latency/loss/sent/recv/protocol/handshake).
- **KDE Connect phone**: battery/signal + action buttons (Ring · Clip · Share · Photos · Files · Messages · Mirror).
- serp already covers wifi/BT natively, so this widget is just the VPN + phone bits.

### 🧩 The recipe to add your own widget
serp has **no drop-in user-widget dir** — a new widget is a fork edit, but a clean, few-line one:
1. Drop a QML file under `src/quickshell/<name>/`
2. Register in `src/quickshell/WindowRegistry.js`: add a `getWidgetLauncherEntries` entry **and** a
   `getLayout` mapping (`{ w, h, comp: "<name>/File.qml", pos: {...} }`)
3. Add `"<name>"` to `_allWidgetNames` in `src/quickshell/Main.qml`
4. Bind a key: `bind = $mainMod, X, exec, serpantinum msg toggle <name>`

Gate any polling on `root.visible` so a hidden widget isn't doing work.

---

## 3. Hyprspace overview (replacing hyprexpo) — the fun one 🕵️

> ⚠️ **RETIRED on Hyprland 0.57 (2026-11-09).** The plugin doesn't build against 0.57's headers
> ("[hyprpm] Failed to load plugins: Outdated headers"); the `hyprpm reload` load-attempt was removed from
> autostart to kill the boot warning. Greg wasn't really using the overview → parked. To revive on 0.57:
> `hyprpm update` (rebuild for the new ABI) → re-add `hyprpm reload` + the bind. The notes below are the 0.56-era setup.

We swapped hyprexpo for **[Hyprspace](https://github.com/KZDKM/Hyprspace)** — a GNOME/macOS-style
overview where you can **drag windows between workspaces**, with a proper spaces panel, special-workspace
support, and a clean multi-monitor dispatcher.

### The catch (and the detective story)
Hyprspace's main repo **won't build on Hyprland 0.56.x** (the plugin lags Hyprland's fast-moving API —
moved `AnimationManager.hpp`, config API v2, fullscreen enum → `SFullscreenState`, `m_realPosition/Size`
accessors, deleted legacy config mgr). There's **no maintained 0.56 fork**… but digging the issues turned
up **[PR #238 by ImanolBarba](https://github.com/KZDKM/Hyprspace/pull/238)** — an open, unmerged branch
(`migrate-v2`) that migrates it to 0.56.0+. Contributors confirmed it builds on 0.56.

**The trick to actually install a PR branch via hyprpm:** hyprpm shallow-clones only the *default* branch,
so `hyprpm add <url> migrate-v2` (passing the branch as a git-rev) **fails** ("unknown revision"). So we:
1. Forked it → `github.com/GregHofmeyr/Hyprspace`
2. **Set `migrate-v2` as the fork's DEFAULT branch** (so hyprpm's shallow clone grabs the fix)
3. `hyprpm add https://github.com/GregHofmeyr/Hyprspace.git` → **builds clean on 0.56.2** ✅

*(You now own the fork → wipe-proof + updatable; watch for KZDKM merging #238 upstream one day.)*

### Install
```bash
hyprpm add https://github.com/GregHofmeyr/Hyprspace.git   # (or fork it yourself, same trick)
hyprpm enable Hyprspace
hyprpm disable hyprexpo    # if you were on hyprexpo
hyprpm reload -n
```

### Wiring it into the session (3 things people miss)
```ini
# 1) LOAD the plugin on boot — without this it never loads and overview:toggle is an "invalid dispatcher"
exec-once = hyprpm reload -n

# 2) Bind via exec+hyprctl (NOT a native `overview:toggle` bind) so there's no parse-time
#    "invalid dispatcher" warning before the plugin finishes loading. (We use mouse5 — 60% keyboard.)
bind = $mainMod, mouse:276, exec, hyprctl dispatch overview:toggle

# 3) Config block — dispatchers: overview:toggle / overview:open / overview:close (optional `all` arg)
plugin {
    overview {
        centerAligned = true         # workspaces centered (GNOME/macOS) vs left (Windows)
        showNewWorkspace = true      # dynamic empty "new workspace" slot at the end
        showSpecialWorkspace = true  # show the scratchpad in the overview
        switchOnDrop = true          # drop a window onto a workspace → jump there
        exitOnClick = true           # click empty space to close
        # plenty more: panelHeight, onBottom, reverseSwipe, hideBackgroundLayers, colors, overrideAnimSpeed…
    }
}
```
⚠️ Don't enable `overrideGaps` **and** `affectStrut` together — that combo crashed in early builds of the PR.

### gesturepad (phone-swipe) integration
Repointed our gesturepad daemon's overview gestures from `hyprexpo:expo` → Hyprspace's
`overview:open`/`close`/`toggle` (empty args). 3-finger up/down from the phone now drives Hyprspace.

---

## 4. EQ / audio chain — now the native serpantinum-audio engine

**Upstream replaced EasyEffects with `serpantinum-audio`** (a PipeWire processor; see §6), and the shell now
ships a full audio widget in the music popup: 10-band EQ + presets (Flat/Bass/Treble/Vocal/Pop/Rock/Jazz/
Classic), balance, mono, channel-swap, dynamic-range modes and a dynamic-EQ toggle — all driven through
`src/quickshell/media/equalizer.sh` → `serpantinum-audio ctl ...`. The visualizer spectrum reads from it too.
Streams are routed into a `serpantinum_sink` and processed inline (verify with `wpctl status`).

So our old EasyEffects plan (§4 as it was) is **retired**:
- The `SUPER+SHIFT+E` → `easyeffects --bypass-toggle` bind in `hyprland.lua` (cachy-configs) is **dead** —
  EasyEffects is no longer the chain. Rebind or drop it.
- The staged `src/scripts/eq-apply.sh` + `eq-restore.sh` (untracked) are **obsolete** — serpantinum-audio
  persists its own state (`~/.local/state/serpantinum/audio.state`). Safe to delete.
- On first start after the update, `migrate_easyeffects.sh` hands audio over from EasyEffects automatically.

⚠️ **The whole widget silently no-ops if `serpantinum-audio` isn't on PATH** (equalizer.sh bails at its
`command -v` guard) — this is exactly how it looked broken before we installed the daemon. See §6.

---

## 5. Backlog (want-to-do)

- **AudioHub / EQ controller widget** (see §4) + adjustable dB range + persist.
- **Audio device widget**: proper per-device volume/mute exposure + device-list cleanup (mostly there upstream).
- **Clipboard:** exclude *pinned* items from the "clear" action (pinned live in `pinned.json`; clear currently
  wipes everything).
- **Floating (left-edge) widget:** stop it following the cursor vertically (keep it centered) + per-display fix.
- **BT trusted-only:** a UI toggle for the filter (currently a settings.json flag).
- Launcher widget-buttons tidy-up.

---

## 6. Hyprland 0.57 → Lua config + serpantinum-core (2026-11-09)

**Hyprland 0.57's config parser is Lua-only** (ships `/usr/share/hypr/stubs/hl.meta.lua` = full API + `/usr/share/hypr/hyprland.lua` = default). Our `.conf` session config was migrated to **`~/.config/hypr-serp/hyprland.lua`** (single self-contained file: `hl.config{}`, `hl.bind(k, hl.dsp.*, {flags})`, `hl.monitor{}`, `hl.layer_rule{}`, `hl.on("hyprland.start", …)`). nvidia + monitors were folded in, and the Lua config **parses `~/.config/hypr/monitors.conf`** itself so nwg-displays changes still persist on reload. Validate with `Hyprland --verify-config -c <file>` (prints `config ok`). ⚠️ Hyprland's config Lua is **Luau-ish — `for` loop variables are const** (bind a fresh local). Launched via uwsm (not `start-hyprland`), which throws a cosmetic "started without start-hyprland" nag — we auto-`hyprctl dismissnotify` it a few seconds into boot.

### Companion daemons (NOT bundled — install all three or features silently no-op)

serp 2.5.x offloads real work to **three separate Rust daemons** (official repos under `ilyamiro/`). The
shell spawns them by name on `PATH` and guards every call with `command -v`, so a missing one just disables
its feature instead of crashing — which is why a missing daemon *looks like a bug* rather than an error:

| Daemon | Does | Missing → |
|---|---|---|
| `serpantinum-core` (≥0.6.0) | system usage, brightness, caps/num-lock, idle, network, screen time, launcher rank, monitors, wallpaper index | system-monitor empty, brightness/network widgets blank |
| `serpantinum-audio` | the whole audio widget: EQ + presets, balance, mono, swap, dynamics, dynamic EQ, visualizer (replaces EasyEffects) | audio widget does nothing (see §4) |
| `serpantinum-gamma` | blue light filter + day/night schedule (replaces wl-gammarelay-rs) | blue light filter does nothing |

**Install (prebuilt — no cargo needed):** each repo publishes checksummed `x86_64-linux` release tarballs —
exactly what serp's own installer pulls (`install/modules/{core,audio,gamma}.sh`). We stage them under
`~/.local/share/serpantinum-daemons/<name>/` and symlink the binary into `~/.local/bin`:

```bash
for r in serpantinum-core serpantinum-audio serpantinum-gamma; do
  json=$(curl -fsSL https://api.github.com/repos/ilyamiro/$r/releases/latest)
  url=$(jq -r '.assets[]|select(.name|test("-x86_64-linux\\.tar\\.gz$"))|.browser_download_url' <<<"$json")
  sums=$(jq -r '.assets[]|select(.name=="SHA256SUMS")|.browser_download_url' <<<"$json")
  d=~/.local/share/serpantinum-daemons/$r; mkdir -p "$d/dl"
  curl -fsSL "$url" -o "$d/dl/a.tgz"; curl -fsSL "$sums" -o "$d/dl/SHA256SUMS"
  ( cd "$d/dl" && grep -F " ${url##*/}" SHA256SUMS | sha256sum -c - )   # verify before trusting
  tar -xzf "$d/dl/a.tgz" -C "$d" --strip-components=2 usr/bin/$r
  ln -sf "$d/$r" ~/.local/bin/$r
done
# verify: serpantinum-core sysinfo | head -c80 ; serpantinum-audio version ; serpantinum-gamma --version
# then restart serp so it leases the feeds + auto-starts the audio engine.
```
*(2026-11-13: installed **core 0.6.1, audio 0.4.0, gamma 0.7.0**. The old cargo-built serpantinum-core 0.5.0
source tree at `~/Projects/serpantinum-core` is superseded but left in place. The D-Bus `.service` files the
tarballs carry are **not needed** — the shell spawns the binaries directly, and those files hardcode `/usr/bin`.)*

---

## Appendix — our keybinds (serp session)

| Key | Action |
|---|---|
| `SUPER+mouse5` | Hyprspace overview *(retired on 0.57 — see §3)* |
| `SUPER+D` | Docker dashboard |
| `SUPER+SHIFT+N` | Connections (WARP + KDE Connect) |
| `SUPER+SHIFT+E` | ~~EasyEffects bypass A/B~~ — **dead** (EasyEffects replaced by serpantinum-audio; see §4) |
| `SUPER+SHIFT+C` | Caffeine (idle inhibit) |
| `SUPER+A` launcher · `SUPER+V` clipboard · `SUPER+M` volume · `SUPER+N` network · `SUPER+SHIFT+B` system | serp widgets |

*(Keybinds/apps ported from HyDE muscle memory; serp's default widget binds relocated around them.)*

# artix-installer

![](https://img.shields.io/badge/OS-Artix%20Linux-blue?logo=Artix+Linux)

A simple installer for Artix Linux. Supports OpenRC and dinit, and installs a
cohesive, minimal **Noctalia + Niri** desktop after the base install.

## Credits & Attribution

This project is based on the original artix-installer by Maxwell Anderson (Zaechus).

**Original project:** https://github.com/Zaechus/artix-installer

The original project and its source code are licensed under the GNU General Public License v3.0 (GPL-3.0).

This version contains modifications and adjustments made for personal use. AI assistance was used to help understand, review, improve, and restructure parts of the installer.

The original copyright notices and GPL license have been retained in the source files.

## What you get

| Layer | Choice |
|---|---|
| Compositor | [Niri](https://github.com/YaLTeR/niri) (scrollable tiling, Wayland) with full keybind set |
| Desktop shell | [Noctalia](https://docs.noctalia.dev) — panel (workspaces, tray, clipboard, network w/ selection, bluetooth, volume, battery, power/session menu) and a clock in `4:58 PM` format that opens a calendar panel on click; **muted Material palette generated from the wallpaper**; blurred wallpaper backdrop in niri's overview |
| Dock | Noctalia dock pinned to the **left** edge, small, auto-hiding, with running-app indicators |
| Greeter | `greetd` + `tuigreet` (`/etc/greetd/config.toml`), clock + remembered session; launches the Noctalia (Niri) session |
| App launcher | `Ctrl+Space` opens the Noctalia launcher panel |
| Terminal | [Ghostty](https://ghostty.org), Caskaydia Cove Nerd Font Mono with ligatures (`font-feature = calt`), themed via Noctalia's builtin ghostty template — `theme = noctalia` regenerates from the wallpaper palette whenever it changes (a fallback theme file ships for first boot) |
| AUR | `paru` built from source; `strata-bin` (keyboard-first file manager) and `vi` (classic ex/vi) from AUR |
| Fonts | Adwaita Sans (UI, set system-wide via dconf), Caskaydia Cove Nerd Font, Papirus-Dark icon theme (GTK3/GTK4/libadwaita defaults) |
| Browser | LibreWolf (dark, Papirus-Dark icons via system defaults) |
| Shells | `dash` is `/bin/sh`; `zsh` is the user shell with a lightweight oh-my-zsh-style `~/.zshrc`; personal aliases live in `~/.zshrc.local` |
| Editor | `vim` (~/.vimrc: syntax, relative numbers, persistent undo, 256-color statusline), plus `vi` and `nano` |
| Network | NetworkManager (+ OpenRC/dinit service), `wpa_supplicant` backend |
| Audio | PipeWire + WirePlumber as Artix **user services** (OpenRC user runlevel / dinit user instance via `dinit-user-spawn`) |
| Bluetooth | BlueZ (+ service), controlled from the Noctalia bluetooth widget and control center |
| Power | Battery widget + Noctalia session/power menu; `Mod+L` locks via Noctalia's session lock |
| Misc | `lib32` repositories disabled, wall-to-wall muted landscape wallpaper (Pexels), user in `wheel` with sudo enabled |

## Usage

1. Boot into the Artix live disk (the login and password are both `artix`).
2. Connect to the internet. Ethernet is setup automatically, and wifi is done with something like:
```
sudo rfkill unblock wifi
sudo ip link set wlan0 up
connmanctl
```
In Connman, use: `agent on`, `scan wifi`, `services`, `connect wifi_NAME`, `quit`

3. Acquire the install scripts:
```
git clone https://github.com/cryotux/artix-installer.git
cd artix-installer
```
4. Run `./install.sh`. You will be asked for language, init system, disk, swap
   size, filesystem, encryption, timezone, hostname, username, and passwords.
5. When everything finishes, `poweroff`, remove the installation media, and boot
   into Artix. After installation, networking is handled by NetworkManager —
   manage it from the Noctalia panel widget or with `nmtui`/`nmcli`.

### Preinstallation

* ISO downloads can be found at [artixlinux.org](https://artixlinux.org/download.php)
* ISO files can be burned to drives with `dd` or something like Etcher.
* `sudo dd bs=4M if=/path/to/artix.iso of=/dev/sd[drive letter] status=progress`
* A better method these days is to use [Ventoy](https://www.ventoy.net/en/index.html).

## Keybinds

The niri hotkey overlay **is** the in-system cheat sheet:
`Mod+Shift+/` (or `Ctrl+Alt+/`) shows a live list of every binding.

| Keys | Action |
|---|---|
| `Ctrl+Space` | Noctalia app launcher |
| `Ctrl+Alt+T` / `Mod+T` | Ghostty terminal |
| `Mod+S` | Control center (network, bluetooth, volume, power) |
| `Mod+Comma` | Noctalia settings |
| `Alt+Tab` | Noctalia window switcher (hold) |
| `Mod+L` | Lock screen (Noctalia session lock) |
| `Print` / `Ctrl+Print` | Screenshot region / full screen |
| `Mod+O` | Overview (zoomed-out workspaces) |
| `Mod+1..9` | Switch workspace |
| `Mod+H/J/K`, arrows | Focus columns/windows (Mod+L is lock) |
| `Mod+Q` | Close window |
| `Mod+V` | Float/tiling toggle |
| `Mod+R` | Cycle preset column widths |
| `Mod+F`, `Mod+Shift+F` | Maximize column / fullscreen window |
| `Mod+Shift+E` | Quit session |
| Volume/brightness keys | Noctalia OSD |

## Post-install notes

* **Wallpaper**: a muted landscape photo from [Pexels](https://www.pexels.com)
  is downloaded to `~/.local/share/backgrounds/wallpaper.jpg`. If the download
  fails, Noctalia falls back to its fill color and you can pick any image from
  the launcher's wallpaper provider.
* **strata** is a keyboard-first file manager installed from AUR
  (`strata-bin`, https://stratafiles.io). Unlike some other file managers it
  needs no extra pacman repository — its dependencies all come from the Artix
  repos.
* **Noctalia config**: the curated config lives in `~/.config/noctalia/config.toml`
  and can be hot-edited (`noctalia config validate` checks it). Changes made
  through Noctalia's settings GUI are stored in
  `~/.local/state/noctalia/settings.toml` on top of it. The builtin **ghostty**
  template keeps terminal colors in lockstep with the shell palette; the niri
  and GTK color templates are intentionally left off so the hand-written
  config remains the source of truth.
* **`dash` as `/bin/sh`**: system scripts run under a strict POSIX shell. This
  is exactly the behavior of `sh` on most distros, but a rare package init
  script relying on bashisms in a `#!/bin/sh` script would misbehave.
* **Customizing zsh**: put aliases/functions in `~/.zshrc.local` — it is
  sourced last and never overwritten by this installer's files.
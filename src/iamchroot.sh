#!/bin/sh -e
#
# A simple installer for Artix Linux
#
# Copyright (c) 2022 Maxwell Anderson
#
# This file is part of artix-installer.
#
# artix-installer is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# artix-installer is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License
# along with artix-installer. If not, see <https://www.gnu.org/licenses/>.

# ---------------------------------------------------------------------------
# Timezone
ln -sf "/usr/share/zoneinfo/$REGION_CITY" /etc/localtime
hwclock --systohc

# Localization
if ! grep -q "^#*$LANGCODE\.UTF-8 UTF-8" /etc/locale.gen; then
	printf "%s.UTF-8 UTF-8\n" "$LANGCODE" >>/etc/locale.gen
fi

locale-gen

printf "LANG=%s.UTF-8\n" "$LANGCODE" >/etc/locale.conf
printf "KEYMAP=%s\n" "$MY_KEYMAP" >/etc/vconsole.conf

# Hostname
printf '%s\n' "$MY_HOSTNAME" >/etc/hostname

if [ "$MY_INIT" = "openrc" ]; then
	printf 'hostname="%s"\n' "$MY_HOSTNAME" >/etc/conf.d/hostname
fi

printf "\n127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t%s.localdomain\t%s\n" \
	"$MY_HOSTNAME" "$MY_HOSTNAME" >/etc/hosts

# ---------------------------------------------------------------------------
# Configure GRUB
root_uuid=$(blkid "$PART2" -o value -s UUID)

if [ "$ENCRYPTED" = "y" ]; then
	my_params="cryptdevice=UUID=$root_uuid:root root=/dev/mapper/root"
else
	my_params=""
fi

# Btrfs root subvolume
if [ "$MY_FS" = "btrfs" ]; then
	if [ -n "$my_params" ]; then
		my_params="$my_params rootflags=subvol=root"
	else
		my_params="rootflags=subvol=root"
	fi
fi

sed -i \
	"s|^GRUB_CMDLINE_LINUX_DEFAULT.*$|GRUB_CMDLINE_LINUX_DEFAULT=\"$my_params\"|g" \
	/etc/default/grub

# Install UEFI GRUB
grub-install \
	--target=x86_64-efi \
	--efi-directory=/boot \
	--recheck

grub-install \
	--target=x86_64-efi \
	--efi-directory=/boot \
	--removable \
	--recheck

grub-mkconfig -o /boot/grub/grub.cfg

# Root password
printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd

# Enable wheel sudo permissions
sed -i '/%wheel ALL=(ALL) ALL/s/^#//g' /etc/sudoers

# ---------------------------------------------------------------------------
# User account
useradd -m -G wheel,users,audio,video,input,optical,storage,power \
	-s /usr/bin/zsh "$MY_USER"
printf '%s:%s\n' "$MY_USER" "$USER_PASSWORD" | chpasswd

# ---------------------------------------------------------------------------
# Shells: dash for /bin/sh, zsh for the user session
ln -sf /usr/bin/dash /usr/bin/sh
grep -qx '/usr/bin/dash' /etc/shells || printf '/usr/bin/dash\n' >>/etc/shells

# ---------------------------------------------------------------------------
# Services
if [ "$MY_INIT" = "openrc" ]; then
	# Boot-time plumbing
	rc-update add elogind boot
	rc-update add dbus boot
	rc-update add NetworkManager default
	rc-update add greetd default
	rc-update add bluetoothd default

	# OpenRC user services (pipewire session audio, user session bus)
	# rc-update -U writes into the "user" runlevel, started automatically
	# on login (OpenRC >= 0.60.1 user services).
	for svc in dbus pipewire pipewire-pulse wireplumber; do
		if [ -f "/etc/user/init.d/$svc" ]; then
			rc-update add -U "$svc" default
		else
			printf "warning: /etc/user/init.d/%s not found; audio may need manual setup\n" "$svc"
		fi
	done
elif [ "$MY_INIT" = "dinit" ]; then
	ln -sf /etc/dinit.d/dbus /etc/dinit.d/boot.d/
	ln -sf /etc/dinit.d/NetworkManager /etc/dinit.d/boot.d/
	ln -sf /etc/dinit.d/greetd /etc/dinit.d/boot.d/
	ln -sf /etc/dinit.d/bluetoothd /etc/dinit.d/boot.d/

	# dinit-user-spawn launches a per-user dinit daemon on login; the user
	# services below (pipe audio wireplumber bus) are managed by it.
	# elogind/logind boot.d links are already created by elogind-dinit.
	ln -sf /etc/dinit.d/dinit-user-spawn /etc/dinit.d/boot.d/

	HOME_DINIT="/home/$MY_USER/.config/dinit.d/boot.d"
	mkdir -p "$HOME_DINIT"
	for svc in dbus pipewire pipewire-pulse wireplumber; do
		if [ -f "/etc/dinit.d/user/$svc" ]; then
			ln -sf "/etc/dinit.d/user/$svc" "$HOME_DINIT/"
		else
			printf "warning: /etc/dinit.d/user/%s not found; audio may need manual setup\n" "$svc"
		fi
	done
	chown -R "$MY_USER:" "/home/$MY_USER/.config"
fi

# Configure networking and swap (kept from upstream)
if [ "$MY_INIT" = "openrc" ]; then
	sed -i '/rc_need="localmount"/s/^#//g' /etc/conf.d/swap
fi

# ---------------------------------------------------------------------------
# dconf/GTK system defaults: Papirus-Dark icons, Adwaita Sans, dark mode
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d

cat >/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF

cat >/etc/dconf/db/local.d/00-defaults <<'EOF'
[org/gnome/desktop/interface]
color-scheme="prefer-dark"
gtk-theme="Adwaita-dark"
icon-theme="Papirus-Dark"
font-name="Adwaita Sans 11"
document-font-name="Adwaita Sans 11"
monospace-font-name="CaskaydiaCove Nerd Font Mono 11"
EOF

dconf update

mkdir -p /etc/gtk-3.0 /etc/gtk-4.0
cat >/etc/gtk-3.0/settings.ini <<'EOF'
[Settings]
gtk-theme-name = Adwaita-dark
gtk-icon-theme-name = Papirus-Dark
gtk-font-name = Adwaita Sans 11
gtk-application-prefer-dark-theme = true
gtk-xft-antialias = 1
gtk-xft-hinting = 1
gtk-xft-hintstyle = hintslight
gtk-xft-rgba = rgb
EOF

cp /etc/gtk-3.0/settings.ini /etc/gtk-4.0/settings.ini

# ---------------------------------------------------------------------------
# greetd: tuigreet greeter (riced, minimal) launching the Noctalia session
if ! getent passwd greeter >/dev/null 2>&1; then
	# Some Artix builds skip sysusers.d processing; make sure the greeter
	# account exists for greetd to drop privileges to.
	useradd -r -M -d /var/lib/greetd -s /usr/sbin/nologin greeter
fi

cat >/etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --time-format '%l:%M %p' --remember --remember-session --cmd /usr/local/bin/start-niri --power-shutdown 'poweroff' --power-reboot 'reboot'"
user = "greeter"
EOF

# Point the stock niri session entry at our Artix session wrapper so the
# tuigreet session menu works on OpenRC and dinit (no systemd user manager).
sed -i \
	-e 's/^Exec=.*/Exec=\/usr\/local\/bin\/start-niri/' \
	-e 's/^Name=.*/Name=Noctalia (Niri)/' \
	/usr/share/wayland-sessions/niri.desktop

cat >/usr/local/bin/start-niri <<'EOF'
#!/bin/sh
# Noctalia + Niri session launcher for Artix (OpenRC/dinit, no systemd).
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=niri
export XDG_SESSION_DESKTOP=niri

if [ -z "$XDG_RUNTIME_DIR" ]; then
	XDG_RUNTIME_DIR="/run/user/$(id -u)"
	export XDG_RUNTIME_DIR
fi
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
	mkdir -m 700 -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
fi

# Reuse the user session bus created by the user service manager when it
# exists; otherwise start one around the compositor.
if [ -S "$XDG_RUNTIME_DIR/bus" ]; then
	DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
	export DBUS_SESSION_BUS_ADDRESS
	exec niri
else
	exec dbus-run-session -- niri
fi
EOF

chmod 755 /usr/local/bin/start-niri

# ---------------------------------------------------------------------------
# User configuration
UHOME="/home/$MY_USER"

# --- zsh: lightweight oh-my-zsh-style setup
mkdir -p "$UHOME/.config"

cat >"$UHOME/.zshrc" <<'EOF'
# ~/.zshrc - lightweight, oh-my-zsh-style setup without the framework.
# Personal aliases and overrides belong in ~/.zshrc.local (sourced below).

# --- History ---
mkdir -p "$HOME/.cache/zsh"
HISTFILE="$HOME/.cache/zsh/history"
HISTSIZE=10000
SAVEHIST=10000
setopt share_history hist_ignore_dups hist_ignore_space
setopt hist_reduce_blanks hist_expire_dups_first

# --- Completion ---
autoload -Uz compinit && compinit -d "$HOME/.cache/zsh/zcompdump"
zmodload zsh/complist
setopt complete_in_word
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*:descriptions' format '%F{cyan}-- %d --%f'
autoload -Uz colors && colors

# --- Prompt (with git branch via vcs_info) ---
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats '%F{8}(%F{magenta}%b%f)'
setopt prompt_subst
PROMPT='%F{cyan}%1~%f ${vcs_info_msg_0_} %(?.%F{magenta}❯.%F{red}❯)%f '

# --- Behaviour ---
setopt auto_cd
setopt interactive_comments

# --- Key handling ---
bindkey -e
bindkey '^[[3;5~' kill-word

# --- Plugins (system-wide, Artix package paths) ---
[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
	source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# syntax highlighting must be sourced last
[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
	source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# --- Personal configuration ---
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
EOF

cat >"$UHOME/.zshrc.local" <<'EOF'
# ~/.zshrc.local - your personal aliases, functions, and overrides.
# Sourced at the end of ~/.zshrc. This file is yours; edit freely.

# Sensible defaults to start with:
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ll='ls -lahF'
alias la='ls -A'
alias v='vim'
alias f='strata'
alias update='paru -Syu'
alias cleanup='paru -Sc'
alias h='history | tail -50'

# Uncomment and extend as you like:
# alias ..='cd ..'
# alias ports='ss -tulpn'

export EDITOR=vim
EOF

# --- vim: optimal no-plugin setup
cat >"$UHOME/.vimrc" <<'EOF'
" ~/.vimrc - a complete, plugin-free setup installed by artix-installer.

syntax on
set background=dark
filetype plugin indent on

" Line numbers and focus
set number
set relativenumber
set cursorline
set signcolumn=yes
set scrolloff=5
set sidescrolloff=8

" Search
set hlsearch
set incsearch
set ignorecase
set smartcase
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

" Indentation (4-wide default, 2-wide for web/config filetypes)
set expandtab
set smarttab
set shiftwidth=4
set softtabstop=4
set tabstop=4
autocmd FileType yaml,html,css,javascript,typescript,json,toml,sh,zsh,markdown
	\ setlocal shiftwidth=2 softtabstop=2 tabstop=2
set autoindent
set smartindent

" Undo/swap persistence (self-maintaining cache dirs)
set nobackup
set undofile
if !isdirectory(expand('~/.cache/vim/undo'))
	call mkdir(expand('~/.cache/vim/undo'), 'p')
endif
set undodir=~/.cache/vim/undo//
if !isdirectory(expand('~/.cache/vim/swap'))
	call mkdir(expand('~/.cache/vim/swap'), 'p')
endif
set directory=~/.cache/vim/swap//

" Backspace behaves like modern editors
set backspace=indent,eol,start

" UI
set wildmenu
set wildmode=longest:full,full
set showcmd
set laststatus=2
set statusline=%f\ %m%r%h%w%=%y\ %p%%\ %l:%c
set showmatch
set wrap off
set mouse=a
set inccommand=nosplit
set splitbelow
set splitright

" Clipboard integration (Artix vim is built with +clipboard)
set clipboard=unnamedplus

" Handy extras
nnoremap gV `[v`]
EOF

# --- Ghostty terminal (Caskaydia Cove Nerd Mono + ligatures)
mkdir -p "$UHOME/.config/ghostty"
cat >"$UHOME/.config/ghostty/config" <<'EOF'
# Ghostty - tuned to blend into the Noctalia desktop.

# Caskaydia Cove Nerd Font Mono with ligatures
font-family = CaskaydiaCove Nerd Font Mono
font-feature = calt
font-size = 12

# Colors come from the 'noctalia' theme: a fallback ships below and Noctalia
# rewrites it from the wallpaper-generated palette (builtin ghostty template).
theme = noctalia
cursor-style = block
cursor-style-blink = false

# Tiling-friendly windowing
window-decoration = false
window-padding-x = 14
window-padding-y = 12
window-padding-balance = true
window-padding-color = background
background-opacity = 0.93

# Desktop niceties
mouse-hide-while-typing = true
copy-on-select = clipboard
EOF

# Fallback 'noctalia' theme for Ghostty, replaced at runtime by Noctalia's
# template so terminal colors always match the shell palette.
cat >"$UHOME/.config/ghostty/themes/noctalia" <<'EOF'
palette = 0=#23252F
palette = 1=#C27C86
palette = 2=#8CA886
palette = 3=#C2AE86
palette = 4=#8698C5
palette = 5=#A98FC5
palette = 6=#82B2B8
palette = 7=#BFC2CC
palette = 8=#3A3D4A
palette = 9=#D4878F
palette = 10=#9BB693
palette = 11=#D0BD95
palette = 12=#96A9D3
palette = 13=#B69DD0
palette = 14=#92C0C5
palette = 15=#E0E2EA
background = #1A1C26
foreground = #D5D8E1
cursor-color = #9DA6C7
cursor-text = #1A1C26
selection-background = #2E3244
selection-foreground = #E3E6EF
EOF

# --- Noctalia (panel, dock, wallpaper, theme)
mkdir -p "$UHOME/.config/noctalia"
cat >"$UHOME/.config/noctalia/config.toml" <<'EOF'
# Noctalia - curated configuration installed by artix-installer.
# Docs: https://docs.noctalia.dev - GUI changes land in
# ~/.local/state/noctalia/settings.toml and override these values.

[theme]
mode = "dark"
source = "wallpaper"           # Material palette is generated from the wallpaper
wallpaper_scheme = "muted"     # keeps everything quiet and cohesive
pure_black_dark = false

[shell]
font_family = "Adwaita Sans"

[theme.templates]
enable_builtin_templates = true
builtin_ids = ["ghostty"]  # keep terminal colors synced with the system palette

[wallpaper]
enabled = true
fill_mode = "crop"
fill_color = "#1A1C26"
directory = "__UHOME__/.local/share/backgrounds"

[wallpaper.default]
path = "__UHOME__/.local/share/backgrounds/wallpaper.jpg"

[backdrop]
enabled = true                 # blurred wallpaper backdrop for niri's overview
blur_intensity = 0.5
tint_intensity = 0.3

[bar]
order = ["main"]

[bar.main]
position = "top"
background_opacity = 0.85
start = ["workspaces"]
center = ["clock"]     # canonical key for the middle lane ("4:58 PM")
end = ["tray", "clipboard", "network", "bluetooth", "volume", "battery", "session"]

[widget.clock]
format = "{:%-l:%M %p}"        # "4:58 PM"; left click opens the calendar panel

[dock]
enabled = true
position = "left"              # small auto-hiding dock on the left edge
auto_hide = true
show_running = true            # running-app indicators under pinned icons
icon_size = 40
main_axis_padding = 10
cross_axis_padding = 6
item_spacing = 5
background_opacity = 0.85
radius = 14
margin_edge = 0                # flush with the screen edge
EOF

# --- niri compositor (full config, niri defaults + Noctalia wiring)
mkdir -p "$UHOME/.config/niri"
cat >"$UHOME/.config/niri/config.kdl" <<'EOF'
// Noctalia + Niri - installed by artix-installer.
// Reference: https://niri-wm.github.io/niri/Configuration:-Introduction
// "Mod" is Super.

// Noctalia must start with the session (panel, dock, launcher, lock, ...).
spawn-at-startup "noctalia"

input {
    keyboard {
        repeat-delay 250
        repeat-rate 35
        xkb {
            layout "__KEYMAP__"
        }
    }
    touchpad {
        tap true
        natural-scroll true
    }
}

layout {
    // Let Noctalia's wallpaper layer show through.
    background-color "transparent"

    gaps 8

    border {
        width 2
        active-color "#6C79A6"
        inactive-color "transparent"
        radius 8
    }
    focus-ring {
        off
    }
}

// Noctalia renders a blurred, tinted copy of the wallpaper into niri's
// overview backdrop; this rule makes that surface visible.
layer-rule {
    match namespace="^noctalia-backdrop"
    place-within-backdrop true
}

binds {
    // Cheatsheet: niri's hotkey overlay lists every binding below.
    Mod+Shift+Slash hotkey-overlay-title="Keyboard Shortcuts Cheat Sheet" { show-hotkey-overlay; }
    Ctrl+Alt+Slash hotkey-overlay-title="Keyboard Shortcuts Cheat Sheet" { show-hotkey-overlay; }

    // Programs.
    Mod+T hotkey-overlay-title="Open a Terminal: Ghostty" { spawn "ghostty"; }
    Ctrl+Alt+T hotkey-overlay-title="Open a Terminal: Ghostty" { spawn "ghostty"; }
    Ctrl+Space hotkey-overlay-title="App Launcher" { spawn-sh "noctalia msg panel-toggle launcher"; }
    Mod+Space hotkey-overlay-title="App Launcher (alias)" { spawn-sh "noctalia msg panel-toggle launcher"; }
    Mod+S hotkey-overlay-title="Control Center" { spawn-sh "noctalia msg panel-toggle control-center"; }
    Mod+Comma hotkey-overlay-title="Noctalia Settings" { spawn-sh "noctalia msg settings-toggle"; }
    Alt+Tab hotkey-overlay-title="Window Switcher" { spawn-sh "noctalia msg window-switcher hold"; }
    Mod+L hotkey-overlay-title="Lock the Screen" { spawn-sh "noctalia msg session lock"; }

    // Media and brightness through Noctalia.
    XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "noctalia msg volume-up"; }
    XF86AudioLowerVolume allow-when-locked=true { spawn-sh "noctalia msg volume-down"; }
    XF86AudioMute allow-when-locked=true { spawn-sh "noctalia msg volume-mute"; }
    XF86MonBrightnessUp allow-when-locked=true { spawn-sh "noctalia msg brightness-up"; }
    XF86MonBrightnessDown allow-when-locked=true { spawn-sh "noctalia msg brightness-down"; }

    // Screenshots through Noctalia (lands in ~/Pictures, policy under [shell.screenshot]).
    Print hotkey-overlay-title="Screenshot: Select Region" { spawn-sh "noctalia msg screenshot-region"; }
    Ctrl+Print hotkey-overlay-title="Screenshot: Full Screen" { spawn-sh "noctalia msg screenshot-fullscreen"; }

    // Overview: zoomed-out view of workspaces and windows.
    Mod+O repeat=false { toggle-overview; }

    // Windows.
    Mod+Q repeat=false { close-window; }
    Mod+Shift+E { quit; }
    Ctrl+Alt+Delete { quit; }
    Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }

    // Focus and movement.
    Mod+Left  { focus-column-left; }
    Mod+Down  { focus-window-down; }
    Mod+Up    { focus-window-up; }
    Mod+Right { focus-column-right; }
    Mod+H     { focus-column-left; }
    Mod+J     { focus-window-down; }
    Mod+K     { focus-window-up; }

    Mod+Ctrl+Left  { move-column-left; }
    Mod+Ctrl+Down  { move-window-down; }
    Mod+Ctrl+Up    { move-window-up; }
    Mod+Ctrl+Right { move-column-right; }
    Mod+Ctrl+H     { move-column-left; }
    Mod+Ctrl+J     { move-window-down; }
    Mod+Ctrl+K     { move-window-up; }
    Mod+Ctrl+L     { move-column-right; }

    Mod+Home { focus-column-first; }
    Mod+End  { focus-column-last; }
    Mod+Ctrl+Home { move-column-to-first; }
    Mod+Ctrl+End  { move-column-to-last; }

    Mod+Shift+Left  { focus-monitor-left; }
    Mod+Shift+Down  { focus-monitor-down; }
    Mod+Shift+Up    { focus-monitor-up; }
    Mod+Shift+Right { focus-monitor-right; }
    Mod+Shift+H     { focus-monitor-left; }
    Mod+Shift+J     { focus-monitor-down; }
    Mod+Shift+K     { focus-monitor-up; }
    Mod+Shift+L     { focus-monitor-right; }

    Mod+Shift+Ctrl+Left  { move-column-to-monitor-left; }
    Mod+Shift+Ctrl+Down  { move-column-to-monitor-down; }
    Mod+Shift+Ctrl+Up    { move-column-to-monitor-up; }
    Mod+Shift+Ctrl+Right { move-column-to-monitor-right; }
    Mod+Shift+Ctrl+H     { move-column-to-monitor-left; }
    Mod+Shift+Ctrl+J     { move-column-to-monitor-down; }
    Mod+Shift+Ctrl+K     { move-column-to-monitor-up; }
    Mod+Shift+Ctrl+L     { move-column-to-monitor-right; }

    // Workspaces.
    Mod+Page_Down      { focus-workspace-down; }
    Mod+Page_Up        { focus-workspace-up; }
    Mod+U              { focus-workspace-down; }
    Mod+I              { focus-workspace-up; }
    Mod+Ctrl+Page_Down { move-column-to-workspace-down; }
    Mod+Ctrl+Page_Up   { move-column-to-workspace-up; }
    Mod+Ctrl+U         { move-column-to-workspace-down; }
    Mod+Ctrl+I         { move-column-to-workspace-up; }

    Mod+Shift+Page_Down { move-workspace-down; }
    Mod+Shift+Page_Up   { move-workspace-up; }
    Mod+Shift+U         { move-workspace-down; }
    Mod+Shift+I         { move-workspace-up; }

    Mod+WheelScrollDown      cooldown-ms=150 { focus-workspace-down; }
    Mod+WheelScrollUp        cooldown-ms=150 { focus-workspace-up; }
    Mod+Ctrl+WheelScrollDown cooldown-ms=150 { move-column-to-workspace-down; }
    Mod+Ctrl+WheelScrollUp   cooldown-ms=150 { move-column-to-workspace-up; }

    Mod+WheelScrollRight      { focus-column-right; }
    Mod+WheelScrollLeft       { focus-column-left; }
    Mod+Ctrl+WheelScrollRight { move-column-right; }
    Mod+Ctrl+WheelScrollLeft  { move-column-left; }

    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+6 { focus-workspace 6; }
    Mod+7 { focus-workspace 7; }
    Mod+8 { focus-workspace 8; }
    Mod+9 { focus-workspace 9; }
    Mod+Ctrl+1 { move-column-to-workspace 1; }
    Mod+Ctrl+2 { move-column-to-workspace 2; }
    Mod+Ctrl+3 { move-column-to-workspace 3; }
    Mod+Ctrl+4 { move-column-to-workspace 4; }
    Mod+Ctrl+5 { move-column-to-workspace 5; }
    Mod+Ctrl+6 { move-column-to-workspace 6; }
    Mod+Ctrl+7 { move-column-to-workspace 7; }
    Mod+Ctrl+8 { move-column-to-workspace 8; }
    Mod+Ctrl+9 { move-column-to-workspace 9; }

    // Columns into and out of columns.
    Mod+BracketLeft  { consume-or-expel-window-left; }
    Mod+BracketRight { consume-or-expel-window-right; }
    Mod+Period       { expel-window-from-column; }

    // Sizing.
    Mod+R { switch-preset-column-width; }
    Mod+Shift+R { switch-preset-column-width-back; }
    Mod+Ctrl+R { reset-window-height; }
    Mod+F { maximize-column; }
    Mod+Shift+F { fullscreen-window; }
    Mod+M { maximize-window-to-edges; }
    Mod+Ctrl+F { expand-column-to-available-width; }
    Mod+C { center-column; }
    Mod+Ctrl+C { center-visible-columns; }
    Mod+Minus { set-column-width "-10%"; }
    Mod+Equal { set-column-width "+10%"; }
    Mod+Shift+Minus { set-window-height "-10%"; }
    Mod+Shift+Equal { set-window-height "+10%"; }

    // Floating.
    Mod+V       { toggle-window-floating; }
    Mod+Shift+V { switch-focus-between-floating-and-tiling; }
    Mod+W { toggle-column-tabbed-display; }

    // Monitors off; any input wakes them.
    Mod+Shift+P { power-off-monitors; }
}
EOF

# Substitute per-install values
sed -i \
	-e "s|__UHOME__|$UHOME|g" \
	"$UHOME/.config/noctalia/config.toml" \
	"$UHOME/.config/niri/config.kdl"
sed -i "s|__KEYMAP__|$MY_KEYMAP|g" "$UHOME/.config/niri/config.kdl"

# --- Wallpaper: muted landscape photo (Pexels), full resolution
BG_DIR="$UHOME/.local/share/backgrounds"
install -d -o "$MY_USER" -g "$MY_USER" "$BG_DIR"
BG_FILE="$BG_DIR/wallpaper.jpg"
BG_OK=0
for bg_url in \
	"https://images.pexels.com/photos/326055/pexels-photo-326055.jpeg?auto=compress&cs=tinysrgb&w=3840" \
	"https://images.pexels.com/photos/1323550/pexels-photo-1323550.jpeg?auto=compress&cs=tinysrgb&w=3840" \
	"https://images.pexels.com/photos/572897/pexels-photo-572897.jpeg?auto=compress&cs=tinysrgb&w=3840"; do
	if curl -fsSL "$bg_url" -o "$BG_FILE"; then
		BG_OK=1
		break
	fi
done
if [ "$BG_OK" = "1" ]; then
	chown "$MY_USER:" "$BG_FILE"
else
	rm -f "$BG_FILE"
	printf "warning: wallpaper download failed; Noctalia will use its fill colour\n"
fi

# Standard XDG user directories
su -l "$MY_USER" -c 'xdg-user-dirs-update' >/dev/null 2>&1 || true

# Ownership pass
chown -R "$MY_USER:" "$UHOME/.config" "$UHOME/.cache" 2>/dev/null || true
chmod 700 "$UHOME/.cache" 2>/dev/null || true

# ---------------------------------------------------------------------------
# mkinitcpio (Btrfs/encryption hooks) and initramfs regeneration
if [ "$MY_FS" = "btrfs" ]; then
	sed -i \
		's|^BINARIES=.*$|BINARIES=(/usr/bin/btrfs)|' \
		/etc/mkinitcpio.conf
fi

if [ "$ENCRYPTED" = "y" ]; then
	sed -i \
		's|^HOOKS=.*$|HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)|' \
		/etc/mkinitcpio.conf
else
	sed -i \
		's|^HOOKS=.*$|HOOKS=(base udev autodetect keyboard keymap modconf block filesystems fsck)|' \
		/etc/mkinitcpio.conf
fi

/usr/bin/mkinitcpio -P

# ---------------------------------------------------------------------------
# pacman configuration: lib32 repos disabled + niceties
awk '
	/^\[lib32/ { skip = 1 }
	/^\[/      { if ($0 !~ /^\[lib32/) skip = 0 }
	{
		if (skip && $0 !~ /^#/) {
			print "# lib32 disabled by artix-installer: " $0
		} else {
			print
		}
	}
' /etc/pacman.conf >/etc/pacman.conf.new
mv /etc/pacman.conf.new /etc/pacman.conf

grep -q '^Color$' /etc/pacman.conf || sed -i 's/^#Color$/Color/' /etc/pacman.conf
grep -q '^ParallelDownloads' /etc/pacman.conf || \
	sed -i 's/^#ParallelDownloads$/ParallelDownloads = 5/' /etc/pacman.conf

# ---------------------------------------------------------------------------
# AUR layer: paru (helper), strata (file manager), vi (editor)
# Built as the user via the snapshot + makepkg + pacman -U dance.
aur_build() {
	pkg="$1"
	dir="/tmp/aurbuild/$pkg"
	rm -rf "$dir"
	mkdir -p "$dir"
	curl -fsSL "https://aur.archlinux.org/cgit/aur.git/snapshot/$pkg.tar.gz" \
		-o "/tmp/aurbuild/$pkg.tar.gz"
	tar -xf "/tmp/aurbuild/$pkg.tar.gz" -C "$dir"
	chown -R "$MY_USER:" "$dir"
	su -l "$MY_USER" -c "cd '$dir/$pkg' && makepkg -f"
	pacman -U --noconfirm "$dir/$pkg"/*.pkg.tar.zst
}

# paru - the AUR helper (mandate)
aur_build paru

# strata - keyboard-first file manager (mandate), from AUR. Unlike flea-bin it
# has no omarchy meta dependency, so no extra repository is needed.
aur_build strata-bin

# vi - the classic vi (mandate: "vim, vi and nano added"), from AUR
aur_build vi

rm -rf /tmp/aurbuild

# Best-effort validation of the Noctalia configuration we generated.
su -l "$MY_USER" -c 'timeout 30 noctalia config validate' >/dev/null 2>&1 ||
	printf "note: noctalia config validate reported issues; run it manually after first boot\n"

printf '\nDone. Reboot into Noctalia (Niri) via tuigreet.\n'
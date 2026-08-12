#!/usr/bin/env bash
# setup.sh -- Aaryan's workstation, from a fresh machine to working.
# Runs on Ubuntu and macOS. Idempotent; every config it replaces is copied to
# <file>.bak.<stamp> first. Safe for an agent to run unattended: it never
# deletes, never prints a secret, and collects what it could not do into a
# list printed at the end instead of stopping.
#
#   ./setup.sh
#
# Window management is the same model on both machines -- a horizontal strip of
# windows you scroll through. niri on Linux, paneru on macOS, identical keys:
# the modifier is the 3rd key from the left (Super on a PC, Option on a Mac).

set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
OS="$(uname -s)"
WARNINGS=()

log()  { printf '\n\033[32m==>\033[0m %s\n' "$*"; }
step() { printf '\033[2m  ·\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*"; WARNINGS+=("$*"); }
have() { command -v "$1" >/dev/null 2>&1; }

# -L dereferences: a symlinked dotfile must not back up as another link to the
# file we are about to overwrite, or both copies die.
bak() { if [ -s "$1" ]; then cp -aL "$1" "$1.bak.$STAMP"; step "backed up $1"; fi; }

TOOLS="ripgrep fzf zoxide jq gh node"

# ---------------------------------------------------------------- linux

linux_packages() {
  log "Packages (apt)"
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  # one call each: apt aborts the whole transaction on a single unknown name
  for p in git curl unzip zsh fontconfig ripgrep fzf zoxide jq nodejs gh \
           zsh-autosuggestions zsh-syntax-highlighting ghostty; do
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$p" >/dev/null 2>&1 \
      || warn "$p: not in the archive on this release"
  done
  have code   || sudo snap install code --classic >/dev/null 2>&1 \
    || warn "VS Code: code.visualstudio.com/docs/setup/linux"
  have atuin  || curl -fsSL https://setup.atuin.sh | bash || warn "atuin install failed"
}

linux_niri() {
  log "niri (scrollable tiling)"
  if have niri; then step "present"; else
    # dms adds the bar, launcher and notifications -- niri alone is a bare compositor
    sudo add-apt-repository -y ppa:avengemedia/danklinux >/dev/null 2>&1 \
      && sudo add-apt-repository -y ppa:avengemedia/dms >/dev/null 2>&1 \
      && sudo apt-get update -qq \
      && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y niri dms >/dev/null \
      || warn "niri PPA failed -- github.com/YaLTeR/niri/wiki/Getting-Started"
  fi
  write_niri_config
}

# ---------------------------------------------------------------- macos

mac_packages() {
  log "Packages (brew)"
  have brew || { warn "install Homebrew first: brew.sh"; return 0; }
  # shellcheck disable=SC2086
  brew install $TOOLS atuin paneru zsh-autosuggestions zsh-syntax-highlighting \
    >/dev/null || warn "some brew formulae failed"
  brew list --cask ghostty >/dev/null 2>&1 || brew install --cask ghostty >/dev/null 2>&1 \
    || warn "ghostty cask failed"
}

mac_paneru() {
  log "paneru (scrollable tiling)"
  write_paneru_config
  have paneru || { warn "paneru not installed"; return 0; }
  paneru install >/dev/null 2>&1 || true
  paneru restart >/dev/null 2>&1 || paneru start >/dev/null 2>&1 || true
  # a running daemon that cannot answer has no Accessibility grant yet
  if ! paneru query active >/dev/null 2>&1; then
    warn "paneru needs Accessibility: System Settings > Privacy & Security > Accessibility"
  fi
  # macOS claims 3- and 4-finger horizontal swipe for Spaces, so paneru never
  # sees the gesture; alt+scroll works regardless. Left for the operator to decide.
  if [ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture 2>/dev/null || echo 0)" != "0" ]; then
    step "4-finger swipe belongs to macOS Spaces -- use option+scroll, or turn it off in Trackpad settings"
  fi
}

# ---------------------------------------------------------------- shared

font() {
  log "JetBrains Mono Nerd Font"
  if fc-list 2>/dev/null | grep -qi "jetbrainsmono nerd"; then step "present"; return 0; fi
  mkdir -p "$HOME/.local/share/fonts"
  ( cd "$HOME/.local/share/fonts" \
    && curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
    && unzip -oq JetBrainsMono.zip && rm -f JetBrainsMono.zip ) || { warn "font download failed"; return 0; }
  have fc-cache && { fc-cache -f >/dev/null || warn "fc-cache failed"; }
}

write_ghostty_config() {
  mkdir -p "$HOME/.config/ghostty"
  bak "$HOME/.config/ghostty/config"
  cat > "$HOME/.config/ghostty/config" <<'EOF'
theme = dark:Catppuccin Mocha,light:Catppuccin Latte
font-family = "JetBrainsMono Nerd Font"
font-size = 13
window-padding-x = 12
window-padding-y = 12
background-opacity = 0.97
copy-on-select = clipboard
scrollback-limit = 104857600
shell-integration-features = cursor,sudo,title,ssh-env,ssh-terminfo

# ctrl+shift is identical on both keyboards and clear of the window manager.
# Same letters as the window manager: hjkl moves focus, the modifier says which.
keybind = ctrl+shift+h=goto_split:left
keybind = ctrl+shift+j=goto_split:down
keybind = ctrl+shift+k=goto_split:up
keybind = ctrl+shift+l=goto_split:right
keybind = ctrl+shift+e=new_split:right
keybind = ctrl+shift+o=new_split:down
keybind = ctrl+shift+z=toggle_split_zoom
keybind = ctrl+shift+t=new_tab
keybind = ctrl+shift+w=close_surface
keybind = ctrl+shift+r=reload_config
keybind = ctrl+shift+one=goto_tab:1
keybind = ctrl+shift+two=goto_tab:2
keybind = ctrl+shift+three=goto_tab:3
EOF
  if have ghostty && ! ghostty +validate-config >/dev/null 2>&1; then
    warn "ghostty config has an unknown key -- run 'ghostty +validate-config'"
  fi
}

write_niri_config() {
  mkdir -p "$HOME/.config/niri"
  bak "$HOME/.config/niri/config.kdl"
  cat > "$HOME/.config/niri/config.kdl" <<'EOF'
input {
    keyboard {
        xkb {
            options "ctrl:nocaps"
        }
        repeat-delay 200
        repeat-rate 45
    }
    touchpad {
        tap
        natural-scroll
        dwt                       // ignore the pad while typing
    }
    focus-follows-mouse
}

layout {
    gaps 8
    center-focused-column "never"
    preset-column-widths {        // what Mod+R cycles through
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
    }
    default-column-width { proportion 0.5; }
    focus-ring {
        width 2
        active-color "#cba6f7"
        inactive-color "#313244"
    }
}

prefer-no-csd
screenshot-path "~/Pictures/Screenshots/%Y-%m-%d %H-%M-%S.png"

// Mod is Super: 3rd key from the left, the same physical slot as Option on the
// Mac, where paneru binds the identical letters. W and brackets rather than
// F/B/Period because those are zsh word-navigation under macos-option-as-alt.
binds {
    Mod+T { spawn "ghostty"; }
    Mod+Q { close-window; }

    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }

    Mod+Shift+H { move-column-left; }
    Mod+Shift+L { move-column-right; }

    Mod+BracketLeft  { consume-or-expel-window-left; }
    Mod+BracketRight { consume-or-expel-window-right; }

    Mod+R { switch-preset-column-width; }
    Mod+Shift+R { switch-preset-column-width-back; }
    Mod+W { maximize-column; }
    Mod+C { center-column; }

    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Shift+2 { move-column-to-workspace 2; }
    Mod+Shift+3 { move-column-to-workspace 3; }

    Print { screenshot; }
    Mod+Shift+E { quit; }
}
EOF
  if have niri && ! niri validate >/dev/null 2>&1; then
    warn "niri config did not validate -- run 'niri validate'"
  fi
}

write_paneru_config() {
  mkdir -p "$HOME/.config/paneru"
  bak "$HOME/.config/paneru/paneru.toml"
  cat > "$HOME/.config/paneru/paneru.toml" <<'EOF'
# Modifier is Option: 3rd key from the left, the same physical slot as Super on
# a PC keyboard, where niri binds the identical letters.
#
#   mac    fn  control  option  command
#   linux  ctrl  fn     super   alt
#                       ^^^^^^ this one, both machines
#
# Letters dodge zsh word-navigation (alt+f, alt+b, alt+.) because
# macos-option-as-alt is on in the ghostty config and those still have to work.

[options]
focus_follows_mouse = true
mouse_follows_focus = true

[bindings]
window_focus_west  = "alt - h"
window_focus_east  = "alt - l"
window_focus_south = "alt - j"
window_focus_north = "alt - k"

window_swap_west = "alt + shift - h"
window_swap_east = "alt + shift - l"

window_stack   = "alt - leftbracket"
window_unstack = "alt - rightbracket"

window_resize    = "alt - r"
window_shrink    = "alt + shift - r"
window_fullwidth = "alt - w"
window_center    = "alt - c"
window_equalize  = "alt - e"

window_virtualnum_1 = "alt - 1"
window_virtualnum_2 = "alt - 2"
window_virtualnum_3 = "alt - 3"
window_virtualmovenum_1 = "alt + shift - 1"
window_virtualmovenum_2 = "alt + shift - 2"
window_virtualmovenum_3 = "alt + shift - 3"

window_nextdisplay = "alt - n"
window_manage = "alt - m"

restart = "ctrl + alt - r"
quit    = "ctrl + alt - q"

[swipe]
sensitivity = 0.5
continuous = false

[swipe.gesture]
fingers_count = 4           # macOS Spaces owns this until you turn it off in Trackpad settings
vertical = true

[swipe.scroll]
modifier = "alt"            # option + two-finger scroll slides the strip; works with no system change
vertical_modifier = "shift"
EOF
}

write_zshrc() {
  bak "$HOME/.zshrc"
  local share=/usr/share
  [ -n "${HOMEBREW_PREFIX:-}" ] && share="$HOMEBREW_PREFIX/share"
  cat > "$HOME/.zshrc" <<EOF
# managed by setup.sh -- edits here are overwritten on the next run
export PATH="\$HOME/.local/bin:\$PATH"

HISTSIZE=100000; SAVEHIST=100000; HISTFILE=~/.zsh_history
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS
setopt AUTO_CD INTERACTIVE_COMMENTS

autoload -Uz compinit && compinit -C
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu select

source $share/zsh-autosuggestions/zsh-autosuggestions.zsh 2>/dev/null

_have() { command -v "\$1" >/dev/null 2>&1; }
_have zoxide && eval "\$(zoxide init zsh)"
_have atuin  && eval "\$(atuin init zsh)"
_have fzf    && source <(fzf --zsh)
_have code   && export EDITOR='code --wait'

# last, on purpose: it wraps every ZLE widget defined before it, ctrl-R included
source $share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 2>/dev/null
EOF
}

# ~/.claude is the agent layer: CLAUDE.md, rules, agents, skills, commands.
agent_layer() {
  have gh || { warn "gh missing -- ~/.claude agent layer not installed"; return 0; }
  if ! gh auth status >/dev/null 2>&1; then
    if [ -t 0 ]; then gh auth login || { warn "gh auth did not complete"; return 0; }
    else warn "run 'gh auth login', then re-run this script"; return 0; fi
  fi
  log "Global agent config"
  local d="$HOME/.claude"
  if [ -d "$d/.git" ]; then
    git -C "$d" pull --rebase --autostash || warn "could not pull claude-global-config"
    return 0
  fi
  # Claude Code creates ~/.claude first, so clone-into-nonempty fails: graft instead.
  # projects/ is gigabytes of transcripts and is not ours to move.
  if [ -d "$d" ] && ! tar czf "$HOME/.claude.bak.$STAMP.tar.gz" -C "$d" \
       --exclude=projects --exclude=todos . 2>/dev/null; then
    warn "could not back up ~/.claude -- refusing to overwrite it"; return 0
  fi
  mkdir -p "$d"
  ( cd "$d" && git init -q \
    && git remote add origin https://github.com/AaryanAgrawal/claude-global-config.git \
    && GIT_TERMINAL_PROMPT=0 git fetch -q origin \
    && git checkout -f -B main origin/main ) \
    || warn "could not graft claude-global-config into ~/.claude"
  step "credentials are separate: ~/.claude/scripts/agent-setup.sh"
}

summary() {
  log "Done"
  printf '  terminal   %s\n' "$(have ghostty && echo ghostty || echo '-- missing')"
  printf '  windows    %s\n' "$(have niri && echo niri || { have paneru && echo paneru || echo '-- missing'; })"
  printf '  editor     %s\n' "$(have code && echo 'VS Code' || echo '-- missing')"
  printf '  claude     %s\n' "$(have claude && echo present || echo '-- missing')"
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    printf '\n\033[33m  %d need you:\033[0m\n' "${#WARNINGS[@]}"
    printf '    - %s\n' "${WARNINGS[@]}"
  fi
  printf '\n  Log out and back in: the shell change and the font cache both need it.\n\n'
}

main() {
  log "$OS"
  case "$OS" in
    Linux)  linux_packages; linux_niri ;;
    Darwin) mac_packages;   mac_paneru ;;
    *)      printf 'unsupported OS: %s\n' "$OS" >&2; exit 1 ;;
  esac
  font
  log "Configs"
  write_ghostty_config
  write_zshrc
  have claude || curl -fsSL https://claude.ai/install.sh | bash || warn "claude code install failed"
  have uv     || curl -LsSf https://astral.sh/uv/install.sh | sh || warn "uv install failed"
  agent_layer
  [ "${SHELL:-}" = "$(command -v zsh)" ] || chsh -s "$(command -v zsh)" || warn "run: chsh -s $(command -v zsh)"
  summary
}

main "$@"

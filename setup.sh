#!/usr/bin/env bash
# setup.sh -- Aaryan's Ubuntu laptop, from a fresh install to working.
# Idempotent. Every config it replaces is copied to <file>.bak.<stamp> first.
#
#   ./setup.sh

set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
WARNINGS=()

log()  { printf '\n\033[32m==>\033[0m %s\n' "$*"; }
step() { printf '\033[2m  ·\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*"; WARNINGS+=("$*"); }
have() { command -v "$1" >/dev/null 2>&1; }

# -L dereferences: a symlinked dotfile must not back up as another link to the
# file we are about to overwrite, or both copies die.
bak() { if [ -s "$1" ]; then cp -aL "$1" "$1.bak.$STAMP"; step "backed up $1"; fi; }

apt_get() { sudo DEBIAN_FRONTEND=noninteractive apt-get "$@"; }

packages() {
  log "Packages"
  apt_get update -qq
  # one call each: apt aborts the whole transaction on a single unknown name
  for p in git curl unzip zsh fontconfig ripgrep fzf zoxide jq nodejs gh \
           zsh-autosuggestions zsh-syntax-highlighting ghostty; do
    apt_get install -y "$p" >/dev/null 2>&1 || warn "$p: not in the archive on this release"
  done
}

install_niri() {
  log "niri (scrollable tiling)"
  if have niri; then step "present"; return 0; fi
  # dms adds the bar, launcher and notifications -- niri alone is a bare compositor
  sudo add-apt-repository -y ppa:avengemedia/danklinux >/dev/null 2>&1 \
    && sudo add-apt-repository -y ppa:avengemedia/dms >/dev/null 2>&1 \
    && apt_get update -qq \
    && apt_get install -y niri dms >/dev/null \
    || warn "niri PPA failed -- github.com/YaLTeR/niri/wiki/Getting-Started"
}

extras() {
  log "Editor, agent, runtimes"
  have code   || sudo snap install code --classic >/dev/null 2>&1 || warn "VS Code: code.visualstudio.com/docs/setup/linux"
  have claude || curl -fsSL https://claude.ai/install.sh | bash    || warn "claude code install failed"
  have uv     || curl -LsSf https://astral.sh/uv/install.sh | sh   || warn "uv install failed"
  have atuin  || curl -fsSL https://setup.atuin.sh | bash          || warn "atuin install failed"
  have op     || warn "1Password CLI: developer.1password.com/docs/cli/get-started"
}

font() {
  log "JetBrains Mono Nerd Font"
  if fc-list 2>/dev/null | grep -qi "jetbrainsmono nerd"; then step "present"; return 0; fi
  mkdir -p "$HOME/.local/share/fonts"
  ( cd "$HOME/.local/share/fonts" \
    && curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
    && unzip -oq JetBrainsMono.zip && rm -f JetBrainsMono.zip ) || { warn "font download failed"; return 0; }
  fc-cache -f >/dev/null || warn "fc-cache failed"
}

ghostty_config() {
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
# Same letters as niri: hjkl moves focus, the modifier says window vs split.
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

niri_config() {
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

zshrc() {
  bak "$HOME/.zshrc"
  cat > "$HOME/.zshrc" <<'EOF'
# managed by setup.sh -- edits here are overwritten on the next run
export PATH="$HOME/.local/bin:$PATH"

HISTSIZE=100000; SAVEHIST=100000; HISTFILE=~/.zsh_history
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS
setopt AUTO_CD INTERACTIVE_COMMENTS

autoload -Uz compinit && compinit -C
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu select

source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh 2>/dev/null

_have() { command -v "$1" >/dev/null 2>&1; }
_have zoxide && eval "$(zoxide init zsh)"
_have atuin  && eval "$(atuin init zsh)"
_have fzf    && source <(fzf --zsh)
_have code   && export EDITOR='code --wait'

# last, on purpose: it wraps every ZLE widget defined before it, ctrl-R included
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 2>/dev/null
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
  printf '  windows    %s\n' "$(have niri && echo 'niri -- pick it at the login screen' || echo '-- missing')"
  printf '  editor     %s\n' "$(have code && echo 'VS Code' || echo '-- missing')"
  printf '  claude     %s\n' "$(have claude && echo present || echo '-- missing')"
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    printf '\n\033[33m  %d need you:\033[0m\n' "${#WARNINGS[@]}"
    printf '    - %s\n' "${WARNINGS[@]}"
  fi
  printf '\n  Log out and back in: the shell change and the font cache both need it.\n\n'
}

main() {
  packages
  install_niri
  extras
  font
  log "Configs"
  ghostty_config
  niri_config
  zshrc
  agent_layer
  [ "${SHELL:-}" = "$(command -v zsh)" ] || chsh -s "$(command -v zsh)" || warn "run: chsh -s $(command -v zsh)"
  summary
}

main "$@"

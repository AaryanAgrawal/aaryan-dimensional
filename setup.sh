#!/usr/bin/env bash
# setup.sh -- Aaryan's Linux workstation, from a fresh install to working.
# Idempotent: safe to re-run. Every config it replaces is backed up first.
#
#   ./setup.sh                 full desktop workstation
#   ./setup.sh --no-desktop    servers/containers: tools + shell, no GUI
#   ./setup.sh --no-brew       distro packages instead of Homebrew

set -euo pipefail

DESKTOP=1
USE_BREW=1
STAMP="$(date +%Y%m%d-%H%M%S)"
BREW_BIN=/home/linuxbrew/.linuxbrew/bin/brew
GLOBAL_CONFIG_REPO=AaryanAgrawal/claude-global-config

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
WARNINGS=()

log()  { printf '\n%s==>%s %s\n' "$C_OK" "$C_OFF" "$*"; }
step() { printf '%s  ·%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
warn() { printf '%s  ! %s%s\n' "$C_WARN" "$*" "$C_OFF"; WARNINGS+=("$*"); }
die()  { printf '%s==> %s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Back up before overwriting -- never silently clobber a config someone tuned.
bak() { if [ -s "$1" ]; then cp -a "$1" "$1.bak.$STAMP"; step "backed up $1"; fi; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-desktop|--server) DESKTOP=0 ;;
      --no-brew)             USE_BREW=0 ;;
      -h|--help)             sed -n '2,8p' "$0"; exit 0 ;;
      *)                     die "unknown flag: $1" ;;
    esac
    shift
  done
}

detect_distro() {
  [ -r /etc/os-release ] || die "no /etc/os-release -- unsupported system"
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO="$ID"
  FAMILY="${ID_LIKE:-$ID}"
  case "$FAMILY" in
    *debian*|*ubuntu*)  PKG=apt    ;;
    *fedora*|*rhel*)    PKG=dnf    ;;
    *arch*)             PKG=pacman ;;
    *suse*)             PKG=zypper ;;
    *) die "unsupported distro: $ID -- add it to detect_distro()" ;;
  esac
  SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO=sudo
  log "$PRETTY_NAME  ($PKG)"
}

pkg() {
  case "$PKG" in
    apt)    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
    zypper) $SUDO zypper --non-interactive install "$@" ;;
  esac
}

# ---------------------------------------------------------------- system

step_system() {
  log "System packages"
  case "$PKG" in
    apt)    $SUDO apt-get update -qq ;;
    pacman) $SUDO pacman -Sy --noconfirm >/dev/null ;;
  esac

  # zsh comes from the distro, not brew: chsh only accepts a shell in /etc/shells.
  local base=(git curl file unzip zsh tmux)
  case "$PKG" in
    apt)    pkg build-essential procps "${base[@]}" ;;
    dnf)    pkg @development-tools procps-ng "${base[@]}" ;;
    pacman) pkg base-devel procps-ng "${base[@]}" ;;
    zypper) pkg -t pattern devel_basis || pkg gcc make; pkg "${base[@]}" ;;
  esac

  if [ "$DESKTOP" -eq 1 ]; then
    case "$PKG" in
      apt)    pkg tlp powertop nmap arp-scan fontconfig || warn "some laptop tools missing" ;;
      dnf)    pkg tlp powertop nmap arp-scan fontconfig || warn "some laptop tools missing" ;;
      pacman) pkg tlp powertop nmap arp-scan fontconfig || warn "some laptop tools missing" ;;
      zypper) pkg tlp powertop nmap fontconfig || warn "some laptop tools missing" ;;
    esac
    have tlp && $SUDO systemctl enable --now tlp >/dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------- tools

step_brew() {
  [ "$USE_BREW" -eq 1 ] || return 0
  if have brew || [ -x "$BREW_BIN" ]; then step "homebrew present"; else
    log "Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || { warn "homebrew install failed -- falling back to distro packages"; USE_BREW=0; return 0; }
  fi
  # `if`, not `&&`: a trailing false test returns 1 and set -e would kill the run here
  if [ -x "$BREW_BIN" ]; then eval "$("$BREW_BIN" shellenv)"; fi
}

# Deliberately short. Everything here earns a place in the daily loop; the
# nice-to-haves (difftastic, yazi, chezmoi, glow, xh, yq...) are one brew away.
BREW_TOOLS="ripgrep fd bat eza zoxide fzf jq
  lazygit git-delta gh
  btop atuin direnv starship mosh mise neovim
  zsh-autosuggestions zsh-syntax-highlighting"

# Distro names differ and several tools simply aren't packaged -- best effort, keep going.
DISTRO_TOOLS="ripgrep fd-find bat eza zoxide fzf jq neovim"

step_tools() {
  log "CLI tools"
  if [ "$USE_BREW" -eq 1 ]; then
    # shellcheck disable=SC2086
    brew install $BREW_TOOLS || warn "some brew formulae failed -- re-run 'brew install <name>' for those"
  else
    # shellcheck disable=SC2086
    pkg $DISTRO_TOOLS || warn "some distro packages missing"
    warn "--no-brew: atuin, starship, lazygit, delta et al. are not installed"
  fi
}

step_runtimes() {
  log "Runtimes"
  # no rust by default: a toolchain is ~1.5 GB and most boxes here never build Rust
  if have mise; then
    mise use -g node@lts python@3.12 || warn "mise runtime install incomplete"
  else
    warn "mise missing -- skipping node/python/rust"
  fi
  have uv || curl -LsSf https://astral.sh/uv/install.sh | sh || warn "uv install failed"

  if have docker; then step "docker present"; else
    curl -fsSL https://get.docker.com | $SUDO sh || warn "docker install failed"
    $SUDO usermod -aG docker "$USER" 2>/dev/null || true
    step "added $USER to the docker group -- takes effect after a full logout"
  fi

  # op is how every credential on this box gets fetched; never store one in a file.
  have op || brew install 1password-cli 2>/dev/null \
    || warn "1Password CLI not installed -- https://developer.1password.com/docs/cli/get-started"
}

step_claude() {
  log "Claude Code"
  if have claude; then step "present: $(claude --version 2>/dev/null | head -1)"; else
    curl -fsSL https://claude.ai/install.sh | bash || warn "claude code install failed"
  fi
}

# ---------------------------------------------------------------- desktop

step_font() {
  [ "$DESKTOP" -eq 1 ] || return 0
  log "JetBrains Mono Nerd Font"
  if fc-list 2>/dev/null | grep -qi "jetbrainsmono nerd"; then step "already installed"; return 0; fi
  mkdir -p "$HOME/.local/share/fonts"
  ( cd "$HOME/.local/share/fonts" \
    && curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
    && unzip -oq JetBrainsMono.zip && rm -f JetBrainsMono.zip ) || { warn "font download failed"; return 0; }
  fc-cache -f >/dev/null || warn "fc-cache failed -- the font may not be visible until you log out"
}

step_ghostty() {
  [ "$DESKTOP" -eq 1 ] || return 0
  log "Ghostty"
  if have ghostty; then step "present"; return 0; fi
  case "$PKG" in
    apt)    pkg ghostty || { have snap && $SUDO snap install ghostty --classic; } \
              || warn "ghostty needs Ubuntu 26.04+ -- else see github.com/mkasberg/ghostty-ubuntu" ;;
    dnf)    pkg ghostty || warn "ghostty not in your repos -- see ghostty.org/docs/install" ;;
    pacman) pkg ghostty || warn "ghostty install failed" ;;
    *)      warn "no ghostty package for $PKG -- see ghostty.org/docs/install" ;;
  esac
}

step_niri() {
  [ "$DESKTOP" -eq 1 ] || return 0
  log "niri (scrollable tiling)"
  if have niri; then step "present"; return 0; fi
  case "$DISTRO" in
    ubuntu)
      $SUDO add-apt-repository -y ppa:avengemedia/danklinux \
        && $SUDO add-apt-repository -y ppa:avengemedia/dms \
        && $SUDO apt-get update -qq && pkg niri dms \
        || warn "niri PPA failed -- github.com/YaLTeR/niri/wiki/Getting-Started" ;;
    fedora)
      $SUDO dnf copr enable -y yalter/niri && pkg niri \
        || warn "niri copr failed -- github.com/YaLTeR/niri/wiki/Getting-Started" ;;
    arch|cachyos|endeavouros)
      pkg niri || warn "niri install failed" ;;
    *)
      warn "no niri package for $DISTRO -- github.com/YaLTeR/niri/wiki/Getting-Started" ;;
  esac
}

step_keyboard() {
  [ "$DESKTOP" -eq 1 ] || return 0
  have gsettings || return 0
  gsettings set org.gnome.desktop.input-sources xkb-options "['ctrl:nocaps']" 2>/dev/null \
    && step "caps lock -> ctrl (GNOME)" || true
  gsettings set org.gnome.desktop.peripherals.keyboard delay 200 2>/dev/null || true
  gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 22 2>/dev/null || true
}

# ---------------------------------------------------------------- configs

write_ghostty_config() {
  [ "$DESKTOP" -eq 1 ] || return 0
  mkdir -p "$HOME/.config/ghostty"
  bak "$HOME/.config/ghostty/config"
  cat > "$HOME/.config/ghostty/config" <<'EOF'
theme = dark:Catppuccin Mocha,light:Catppuccin Latte
font-family = "JetBrainsMono Nerd Font"
font-size = 13
font-feature = -calt

window-padding-x = 12
window-padding-y = 12
background-opacity = 0.97
cursor-style = block
mouse-hide-while-typing = true
copy-on-select = clipboard
confirm-close-surface = false

scrollback-limit = 104857600
shell-integration-features = cursor,sudo,title,ssh-env,ssh-terminfo

# ctrl+shift is identical on both keyboards and stays clear of the window manager.
# Same letters as niri/paneru: hjkl moves focus, the modifier says window vs split.
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
  [ "$DESKTOP" -eq 1 ] || return 0
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
        active-color "#cba6f7"    // catppuccin mauve, same as the terminal
        inactive-color "#313244"
    }
}

prefer-no-csd
screenshot-path "~/Pictures/Screenshots/%Y-%m-%d %H-%M-%S.png"

// Mod is Super: 3rd key from the left, the same physical slot as Option on a Mac,
// which is what paneru binds. Same finger, same letters, both machines.
// Letters avoid F/B/Period because on the Mac those are zsh word-navigation.
binds {
    Mod+T { spawn "ghostty"; }
    Mod+Q { close-window; }

    // scroll the strip
    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }

    // carry a window along it
    Mod+Shift+H { move-column-left; }
    Mod+Shift+L { move-column-right; }

    // stack into / out of the current column
    Mod+BracketLeft  { consume-or-expel-window-left; }
    Mod+BracketRight { consume-or-expel-window-right; }

    Mod+R { switch-preset-column-width; }
    Mod+Shift+R { switch-preset-column-width-back; }
    Mod+W { maximize-column; }
    Mod+C { center-column; }
    Mod+Shift+W { fullscreen-window; }

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

write_zshrc() {
  bak "$HOME/.zshrc"
  cat > "$HOME/.zshrc" <<'EOF'
# managed by dotfiles/setup.sh

for p in /home/linuxbrew/.linuxbrew/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [[ -x $p ]] && eval "$($p shellenv)" && break
done
export PATH="$HOME/.local/bin:$PATH"

HISTSIZE=100000; SAVEHIST=100000; HISTFILE=~/.zsh_history
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS
setopt AUTO_CD INTERACTIVE_COMMENTS

autoload -Uz compinit && compinit -C
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu select

# plugin paths differ per distro and per brew prefix -- probe instead of hardcoding
for f in zsh-autosuggestions/zsh-autosuggestions.zsh \
         zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  for d in "${HOMEBREW_PREFIX:-/nonexistent}/share" /usr/share/zsh/plugins /usr/share; do
    [[ -r "$d/$f" ]] && source "$d/$f" && break
  done
done

have() { command -v "$1" >/dev/null 2>&1; }
have starship && eval "$(starship init zsh)"
have zoxide   && eval "$(zoxide init zsh)"
have atuin    && eval "$(atuin init zsh)"
have direnv   && eval "$(direnv hook zsh)"
have mise     && eval "$(mise activate zsh)"
have fzf      && source <(fzf --zsh)

if have eza; then
  alias ls='eza --group-directories-first'
  alias ll='eza -l --git --group-directories-first'
  alias lt='eza --tree --level=2'
fi
have bat && { alias cat='bat'; export PAGER='bat --plain'; }
have lazygit && alias lg='lazygit'
have nvim && export EDITOR=nvim

alias gs='git status -sb'
alias gd='git diff'
alias ..='cd ..'
EOF
}

write_starship_config() {
  bak "$HOME/.config/starship.toml"
  mkdir -p "$HOME/.config"
  cat > "$HOME/.config/starship.toml" <<'EOF'
"$schema" = 'https://starship.rs/config-schema.json'
add_newline = true
command_timeout = 1000

format = """$directory$git_branch$git_status$python$nodejs$rust$cmd_duration
$character"""

[character]
success_symbol = "[❯](#a6e3a1)"
error_symbol = "[❯](#f38ba8)"

[directory]
style = "bold #89b4fa"
truncation_length = 3
truncate_to_repo = true

[git_branch]
style = "#cba6f7"
format = "[$branch]($style) "

[git_status]
style = "#fab387"

[cmd_duration]
min_time = 2000
style = "#9399b2"
format = "[$duration]($style) "
EOF
}

write_tmux_config() {
  bak "$HOME/.tmux.conf"
  cat > "$HOME/.tmux.conf" <<'EOF'
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 100000
set -sg escape-time 10
set -g focus-events on
setw -g mode-keys vi

bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind r source-file ~/.tmux.conf \; display "reloaded"

set -g status-style "bg=#181825,fg=#cdd6f4"
set -g status-left "#[fg=#cba6f7,bold] #S "
set -g status-right "#[fg=#9399b2] #h "
set -g window-status-current-style "fg=#fab387,bold"
EOF
}

write_git_config() {
  git config --global core.pager        "delta"
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate    true
  git config --global delta.side-by-side true
  git config --global delta.syntax-theme "Catppuccin Mocha"
  git config --global merge.conflictstyle zdiff3
  git config --global diff.colorMoved   default
  git config --global pull.rebase        true
  git config --global init.defaultBranch main
  git config --global push.autoSetupRemote true
  git config --global rerere.enabled     true
  # identity stays out of the script -- pass it in rather than baking the wrong account in
  [ -n "${GIT_NAME:-}"  ] && git config --global user.name  "$GIT_NAME"
  [ -n "${GIT_EMAIL:-}" ] && git config --global user.email "$GIT_EMAIL"
  git config --global user.email >/dev/null 2>&1 || warn "git identity unset -- GIT_NAME=.. GIT_EMAIL=.. ./setup.sh"
}

write_ssh_config() {
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/config"; chmod 600 "$HOME/.ssh/config"
  grep -q 'ControlPath ~/.ssh/cm-' "$HOME/.ssh/config" && { step "ssh config present"; return 0; }
  bak "$HOME/.ssh/config"
  cat >> "$HOME/.ssh/config" <<'EOF'

Host *
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
  ServerAliveInterval 20
  ServerAliveCountMax 3
EOF
}

step_configs() {
  log "Configs"
  write_ghostty_config
  write_niri_config
  write_zshrc
  write_starship_config
  write_tmux_config
  write_git_config
  write_ssh_config
  have bat && bat cache --build >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------- accounts

step_github() {
  have gh || { warn "gh missing -- skipping GitHub auth"; return 0; }
  log "GitHub"
  if gh auth status >/dev/null 2>&1; then step "already authenticated"; return 0; fi
  if [ -t 0 ]; then gh auth login || warn "gh auth login did not complete"
  else warn "not a terminal -- run 'gh auth login' yourself"; fi
}

# ~/.claude is the agent layer: CLAUDE.md, rules, agents, skills, commands.
step_global_config() {
  have gh || return 0
  gh auth status >/dev/null 2>&1 || { warn "not authenticated -- skipping $GLOBAL_CONFIG_REPO"; return 0; }
  log "Global agent config"
  local d="$HOME/.claude"
  if [ -d "$d/.git" ]; then
    git -C "$d" pull --rebase --autostash || warn "could not pull $GLOBAL_CONFIG_REPO"
    return 0
  fi
  # Claude Code creates ~/.claude first, so clone-into-nonempty fails: graft a repo on instead.
  [ -d "$d" ] && tar czf "$HOME/.claude.bak.$STAMP.tar.gz" -C "$HOME" .claude 2>/dev/null || true
  mkdir -p "$d"
  ( cd "$d" \
    && git init -q \
    && git remote add origin "https://github.com/$GLOBAL_CONFIG_REPO.git" \
    && git fetch -q origin \
    && git checkout -f -B main origin/main ) \
    || warn "could not graft $GLOBAL_CONFIG_REPO into ~/.claude"
  step "credentials are a separate step: ~/.claude/scripts/agent-setup.sh"
}

step_shell() {
  local zsh_path; zsh_path="$(command -v zsh || true)"
  [ -n "$zsh_path" ] || { warn "zsh not installed"; return 0; }
  [ "${SHELL:-}" = "$zsh_path" ] && { step "zsh already default"; return 0; }
  chsh -s "$zsh_path" || warn "chsh failed -- run: chsh -s $zsh_path"
}

summary() {
  log "Done"
  printf '  terminal   %s\n' "$(have ghostty && echo ghostty || echo '-- not installed')"
  printf '  shell      zsh + starship\n'
  printf '  windows    %s\n' "$(have niri && echo 'niri (pick it at the login screen)' || echo '-- not installed')"
  printf '  claude     %s\n' "$(have claude && claude --version 2>/dev/null | head -1 || echo '-- not installed')"
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    printf '\n%s  %d thing(s) need you:%s\n' "$C_WARN" "${#WARNINGS[@]}" "$C_OFF"
    printf '    - %s\n' "${WARNINGS[@]}"
  fi
  printf '\n  Log out and back in: shell change, docker group, and fonts all need it.\n'
  [ -d "$HOME/.claude/.git" ] && printf '  Then: ~/.claude/scripts/agent-setup.sh   (pulls credentials)\n'
  printf '\n'
}

main() {
  parse_args "$@"
  detect_distro
  step_system
  step_brew
  step_tools
  step_runtimes
  step_claude
  step_font
  step_ghostty
  step_niri
  step_keyboard
  step_configs
  step_github
  step_global_config
  step_shell
  summary
}

main "$@"

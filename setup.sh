#!/usr/bin/env bash
# setup.sh -- Aaryan's workstation, from a fresh machine to working.
# Runs on Ubuntu and macOS. Idempotent; every config it replaces is copied to
# <file>.bak.<stamp> first. Safe for an agent to run unattended: it never
# deletes, never prints a secret, and collects what it could not do into a
# list printed at the end instead of stopping.
#
#   ./setup.sh             install or update the workstation
#   ./setup.sh --check     read-only readiness report
#
# Window management is the same model on both machines -- a horizontal strip of
# windows you scroll through. niri on Linux, paneru on macOS, identical keys:
# the modifier is the 3rd key from the left (Super on a PC, Option on a Mac).

set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
OS="$(uname -s)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WARNINGS=()
CHECK_FAILURES=0
CHECK_SETUPS=0
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

log()  { printf '\n\033[32m==>\033[0m %s\n' "$*"; }
step() { printf '\033[2m  ·\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*"; WARNINGS+=("$*"); }
have() { command -v "$1" >/dev/null 2>&1; }

version_line() {
  "$@" 2>&1 | sed -n '1{s/[[:cntrl:]]//g; p;}' || true
}

check_row() {
  local state="$1" label="$2" detail="$3"
  printf '  %-7s %-22s %s\n' "[$state]" "$label" "$detail"
  [ "$state" = FAIL ] && CHECK_FAILURES=$((CHECK_FAILURES + 1))
  [ "$state" = SETUP ] && CHECK_SETUPS=$((CHECK_SETUPS + 1))
  return 0
}

check_section() {
  printf '\n  %s\n' "$1"
}

# -L dereferences: a symlinked dotfile must not back up as another link to the
# file we are about to overwrite, or both copies die.
bak() { if [ -s "$1" ]; then cp -aL "$1" "$1.bak.$STAMP"; step "backed up $1"; fi; }

TOOLS="ripgrep fzf zoxide jq gh node dtach"

node_major() {
  have node || { printf '0\n'; return; }
  node -v | sed 's/^v//; s/\..*//'
}

# nodesource's global prefix is root-owned, so every later `npm install -g`
# (diffity, Hermes's own installer) would fail. ~/.local is ours and on PATH.
npm_prefix_to_home() {
  have npm || return 0
  if [ "$OS" = Linux ] && [ "$(npm config get prefix 2>/dev/null)" = /usr ]; then
    npm config set prefix "$HOME/.local" >/dev/null 2>&1 || true
  fi
}

ensure_node() {
  if [ "$(node_major)" -ge 22 ]; then npm_prefix_to_home; return 0; fi
  log "Node.js 22"
  if [ "$OS" = Darwin ]; then
    if ! have brew || ! brew install node >/dev/null 2>&1; then
      warn "Node.js 22+ install failed"
    fi
    return 0
  fi
  local installer
  installer="$(mktemp)"
  if curl -fsSL https://deb.nodesource.com/setup_22.x -o "$installer" \
      && sudo -E bash "$installer" >/dev/null 2>&1 \
      && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null 2>&1; then
    step "Node.js $(node -v)"
    npm_prefix_to_home
  else
    warn "Node.js 22+ install failed -- nodejs.org/en/download"
  fi
  rm -f "$installer"
}

# ---------------------------------------------------------------- linux

linux_packages() {
  log "Packages (apt)"
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  # One call each keeps one unavailable package from blocking the rest; Hermes needs the toolchain.
  for p in git curl unzip zsh fontconfig ripgrep fzf zoxide jq gh perl dtach \
           build-essential python3 \
           zsh-autosuggestions zsh-syntax-highlighting ghostty; do
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$p" >/dev/null 2>&1 \
      || warn "$p: not in the archive on this release"
  done
  have code   || sudo snap install code --classic >/dev/null 2>&1 \
    || warn "VS Code: code.visualstudio.com/docs/setup/linux"
  have atuin  || curl -fsSL https://setup.atuin.sh | bash || warn "atuin install failed"
  ensure_node
}

linux_niri() {
  log "niri (scrollable tiling)"
  if have niri; then step "present"; else
    # A function keeps `!` from applying only to the first command in the install chain.
    install_niri_from_ppa || warn "niri PPA failed -- github.com/YaLTeR/niri/wiki/Getting-Started"
  fi
  write_niri_config
}

install_niri_from_ppa() {
  sudo add-apt-repository -y ppa:avengemedia/danklinux >/dev/null 2>&1 \
    && sudo add-apt-repository -y ppa:avengemedia/dms >/dev/null 2>&1 \
    && sudo apt-get update -qq \
    && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y niri dms >/dev/null
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
    // no focus-follows-mouse: the strip slides under a still cursor and focus would
    // jump to whatever scrolled beneath it. The keyboard drives focus.
}

layout {
    gaps 8
    center-focused-column "never"
    preset-column-widths {        // what Mod+I / Mod+O cycles, same four as paneru
        proportion 0.33333
        proportion 0.5
        proportion 0.75
        proportion 1.0
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
    Mod+Tab repeat=false { toggle-overview; }   // O is taken by grow, so overview moves here

    // Three pairs, by row: J/K across the strip, H/L inside a stack, I/O size.
    Mod+J { focus-column-left; }
    Mod+K { focus-column-right; }
    Mod+Shift+J { move-column-left; }
    Mod+Shift+K { move-column-right; }

    Mod+H { focus-window-up; }      // only matters when a column holds more than one
    Mod+L { focus-window-down; }

    Mod+I { switch-preset-column-width-back; }   // in  = smaller
    Mod+O { switch-preset-column-width; }        // out = bigger
    Mod+F { maximize-column; }
    Mod+Shift+F { fullscreen-window; }           // true fullscreen; paneru has no equivalent

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

# Both off: mouse_follows_focus warps the cursor on every focus change, and with a
# strip that slides under a still cursor, focus_follows_mouse re-focuses whatever
# scrolls beneath it. Keyboard drives focus; the mouse stays where you left it.
[options]
focus_follows_mouse = false
mouse_follows_focus = false
preset_column_widths = [0.33333, 0.5, 0.75, 1.0]   # third, half, 75%, full

[bindings]

# Three pairs, by row:  j/k across the strip · h/l within a column · i/o size.
# Shift on the horizontal pair carries the window instead of just looking at it.
# No stacking: splitting a column means half the screen height each, which is
# not enough on a laptop. Widths side by side do the same job better.

window_focus_west  = "alt - j"          # <- along the strip
window_focus_east  = "alt - k"          # -> along the strip
window_swap_west   = "alt + shift - j"  # carry the window with you
window_swap_east   = "alt + shift - k"

window_focus_north = "alt - h"          # up inside a stacked column
window_focus_south = "alt - l"          # down

window_shrink    = "alt - i"            # in  = smaller
window_resize    = "alt - o"            # out = bigger
window_fullwidth = "alt - f"            # fill the screen

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

# Manage everything, including background apps and windows with odd accessibility
# roles that paneru would normally skip. Add a floating=true rule for any window
# this makes worse -- dialogs and pickers are the usual offenders.
[windows.everything]
title = ".*"
manage = true
EOF
}

write_zshrc() {
  bak "$HOME/.zshrc"
  local share=/usr/share
  [ -n "${HOMEBREW_PREFIX:-}" ] && share="$HOMEBREW_PREFIX/share"
  cat > "$HOME/.zshrc" <<EOF
# managed by setup.sh -- edits here are overwritten on the next run
export PATH="\$HOME/.local/bin:\$HOME/.opencode/bin:\$PATH"

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
    if [ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]; then
      warn "$HOME/.claude has local changes -- kept them and skipped the config update"
    else
      git -C "$d" pull --ff-only || warn "could not update claude-global-config"
    fi
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

# The harness is the hooks, statusline, and skills under ~/.claude. Each has
# runtime needs the clone does not carry, and most fail OPEN when something is
# missing -- Claude still runs, the guard just silently does nothing.
harness_prepare() {
  local d="$HOME/.claude"
  [ -f "$d/settings.json" ] || { warn "no ~/.claude/settings.json -- harness not installed"; return 0; }
  log "Harness"

  # jq: statusline + keep-working + payment-guard all require it, all exit 0 without it
  have jq   || warn "jq missing -- statusline blank, keep-working and payment-guard silently disabled"
  have perl || warn "perl missing -- the hooks' timeout wrapper needs it"
  have node || warn "node missing -- keep-working, Linear CLI and browser skill need it"
  if have node; then
    local major; major="$(node -v | sed 's/^v//; s/\..*//')"
    [ "$major" -ge 22 ] || warn "node $major found; skills/browser needs >= 22"
  fi

  # node_modules is gitignored repo-wide, so a fresh clone has none
  local blib="$d/skills/browser/lib"
  if [ -f "$blib/package.json" ] && [ ! -d "$blib/node_modules" ]; then
    if have npm; then
      if ( cd "$blib" && npm ci --silent >/dev/null 2>&1 ); then
        step "installed skills/browser deps"
      else
        warn "npm ci failed in $blib -- browser skill will throw 'Cannot find module'"
      fi
    else
      warn "npm missing -- cannot install skills/browser deps"
    fi
  fi

  # the statusline's blocker count reads tools/ which the repo whitelist does not track
  [ -f "$d/tools/blockers/refresh-count.mjs" ] \
    || step "statusline blocker count off: tools/blockers is not in the repo -- harmless"

  # agent-setup.sh is the credential bootstrap; it needs op plus one env file
  have op || warn "1Password CLI missing -- agent-setup.sh cannot pull credentials"
  [ -f "$HOME/.config/agent/.env" ] \
    || warn "no ~/.config/agent/.env -- OP_SERVICE_ACCOUNT_TOKEN has to be placed by hand, then: ~/.claude/scripts/agent-setup.sh"

  # model drift: rules/models.md forbids 1M variants and names fable; flag, never auto-edit
  local model; model="$(jq -r '.model // empty' "$d/settings.json" 2>/dev/null || true)"
  case "$model" in
    *"[1m]"*) warn "settings.json model is '$model' -- rules/models.md forbids 1M variants" ;;
  esac

  # hooks hardcode /Users/aaryan/.claude/hooks/..., which does not exist on Linux, so
  # keep-working and payment-guard would never fire. Rewrite to this machine's HOME.
  if grep -q '/Users/aaryan/.claude/' "$d/settings.json" && [ "$HOME" != /Users/aaryan ]; then
    bak "$d/settings.json"
    sed -i.tmp "s|/Users/aaryan/.claude/|$HOME/.claude/|g" "$d/settings.json"
    rm -f "$d/settings.json.tmp"
    if jq empty "$d/settings.json" 2>/dev/null; then
      step "rewrote hook paths to $HOME/.claude"
    else
      cp "$d/settings.json.bak.$STAMP" "$d/settings.json"
      warn "settings.json did not parse after the path rewrite -- restored from backup"
    fi
  fi
}

install_agent_clis() {
  log "Agent CLIs"
  ensure_node
  have claude || curl -fsSL https://claude.ai/install.sh | bash \
    || warn "Claude Code install failed"
  have codex || curl -fsSL https://chatgpt.com/codex/install.sh | sh \
    || warn "Codex install failed"
  have opencode || curl -fsSL https://opencode.ai/install | bash \
    || warn "OpenCode install failed"
  have hermes || curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser \
    || warn "Hermes install failed"
  have openspec || npm install -g @fission-ai/openspec@latest >/dev/null 2>&1 \
    || warn "OpenSpec install failed"
  step "authentication stays separate; the readiness check names each remaining login"
}

install_dimensional_harness() {
  local source="${DIMENSIONAL_HARNESS_SOURCE:-$HOME/Files/AI Harness/dimensional-harness}"
  log "Dimensional AI harness"
  if [ ! -f "$source/package.json" ]; then
    if have dimensional-ai; then
      step "installed; source checkout not present on this machine"
      return 0
    fi
    if have gh && gh auth status >/dev/null 2>&1; then
      mkdir -p "$(dirname "$source")"
      gh repo clone AaryanAgrawal/dimensional-harness "$source" >/dev/null 2>&1 \
        || warn "could not clone the private harness repository"
    fi
    if [ ! -f "$source/package.json" ]; then
      warn "harness source missing: $source -- run gh auth login, then rerun ./setup.sh"
      return 0
    fi
    step "cloned private harness source"
  fi
  have npm || { warn "npm missing -- cannot install the Dimensional harness"; return 0; }
  if ( cd "$source" && npm ci --silent && npm run install:local -- --workspace "$REPO_ROOT" ); then
    step "installed from $source"
  else
    warn "Dimensional harness install failed: $source"
  fi
}

# diffity: browser diff viewer for reviewing what the agent changed. The skills
# give Claude Code and Codex /diffity-diff, /diffity-review, /diffity-resolve.
diffity_install() {
  log "diffity"
  have npm || { warn "npm missing -- diffity not installed"; return 0; }
  have diffity || npm install -g diffity >/dev/null 2>&1 || { warn "npm install -g diffity failed"; return 0; }
  # --global: without it the skills land in the current repo only
  if [ ! -d "$HOME/.agents/skills/diffity-diff" ]; then
    npx --yes skills add nilbuild/diffity --yes --global >/dev/null 2>&1 \
      || warn "diffity skills failed -- run: npx skills add nilbuild/diffity --global"
  fi
  if [ -L "$HOME/.claude/skills/diffity-diff" ]; then
    step "/diffity-diff, /diffity-review, /diffity-resolve ready in Claude Code"
  else
    warn "diffity skills not linked into ~/.claude/skills"
  fi
  # the installer lists Codex but does not actually link it; do it ourselves
  if [ -d "$HOME/.codex/skills" ]; then
    local s
    for s in "$HOME"/.agents/skills/diffity-*; do
      [ -d "$s" ] && ln -sfn "$s" "$HOME/.codex/skills/$(basename "$s")"
    done
    step "linked into Codex too"
  fi
}

check_command() {
  local label="$1" command="$2" version="$3"
  if have "$command"; then
    check_row PASS "$label" "$version"
  else
    check_row FAIL "$label" "missing; run ./setup.sh"
  fi
}

command_version() {
  local command="$1"
  shift
  if have "$command"; then
    version_line "$command" "$@"
  fi
}

command_path() {
  if have "$1"; then
    command -v "$1"
  fi
}

check_claude_layer() {
  local d="$HOME/.claude" model major
  if [ ! -f "$d/settings.json" ]; then
    check_row SETUP "Claude agent config" "$HOME/.claude/settings.json is missing"
    return 0
  fi
  if jq empty "$d/settings.json" >/dev/null 2>&1; then
    check_row PASS "Claude settings" "valid JSON"
  else
    check_row FAIL "Claude settings" "invalid JSON"
    return 0
  fi
  if [ -n "$(git -C "$d" status --porcelain 2>/dev/null || true)" ]; then
    check_row WARN "Claude config sync" "local changes kept; setup will not overwrite them"
  else
    check_row PASS "Claude config sync" "clean"
  fi
  if [ -r "$d/statusline-command.sh" ]; then
    check_row PASS "Claude status line" "$d/statusline-command.sh"
  else
    check_row SETUP "Claude status line" "missing"
  fi
  if [ -x "$d/hooks/keep-working.sh" ] && [ -x "$d/hooks/payment-guard.sh" ]; then
    check_row PASS "Claude hooks" "keep-working + payment guard"
  else
    check_row FAIL "Claude hooks" "required hook is missing or not executable"
  fi
  if grep -q '/Users/aaryan/.claude/' "$d/settings.json" && [ "$HOME" != /Users/aaryan ]; then
    check_row FAIL "Claude hook paths" "still point at /Users/aaryan; run ./setup.sh"
  else
    check_row PASS "Claude hook paths" "match this machine"
  fi
  model="$(jq -r '.model // "not pinned"' "$d/settings.json")"
  case "$model" in
    *"[1m]"*) check_row WARN "Claude model" "$model conflicts with rules/models.md" ;;
    *) check_row PASS "Claude model" "$model" ;;
  esac
  major="$(node_major)"
  if [ -f "$d/skills/browser/lib/package.json" ] && [ ! -d "$d/skills/browser/lib/node_modules" ]; then
    check_row FAIL "Browser skill" "dependencies missing; run ./setup.sh"
  elif [ "$major" -lt 22 ]; then
    check_row FAIL "Browser skill" "Node.js 22+ required"
  else
    check_row PASS "Browser skill" "runtime dependencies present"
  fi
}

check_auth() {
  local output
  if have gh && gh auth status >/dev/null 2>&1; then
    check_row PASS "GitHub auth" "gh is authenticated"
  else
    check_row SETUP "GitHub auth" "run: gh auth login"
  fi
  output="$(claude auth status --json 2>/dev/null || true)"
  if printf '%s' "$output" | jq -e '.loggedIn == true' >/dev/null 2>&1; then
    check_row PASS "Claude auth" "$(printf '%s' "$output" | jq -r '.authMethod // "signed in"')"
  else
    check_row SETUP "Claude auth" "run: claude"
  fi
  output="$(codex login status 2>&1 || true)"
  # anchored: "Not logged in" also contains "logged in"
  if printf '%s' "$output" | grep -qiE '^(logged in|✓)'; then
    check_row PASS "Codex auth" "$output"
  else
    check_row SETUP "Codex auth" "run: codex"
  fi
  if [ -s "$HOME/.local/share/opencode/auth.json" ]; then
    check_row PASS "OpenCode auth" "credential store present"
  elif [ -s "$HOME/.hermes/profiles/dimensional/opencode/data/opencode/auth.json" ]; then
    check_row PASS "OpenCode auth" "isolated Dimensional credential; checked below"
  else
    check_row SETUP "OpenCode auth" "run opencode, then /connect"
  fi
  if [ -s "$HOME/.hermes/profiles/dimensional/auth.json" ]; then
    check_row PASS "Hermes profile" "Dimensional profile configured"
  elif [ -s "$HOME/.hermes/config.yaml" ] || [ -s "$HOME/.hermes/auth.json" ]; then
    check_row PASS "Hermes profile" "default profile configured"
  else
    check_row SETUP "Hermes profile" "run: hermes setup"
  fi
}

readiness_check() {
  CHECK_FAILURES=0
  CHECK_SETUPS=0
  log "Workstation readiness"
  printf '  %-7s %-22s %s\n' STATUS COMPONENT DETAIL
  printf '  %-7s %-22s %s\n' '-------' '----------------------' '------'
  local command
  check_section "FOUNDATION"
  for command in git curl zsh jq rg node npm dtach; do
    if have "$command"; then
      check_row PASS "$command" "$(command -v "$command")"
    else
      check_row FAIL "$command" "required dependency missing"
    fi
  done
  if [ "$(node_major)" -ge 22 ]; then
    check_row PASS "Node.js" "$(node -v)"
  else
    check_row FAIL "Node.js" "$(node -v 2>/dev/null || echo missing); version 22+ required"
  fi
  check_section "AGENT SURFACES"
  check_command "Claude Code" claude "$(command_version claude --version)"
  check_command "Codex" codex "$(command_version codex --version)"
  check_command "OpenCode" opencode "$(command_version opencode --version)"
  check_command "Hermes" hermes "$(command_version hermes --version)"
  check_command "OpenSpec" openspec "$(command_version openspec --version)"
  check_command "Dimensional harness" dimensional-ai "$(command_path dimensional-ai)"
  check_command "Diffity" diffity "$(command_version diffity --version)"
  check_command "Ghostty" ghostty "$(command_path ghostty)"
  if [ "$OS" = Darwin ]; then
    check_command "Paneru" paneru "$(command_path paneru)"
  else
    check_command "niri" niri "$(command_path niri)"
  fi
  check_section "CLAUDE LAYER"
  check_claude_layer
  check_section "ACCOUNTS"
  check_auth
  check_section "SHARED TOOLING"
  local skills_count=0
  # find exits 1 on a missing dir; under pipefail that would kill the whole report
  if [ -d "$HOME/.agents/skills" ]; then
    skills_count="$(find "$HOME/.agents/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
  fi
  if [ "$skills_count" -gt 0 ]; then
    check_row PASS "Shared skills" "$skills_count under ~/.agents/skills"
  else
    check_row SETUP "Shared skills" "none under ~/.agents/skills"
  fi
  if have op; then
    check_row PASS "1Password CLI" "$(command -v op)"
  else
    check_row SETUP "1Password CLI" "needed only for agent credential sync"
  fi
  printf '\n  Workstation result: %d failed, %d need setup.\n' "$CHECK_FAILURES" "$CHECK_SETUPS"
  if have dimensional-ai && [ "${SETUP_SKIP_HARNESS_DOCTOR:-0}" != 1 ]; then
    log "Dimensional harness"
    if dimensional-ai doctor; then
      step "Core harness checks passed; any harness SETUP rows are human checkpoints"
    else
      warn "Dimensional harness doctor failed"
      CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
  fi
  [ "$CHECK_FAILURES" -eq 0 ]
}

summary() {
  log "Installation finished"
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    printf '\n\033[33m  %d need you:\033[0m\n' "${#WARNINGS[@]}"
    printf '    - %s\n' "${WARNINGS[@]}"
  fi
  printf '\n  Open a new terminal for PATH and shell changes.\n'
  printf '  Re-run this report any time: ./setup.sh --check\n\n'
}

usage() {
  cat <<'EOF'
Usage: ./setup.sh [--check | --help]

  no argument  Install or update the workstation, then verify it
  --check      Read-only readiness report; no installs or config writes
  --help       Show this help

The installer sets up the terminal, window manager, agent CLIs, shared Claude
config, and review skills. Authentication remains per tool and is reported as
SETUP until the operator completes it.
EOF
}

main() {
  case "${1:-}" in
    --check|check) readiness_check; return ;;
    --help|-h|help) usage; return ;;
    "") ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
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
  have uv     || curl -LsSf https://astral.sh/uv/install.sh | sh || warn "uv install failed"
  install_agent_clis
  agent_layer
  harness_prepare
  install_dimensional_harness
  diffity_install
  # plain chsh asks for a password and fails unattended; sudo chsh on Linux does not
  if have zsh && [ "${SHELL:-}" != "$(command -v zsh)" ]; then
    local zsh_path; zsh_path="$(command -v zsh)"
    if [ "$OS" = Linux ]; then
      sudo chsh -s "$zsh_path" "${USER:-$(id -un)}" || warn "run: chsh -s $zsh_path"
    else
      chsh -s "$zsh_path" || warn "run: chsh -s $zsh_path"
    fi
  fi
  summary
  readiness_check
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi

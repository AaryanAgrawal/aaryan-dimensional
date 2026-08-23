#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/setup.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

make_fake_bin() {
  local bin="$1" command
  mkdir -p "$bin"
  cat > "$bin/tool" <<'EOF'
#!/usr/bin/env bash
case "$(basename "$0")" in
  sudo) printf '%s\n' "$*" >> "${SUDO_LOG:-/dev/null}" ;;
  node) printf 'v22.14.0\n' ;;
  npm)
    if [ "${1:-}" = config ] && [ "${2:-}" = get ]; then printf '/usr\n'; fi
    if [ "${1:-}" = config ] && [ "${2:-}" = set ]; then printf '%s\n' "$*" >> "${NPM_LOG:-/dev/null}"; fi ;;
  claude)
    if [ "${1:-}" = auth ]; then printf '{"loggedIn":true,"authMethod":"claude.ai"}\n'; else printf '2.1.241 (Claude Code)\n'; fi ;;
  codex)
    if [ "${1:-}" = login ]; then printf 'Logged in using ChatGPT\n'; else printf 'codex-cli 0.147.0\n'; fi ;;
  opencode) printf '1.18.10\n' ;;
  hermes) printf 'Hermes Agent v0.19.0\n' ;;
  diffity) printf '0.9.5\n' ;;
  fc-list) printf 'JetBrainsMono Nerd Font\n' ;;
esac
exit 0
EOF
  chmod +x "$bin/tool"
  for command in sudo git curl zsh rg node npm dtach gh code atuin niri ghostty brew \
      claude codex opencode hermes uv diffity chsh op fc-list fc-cache unzip; do
    ln -s tool "$bin/$command"
  done
}

make_ready_home() {
  local home="$1"
  mkdir -p "$home/.claude/.git" "$home/.claude/hooks" \
    "$home/.claude/skills/browser/lib/node_modules" "$home/.agents/skills/diffity-diff" \
    "$home/.local/share/opencode" "$home/.hermes/profiles/dimensional" \
    "$home/.config/agent" "$home/.codex/skills"
  printf '{"model":"fable"}\n' > "$home/.claude/settings.json"
  printf '{}\n' > "$home/.claude/skills/browser/lib/package.json"
  printf '#!/usr/bin/env bash\n' > "$home/.claude/statusline-command.sh"
  printf '#!/usr/bin/env bash\n' > "$home/.claude/hooks/keep-working.sh"
  printf '#!/usr/bin/env bash\n' > "$home/.claude/hooks/payment-guard.sh"
  chmod +x "$home/.claude/hooks/keep-working.sh" "$home/.claude/hooks/payment-guard.sh"
  printf '%s\n' '---' 'name: diffity-diff' 'description: Review a diff.' '---' \
    > "$home/.agents/skills/diffity-diff/SKILL.md"
  mkdir -p "$home/.claude/skills"
  ln -s "$home/.agents/skills/diffity-diff" "$home/.claude/skills/diffity-diff"
  printf '{}\n' > "$home/.local/share/opencode/auth.json"
  printf 'model: test\n' > "$home/.hermes/config.yaml"
  printf '{}\n' > "$home/.hermes/profiles/dimensional/auth.json"
  printf 'OP_SERVICE_ACCOUNT_TOKEN=test-only\n' > "$home/.config/agent/.env"
}

bash -n "$SCRIPT"
shellcheck "$SCRIPT"
"$SCRIPT" --help > "$TMP/help.out"
assert_contains "$TMP/help.out" '--check      Read-only readiness report'

source_output="$(bash -c 'source "$1"; printf sourced' _ "$SCRIPT")"
[ "$source_output" = sourced ] || fail "sourcing setup.sh ran main"

INSTALL_BIN="$TMP/install-bin"
mkdir -p "$INSTALL_BIN"
cat > "$INSTALL_BIN/node" <<'EOF'
#!/usr/bin/env bash
printf 'v22.14.0\n'
EOF
cat > "$INSTALL_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '#!/bin/sh\nexit 0\n'
EOF
chmod +x "$INSTALL_BIN/node" "$INSTALL_BIN/curl"
CURL_LOG="$TMP/curl.log" HOME="$TMP/install-home" PATH="$INSTALL_BIN:/usr/bin:/bin" \
  bash -c 'source "$1"; install_agent_clis >/dev/null' _ "$SCRIPT"
assert_contains "$TMP/curl.log" 'https://claude.ai/install.sh'
assert_contains "$TMP/curl.log" 'https://chatgpt.com/codex/install.sh'
assert_contains "$TMP/curl.log" 'https://opencode.ai/install'
assert_contains "$TMP/curl.log" 'https://hermes-agent.nousresearch.com/install.sh'
assert_contains "$SCRIPT" 'bash -s -- --skip-browser'

FAKE_BIN="$TMP/bin"
FAKE_HOME="$TMP/home"
make_fake_bin "$FAKE_BIN"
make_ready_home "$FAKE_HOME"
HOME="$FAKE_HOME" SHELL="$FAKE_BIN/zsh" PATH="$FAKE_BIN:/opt/homebrew/bin:/usr/bin:/bin" \
  NPM_LOG="$TMP/npm.log" SUDO_LOG="$TMP/sudo.log" \
  SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" > "$TMP/install.out"
assert_contains "$TMP/install.out" 'Workstation result: 0 failed, 0 need setup.'
assert_contains "$FAKE_HOME/.config/ghostty/config" 'ctrl+shift+e=new_split:right'
if [ "$(uname -s)" = Darwin ]; then
  assert_contains "$FAKE_HOME/.config/paneru/paneru.toml" 'window_focus_west  = "alt - j"'
else
  assert_contains "$FAKE_HOME/.config/niri/config.kdl" 'Mod+J { focus-column-left; }'
  assert_contains "$TMP/npm.log" "config set prefix $FAKE_HOME/.local"
  assert_contains "$TMP/sudo.log" 'apt-get install -y build-essential'
  assert_contains "$TMP/sudo.log" 'apt-get install -y python3'
fi
assert_contains "$FAKE_HOME/.zshrc" 'zoxide init zsh'
assert_contains "$FAKE_HOME/.zshrc" "\$HOME/.opencode/bin:\$PATH"

before_check="$(find "$FAKE_HOME" -type f -exec cksum {} \; | sort | cksum)"
HOME="$FAKE_HOME" PATH="$FAKE_BIN:/opt/homebrew/bin:/usr/bin:/bin" \
  SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/check.out"
after_check="$(find "$FAKE_HOME" -type f -exec cksum {} \; | sort | cksum)"
[ "$before_check" = "$after_check" ] || fail "--check modified the test home"
assert_contains "$TMP/check.out" 'OpenCode auth          credential store present'
assert_contains "$TMP/check.out" 'Hermes profile         Dimensional profile configured'
assert_contains "$TMP/check.out" 'Workstation result: 0 failed, 0 need setup.'

mv "$FAKE_BIN/codex" "$FAKE_BIN/codex.logged-in"
printf '#!/usr/bin/env bash\nprintf "Not logged in\\n"\n' > "$FAKE_BIN/codex"
chmod +x "$FAKE_BIN/codex"
HOME="$FAKE_HOME" PATH="$FAKE_BIN:/opt/homebrew/bin:/usr/bin:/bin" \
  SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/codex-logged-out.out"
assert_contains "$TMP/codex-logged-out.out" '[SETUP] Codex auth'
mv "$FAKE_BIN/codex" "$FAKE_BIN/codex.logged-out"
mv "$FAKE_BIN/codex.logged-in" "$FAKE_BIN/codex"

mv "$FAKE_BIN/hermes" "$FAKE_BIN/hermes.off"
if HOME="$FAKE_HOME" PATH="$FAKE_BIN:/opt/homebrew/bin:/usr/bin:/bin" \
    SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/missing-hermes.out"; then
  fail "missing Hermes readiness check unexpectedly passed"
fi
assert_contains "$TMP/missing-hermes.out" '[FAIL]  Hermes'
mv "$FAKE_BIN/hermes.off" "$FAKE_BIN/hermes"

if "$SCRIPT" --unknown > "$TMP/unknown.out" 2>&1; then
  fail "unknown option unexpectedly passed"
fi
assert_contains "$TMP/unknown.out" 'unknown option: --unknown'

printf '#!/usr/bin/env bash\nprintf "v18.20.0\\n"\n' > "$FAKE_BIN/node"
chmod +x "$FAKE_BIN/node"
if HOME="$FAKE_HOME" PATH="$FAKE_BIN:/opt/homebrew/bin:/usr/bin:/bin" \
    SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/old-node.out"; then
  fail "Node.js 18 readiness check unexpectedly passed"
fi
assert_contains "$TMP/old-node.out" '[FAIL]  Node.js'
assert_contains "$TMP/old-node.out" 'version 22+ required'

printf 'PASS: setup installer, configs, readiness UX, and failure path\n'

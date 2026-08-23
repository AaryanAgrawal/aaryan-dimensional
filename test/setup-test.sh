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
  node) printf 'v24.13.0\n' ;;
  npm)
    if [ "${1:-}" = config ] && [ "${2:-}" = get ]; then printf '/usr\n'; fi
    if [ "${1:-}" = config ] && [ "${2:-}" = set ]; then printf '%s\n' "$*" >> "${NPM_LOG:-/dev/null}"; fi ;;
  claude)
    if [ "${1:-}" = auth ]; then
      if [ -n "${CLAUDE_AUTH_PAYLOAD:-}" ]; then
        printf '%s\n' "$CLAUDE_AUTH_PAYLOAD"
      else
        printf '{"loggedIn":true,"authMethod":"claude.ai"}\n'
      fi
    else
      printf '2.1.241 (Claude Code)\n'
    fi ;;
  codex)
    if [ "${1:-}" = login ]; then printf 'Logged in using ChatGPT\n'; else printf 'codex-cli 0.147.0\n'; fi ;;
  opencode) printf '1.18.10\n' ;;
  hermes) printf 'Hermes Agent v0.19.0\n' ;;
  openspec) printf '1.10.0\n' ;;
  dimensional-ai) printf '%s/.local/bin/dimensional-ai\n' "$HOME" ;;
  jq)
    case "$*" in
      *'.model // empty'*) printf 'fable\n' ;;
      *'.model // "not pinned"'*) printf 'fable\n' ;;
      *'.loggedIn == true'*)
        input="$(cat)"
        case "$input" in *'"loggedIn":true'*) printf 'true\n' ;; *) exit 1 ;; esac ;;
      *'.authMethod'*'type == "string"'*)
        input="$(cat)"
        case "$input" in
          *'"loggedIn":true'*'"authMethod":"'*) printf 'claude.ai\n' ;;
          *'"loggedIn":true'*) printf 'signed in\n' ;;
          *) exit 1 ;;
        esac ;;
      *'.authMethod'*)
        input="$(cat)"
        case "$input" in
          *'"authMethod":"'*) printf 'claude.ai\n' ;;
          *'"authMethod":42'*) printf '42\n' ;;
          *'"authMethod":true'*) printf 'true\n' ;;
          *'"authMethod":[]'*) printf '[]\n' ;;
          *'"authMethod":{}'*) printf '{}\n' ;;
          *) printf 'signed in\n' ;;
        esac ;;
    esac ;;
  brew) [ "${1:-}" = --prefix ] && printf '/opt/homebrew\n' ;;
  diffity) printf '0.9.5\n' ;;
  fc-list) printf 'JetBrainsMono Nerd Font\n' ;;
esac
exit 0
EOF
  chmod +x "$bin/tool"
  for command in sudo git curl zsh jq rg node npm dtach gh code atuin niri paneru ghostty brew \
      claude codex opencode hermes openspec dimensional-ai uv diffity chsh op fc-list fc-cache unzip; do
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
printf 'v24.13.0\n'
EOF
cat > "$INSTALL_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '#!/bin/sh\nexit 0\n'
EOF
cat > "$INSTALL_BIN/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NPM_LOG"
EOF
chmod +x "$INSTALL_BIN/node" "$INSTALL_BIN/curl" "$INSTALL_BIN/npm"
CURL_LOG="$TMP/curl.log" NPM_LOG="$TMP/agent-npm.log" HOME="$TMP/install-home" PATH="$INSTALL_BIN:/usr/bin:/bin" \
  bash -c 'source "$1"; install_agent_clis >/dev/null' _ "$SCRIPT"
assert_contains "$TMP/curl.log" 'https://claude.ai/install.sh'
assert_contains "$TMP/curl.log" 'https://chatgpt.com/codex/install.sh'
assert_contains "$TMP/curl.log" 'https://opencode.ai/install'
assert_contains "$TMP/curl.log" 'https://hermes-agent.nousresearch.com/install.sh'
assert_contains "$TMP/agent-npm.log" 'install -g @fission-ai/openspec@latest'
assert_contains "$SCRIPT" 'bash -s -- --skip-browser'
assert_contains "$SCRIPT" 'gh repo clone AaryanAgrawal/dimensional-harness'

CLONE_BIN="$TMP/clone-bin"
mkdir -p "$CLONE_BIN"
cat > "$CLONE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
if [ "${1:-}" = auth ]; then exit 0; fi
if [ "${1:-}" = repo ] && [ "${2:-}" = clone ]; then
  mkdir -p "$4"
  printf '{"name":"dimensional-harness"}\n' > "$4/package.json"
fi
EOF
cat > "$CLONE_BIN/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HARNESS_NPM_LOG"
EOF
chmod +x "$CLONE_BIN/gh" "$CLONE_BIN/npm"
GH_LOG="$TMP/gh.log" HARNESS_NPM_LOG="$TMP/harness-npm.log" \
  DIMENSIONAL_HARNESS_SOURCE="$TMP/private-harness" HOME="$TMP/clone-home" \
  PATH="$CLONE_BIN:/usr/bin:/bin" \
  bash -c 'source "$1"; install_dimensional_harness >/dev/null' _ "$SCRIPT"
assert_contains "$TMP/gh.log" "repo clone AaryanAgrawal/dimensional-harness $TMP/private-harness"
assert_contains "$TMP/harness-npm.log" 'ci --silent'
assert_contains "$TMP/harness-npm.log" "run install:local -- --workspace $ROOT"

FONT_BIN="$TMP/font-bin"
mkdir -p "$FONT_BIN"
for command in find grep mkdir rm; do ln -s "$(command -v "$command")" "$FONT_BIN/$command"; done
cat > "$FONT_BIN/curl" <<'EOF'
#!/bin/bash
printf 'curl\n' >> "$FONT_CURL_LOG"
: > JetBrainsMono.zip
EOF
cat > "$FONT_BIN/unzip" <<'EOF'
#!/bin/bash
: > JetBrainsMonoNerdFont-Regular.ttf
exit 0
EOF
chmod +x "$FONT_BIN/curl" "$FONT_BIN/unzip"
FONT_CURL_LOG="$TMP/font-curl.log" HOME="$TMP/font-home" \
  bash -c 'source "$1"; PATH="$2"; font >/dev/null; font >/dev/null; font >/dev/null' \
  _ "$SCRIPT" "$FONT_BIN" || fail "font install without fc-cache failed"
[ "$(wc -l < "$TMP/font-curl.log" | tr -d ' ')" = 1 ] || fail "font install was not idempotent"
if [ "$(uname -s)" = Darwin ]; then
  [ -f "$TMP/font-home/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf" ] \
    || fail "macOS font was not installed into ~/Library/Fonts"
else
  [ -f "$TMP/font-home/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf" ] \
    || fail "Linux font was not installed into ~/.local/share/fonts"
fi

FAKE_BIN="$TMP/bin"
FAKE_HOME="$TMP/home"
make_fake_bin "$FAKE_BIN"
make_ready_home "$FAKE_HOME"
HOME="$FAKE_HOME" SHELL="$FAKE_BIN/zsh" PATH="$FAKE_BIN:/usr/bin:/bin" \
  HOMEBREW_PREFIX=/definitely/not/the/brew/prefix \
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
if [ "$(uname -s)" = Darwin ]; then
  assert_contains "$FAKE_HOME/.zshrc" '/opt/homebrew/share/zsh-autosuggestions'
  if grep -Fq '/definitely/not/the/brew/prefix' "$FAKE_HOME/.zshrc"; then
    fail "zsh plugin path inherited HOMEBREW_PREFIX"
  fi
fi

before_check="$(find "$FAKE_HOME" -type f -exec cksum {} \; | sort | cksum)"
HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
  SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/check.out"
after_check="$(find "$FAKE_HOME" -type f -exec cksum {} \; | sort | cksum)"
[ "$before_check" = "$after_check" ] || fail "--check modified the test home"
assert_contains "$TMP/check.out" 'OpenCode auth          credential store present'
assert_contains "$TMP/check.out" 'Hermes profile         Dimensional profile configured'
assert_contains "$TMP/check.out" 'Dimensional harness    '
assert_contains "$TMP/check.out" 'Workstation result: 0 failed, 0 need setup.'

mv "$FAKE_BIN/codex" "$FAKE_BIN/codex.logged-in"
printf '#!/usr/bin/env bash\nprintf "Not logged in\\n"\n' > "$FAKE_BIN/codex"
chmod +x "$FAKE_BIN/codex"
HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
  SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/codex-logged-out.out"
assert_contains "$TMP/codex-logged-out.out" '[SETUP] Codex auth'
mv "$FAKE_BIN/codex" "$FAKE_BIN/codex.logged-out"
mv "$FAKE_BIN/codex.logged-in" "$FAKE_BIN/codex"

mv "$FAKE_BIN/hermes" "$FAKE_BIN/hermes.off"
if HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/missing-hermes.out"; then
  fail "missing Hermes readiness check unexpectedly passed"
fi
assert_contains "$TMP/missing-hermes.out" '[FAIL]  Hermes'
mv "$FAKE_BIN/hermes.off" "$FAKE_BIN/hermes"

mv "$FAKE_BIN/dimensional-ai" "$FAKE_BIN/dimensional-ai.off"
if HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/missing-harness.out"; then
  fail "missing Dimensional harness readiness check unexpectedly passed"
fi
assert_contains "$TMP/missing-harness.out" '[FAIL]  Dimensional harness'
mv "$FAKE_BIN/dimensional-ai.off" "$FAKE_BIN/dimensional-ai"

mv "$FAKE_BIN/claude" "$FAKE_BIN/claude.off"
if HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/missing-claude.out"; then
  fail "missing Claude Code readiness check unexpectedly passed"
fi
assert_contains "$TMP/missing-claude.out" '[FAIL]  Claude Code'
assert_contains "$TMP/missing-claude.out" '[SETUP] Claude auth'
if grep -Fq '[PASS]  Claude auth' "$TMP/missing-claude.out"; then
  fail "missing Claude Code falsely passed authentication"
fi
mv "$FAKE_BIN/claude.off" "$FAKE_BIN/claude"

MISSING_JQ_BIN="$TMP/missing-jq-bin"
mkdir -p "$MISSING_JQ_BIN"
for source in "$FAKE_BIN"/*; do
  command="$(basename "$source")"
  case "$command" in jq|node) continue ;; esac
  ln -s "$source" "$MISSING_JQ_BIN/$command"
done
cat > "$MISSING_JQ_BIN/node" <<'EOF'
#!/bin/bash
case "${1:-}" in
  -v) printf 'v24.13.0\n' ;;
  -e)
    case "$2" in
      *'authMethod'*)
        input="$(cat)"
        case "$input" in
          *'"loggedIn":true'*'"authMethod":"'*) printf 'claude.ai' ;;
          *'"loggedIn":true'*) printf 'signed in' ;;
          *) exit 1 ;;
        esac ;;
      *'loggedIn'*) input="$(cat)"; case "$input" in *'"loggedIn":true'*) exit 0 ;; *) exit 1 ;; esac ;;
      *'.model'*) printf 'fable' ;;
      *'JSON.parse'*) grep -q '"model"' "${3:-}" ;;
    esac ;;
esac
EOF
chmod +x "$MISSING_JQ_BIN/node"
for command in bash basename cat date dirname env find grep sed tr uname wc; do
  [ -e "$MISSING_JQ_BIN/$command" ] || ln -s "$(command -v "$command")" "$MISSING_JQ_BIN/$command"
done
if HOME="$FAKE_HOME" PATH="$MISSING_JQ_BIN" \
    SETUP_SKIP_HARNESS_DOCTOR=1 /bin/bash "$SCRIPT" --check > "$TMP/missing-jq.out"; then
  fail "missing jq readiness check unexpectedly passed"
fi
assert_contains "$TMP/missing-jq.out" '[FAIL]  jq'
assert_contains "$TMP/missing-jq.out" '[PASS]  Claude settings'
assert_contains "$TMP/missing-jq.out" '[PASS]  Claude status line'
assert_contains "$TMP/missing-jq.out" '[PASS]  Claude hooks'
assert_contains "$TMP/missing-jq.out" '[PASS]  Claude hook paths'
assert_contains "$TMP/missing-jq.out" '[PASS]  Claude model'
assert_contains "$TMP/missing-jq.out" '[PASS]  Browser skill'
assert_contains "$TMP/missing-jq.out" '[PASS]  Claude auth'
assert_contains "$SCRIPT" 'typeof value === "string" && value ? value : "signed in"'
if HOME="$FAKE_HOME" PATH="$MISSING_JQ_BIN" CLAUDE_AUTH_PAYLOAD='{"loggedIn":true,"authMethod":42}' \
    SETUP_SKIP_HARNESS_DOCTOR=1 /bin/bash "$SCRIPT" --check > "$TMP/non-string-auth.out"; then
  fail "missing jq readiness check unexpectedly passed for non-string authMethod"
fi
assert_contains "$TMP/non-string-auth.out" '[PASS]  Claude auth'
assert_contains "$TMP/non-string-auth.out" 'signed in'
assert_contains "$TMP/non-string-auth.out" 'Workstation result:'

for auth_method in '42' 'true' '[]' '{}'; do
  HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    CLAUDE_AUTH_PAYLOAD="{\"loggedIn\":true,\"authMethod\":$auth_method}" \
    SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/jq-non-string-auth.out"
  assert_contains "$TMP/jq-non-string-auth.out" '[PASS]  Claude auth'
  assert_contains "$TMP/jq-non-string-auth.out" 'signed in'
  assert_contains "$TMP/jq-non-string-auth.out" 'Workstation result:'
done

if "$SCRIPT" --unknown > "$TMP/unknown.out" 2>&1; then
  fail "unknown option unexpectedly passed"
fi
assert_contains "$TMP/unknown.out" 'unknown option: --unknown'

mv "$FAKE_BIN/node" "$FAKE_BIN/node.ready"
printf '#!/usr/bin/env bash\nprintf "v18.20.0\\n"\n' > "$FAKE_BIN/node"
chmod +x "$FAKE_BIN/node"
if HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    SETUP_SKIP_HARNESS_DOCTOR=1 "$SCRIPT" --check > "$TMP/old-node.out"; then
  fail "Node.js 18 readiness check unexpectedly passed"
fi
assert_contains "$TMP/old-node.out" '[FAIL]  Node.js'
assert_contains "$TMP/old-node.out" 'version 24+ required'
mv "$FAKE_BIN/node" "$FAKE_BIN/node.old"
mv "$FAKE_BIN/node.ready" "$FAKE_BIN/node"

printf 'PASS: setup installer, configs, readiness UX, and failure path\n'

# dimos-helm release readiness — c26f534..origin/main

## Verdict

**Ship.** No blocker survived verification; the four remaining majors sit in opt-in or recoverable paths, none corrupts a machine, and none breaks the documented interactive install.

## What changed

- Version 0.3.35 to 0.3.97. 213 commits, 2026-03-09 to 2026-07-22, 90 tags cut. +14,216/-1,458 across 94 files. Rust grew from 6,800 to 12,551 lines.
- dim went from an installer to a device manager. Five new top level commands — `config`, `desktop`, `install`, `uninstall`, `webserver` (src/cli.rs:283-319). It had five commands at the base; it has ten now.
- The desktop left the tree. It is a separately released binary, downloaded from R2 and pinned in static_data.json (src/commands/desktop.rs:206-274). src/desktop/ and src/web/ are gone. desktop.rs is the largest new file at 1,998 lines and carries most of the range's operational work: launchd on macOS, systemd user vs system scope selection, XDG_RUNTIME_DIR synthesis over ssh, linger, a self-heal for the wants symlink when `systemctl --user enable` no-ops, and a detached restart so a self-update does not kill itself with its own cgroup.
- src/commands/webserver.rs (899 lines) is a hand-rolled HTTP server, described in its own module doc as the zero dependency fallback for the desktop. It exposes a JSON API that writes config and launches blueprints.
- Config was rewritten to a `serde_json::Value` store at ~/.dimos/config.json (src/config.rs:59), and the data directory moved from ~/.local/share/dim to ~/.dimos/data (src/util/paths.rs:10-13).
- Setup gained a TTY probe. A missing terminal is now treated as non-interactive, and unless you pass `--mode`, `--extras`, or `--project-dir` it skips the DimOS install entirely (src/setup/mod.rs:118-127). This is the largest behaviour change in the range and it appears in no README or CHANGELOG line.
- New orientation docs: AGENTS.md (231 lines), docs/ai-manual-install-guide.md (455 lines), src/setup/agent_instructions.md, todo.md. RealSense support was deleted (src/setup/realsense.rs).
- Dead weight arrived alongside: templates/ with a committed 145KB vite bundle, an abandoned embedded Docker payload (src/docker.rs plus five run/ scripts no release path touches), vhs/ recording a manual docker flow that never invokes dim, and two scratch files at the repo root.

## Blockers

**None.** Both findings filed as blockers failed verification, and for the same reason: they are byte-identical at c26f534.

- The UTF-8 slice panic at src/util/cmd.rs:118 is present verbatim at the base commit. It also only truncates stdout, and the tools named as the source of multi-byte progress lines write to stderr — measured 0 bytes on stdout for both `uv pip install` and `nix build`.
- `--dry-run` genuinely running `sudo apt-get install` (src/setup/deps.rs:442, with `false` hardcoded for dry_run at :491 and :506) is also byte-identical at the base. The range only refactored `cmd::spin` into `spin_cmd`, carrying the hardcoded `false` forward.

Both are real bugs. Neither was introduced here, and neither should hold this tag.

## Should fix soon

Four majors, in the order I would fix them.

**1. `dim setup` re-run silently fails to replace the binary (src/setup/self_install.rs:44).** The desktop boot service runs `~/.local/bin/dim desktop serve --if-enabled` and that dim process blocks for the desktop's lifetime (desktop.rs:174-186), holding the file as its text image. `std::fs::copy` over it returns ETXTBSY. install.sh:76 always execs from /tmp/dim.XXXXXX, so the `current_exe == dest` skip never fires on a re-run. The stage is non-critical (mod.rs:189), so unattended setup logs "continuing past 'self-install' failure" and proceeds, `ensure_path()` is skipped as collateral, and the freshly written unit points at the stale binary. `desktop.on_boot` defaults true and non-interactive setup forces it (mod.rs:504-506), so this is the normal state of any machine that has been through setup once. The fix already exists three lines away: `dim update` uses rename at update.rs:71. Use it in both places.

**2. Non-interactive setup skips DimOS and exits 0 (src/setup/mod.rs:118,125,127,245-250).** Reproduced: `dim setup --dry-run --non-interactive --branch feature-xyz </dev/null` ends at "dim + desktop installed (skipped DimOS install)", exit 0. `--branch` and `DIM_BRANCH` are not in the opt-in set, so CI and provisioning scripts get a dim binary and no DimOS with a green exit. `--dry-run` alone also trips it (cli.rs:248-250), so the documented preview run (README:62) no longer previews the main event. The documented curl form `bash <(curl ...)` keeps a TTY and is unaffected — I confirmed that under a real pty. The robot half is already fixed on fix/jetson-non-interactive by 770b1a0, which is not merged. Minimum: a README and CHANGELOG line, plus adding `--branch` to the opt-in probe.

**3. The webserver has no auth, and its config endpoint reaches code execution (src/commands/webserver.rs:820-857).** No route checks a token, an Origin, or a CSRF nonce, and TLS uses `.with_no_client_auth()` (:387). `POST /api/config` passes arbitrary dotted keys to `config::set_value` (src/config.rs:113) with no whitelist. Repointing `dimos.dir` then makes `launch_blueprint` (:728) run `setsid bash -c "source <dimos.dir>/.venv/bin/activate && exec dimos --dtop run <name>"`. I executed that chain end to end under a throwaway HOME and got code running as the service user. `/api/launch` on its own is not an arbitrary process API — `is_valid_blueprint` (:530) enforces kebab-case and membership in all_blueprints.py. Mitigating: nothing auto-starts this server, default bind is 127.0.0.1, and `dim setup` never calls `webserver::enable`.

**4. `dim webserver` and `dim desktop` are two services sharing one port and one config namespace.** Both declare `DEFAULT_PORT = 1024` (webserver.rs:31, desktop.rs:36) and both read and write `desktop.on_boot`/`desktop.port`/`desktop.host`. Reproduced: `dim webserver enable --port 9000` relocated the desktop to 9000, and `dim webserver disable` set `desktop.on_boot=false` (webserver.rs:195), which is the key `dim desktop serve --if-enabled` gates on (desktop.rs:148) — the ExecStart of the desktop's own boot unit (desktop.rs:1134,1246). There is no port configuration in which the two coexist. The README sells webserver as an independent fallback (README:50, :113), but `grep webserver src/commands/desktop.rs` returns nothing: no fallback wiring exists. The cheapest release-time fix is one line — `#[command(hide = true)]` at cli.rs:301 and drop README:50 — deferring the real config split.

Minors worth clearing in the same pass:

- Support docs point at the wrong log. README.md:199 and :228, AGENTS.md:231, and CONTRIBUTING.md:138 all say `~/.local/share/dim/actions.log`; it is `~/.dimos/data/actions.log` (src/util/paths.rs:10-13). `dim doctor` and `dim log --help` print the correct path, so this fails loudly rather than silently. Same incomplete migration in code: desktop.rs:1846 and :1902 still write to ~/.local/share/dim/.
- README.md:118 documents `dim desktop --port 8088`. It exits 2 with `error: unexpected argument '--port' found`. The working forms, `dim desktop serve --port` and `dim desktop enable --port`, appear nowhere in the README.
- `dim webserver --help` advertises `webserver.enabled`, `webserver.port`, and a default of 8088 (src/cli.rs:131,366,369,375). No code reads those keys. `dim config set webserver.port 9000` is accepted and stored, and the server keeps binding 1024.
- README.md:192 and :202 say the desktop is embedded via `include_dir` and runs under `nix run deno`, contradicting README.md:110-113 ninety lines earlier. Neither `include_dir` nor `nix run deno` exists in the crate. This is the difference between provisioning a Nix store on a locked-down robot and not.
- docs/ai-manual-install-guide.md:111 pipes install.sh to `sh`; install.sh:9 is `set -euo pipefail` and dash rejects it. I diffed the published artifact at the R2 URL against the repo copy — byte-identical, so the live one fails too. Only Part 1.5 of that guide depends on dim, and nothing in the repo links to the file.
- clippy went green to red inside this range. `cargo clippy` exits 0 at c26f534 and 101 at origin/main on `never_loop` at src/setup/mod.rs:57. The cause is a0bce8e, which made the "Get help" arm call `std::process::exit(1)` (mod.rs:84-92). That is also a real UX regression: an interactive user whose non-critical stage failed picks the menu item labelled "show support links" and the install aborts with status 1, with no "aborting" message and no log entry. Fix the label or the exit, delete the vestigial loop, and add clippy to CI.
- `--dry-run` rewrites ~/.config/nix/nix.conf (src/setup/deps.rs:233), new in range via 9d4f73b. I watched it destroy an existing `experimental-features = ca-derivations` line. Reachable when a robot is detected or an explicit mode/extras/project-dir is passed.
- AGENTS.md shipped stale. It was added in this range (adfb5d0) documenting src/setup/realsense.rs, deleted six days before its own last edit, and it omits all five new commands and all three new setup flags.
- Desktop health check accepts any response whose first 64 bytes contain " 2" (desktop.rs:1460). One-directional error, so it never reports a healthy desktop as down. It only degrades the diagnostic when another server holds port 1024.
- One request with a large Content-Length aborts the whole webserver (webserver.rs:816, `vec![0u8; content_length]` with no bound). Reproduced with a 200GB Content-Length; the listener was gone. Two-line fix, and bound the request-line read at :797 while you are there.

## Accepted risk

- **`--dry-run` mutates the machine.** It runs `sudo apt-get update` and `install`, and on macOS `xcode-select --install` plus the Homebrew installer (src/setup/deps.rs:442-529). Pre-existing and shipped through every v0.3.x tag. This range slightly widened it: the python3-dev probe changed from `python3 --version` to `dpkg-query -W python3-dev` (deps.rs:451), which is more correct and therefore makes the apt path fire on more machines.
- **A UTF-8 line can panic the installer** (src/util/cmd.rs:118). Pre-existing. Residual exposure is non-ASCII dpkg output under a non-English locale, or brew on macOS. Never observed in the field.
- **Nothing gates a commit.** .github/workflows/release.yml is the only workflow, tag-triggered, build only, and byte-identical at both ends of the range. The 23 tests at origin/main pass and gate nothing. Two mitigations: `needs: build` means a compile break blocks the release rather than shipping, and releases are actually cut locally through run/publish, which runs `cargo check --quiet` at run/publish:208.
- **Test shape.** 2 of 29 src files carry a test module. 5,928 of 7,102 added Rust lines went into files with none, including all of desktop.rs and webserver.rs. Everything tested is a pure string function; no test executes a command, opens a socket, or writes a file outside a fixture read. There is no lib.rs, so cargo integration tests are structurally impossible until one is extracted.
- **Install verification cannot fail.** `verify_install` is non-critical (mod.rs:387), every branch in verify.rs warns and returns Ok, and the smoke test is skipped when headless or non-interactive. An install where `import dimos` fails still prints complete and exits 0. Entirely pre-existing, and the headless skip is deliberate — the smoke test is a long-running GUI simulation (verify.rs:181), not a terminating check.
- **The desktop binary is downloaded and executed with no checksum or signature** (desktop.rs:251-274). Same trust model the product already relies on: install.sh is curl-fetched from the same bucket and setup runs get.docker.com and astral.sh installers the same way.
- **rustls-rustcrypto 0.0.2-alpha** is a hard dependency (Cargo.toml:22), compiled into every binary. Inert unless both `desktop.ssl_cert` and `desktop.ssl_key` are set, but it appears in any SBOM.
- **Intel Macs get an arm64 binary** (install.sh:41). Deliberate, not a typo: sibling call sites carry `// Rosetta` comments (update.rs:181, run/main:11), because `uname -m` under a Rosetta shell reports x86_64. No x86_64 macOS artifact exists (404 on the bucket), so the correct behaviour is a clean error message, not a working install. Fixing it needs a `sysctl.proc_translated` probe, and the naive fix breaks the working Rosetta path.
- **Dead weight.** src/commands/init.rs and new_app.rs (~690 lines outside the module tree; they would not compile if wired in, at either end of the range). src/generated_platform_reqs.json, a 44KB March snapshot only read when `DIM_PYCHECK=1`, which nothing sets — the checker was deliberately disabled by feed03a. src/docker.rs plus five run/ docker scripts that no release path exercises, with `detect_payload()` self-reading the binary on every invocation (main.rs:26). templates/ with a content-hashed 145KB vite bundle in git. testing/dim/apps/_theme_examples at 1.3MB. test_sudo_env.rs and test_sudo_env.sh at the repo root.
- **No licence.** No LICENSE file, no `license` field, no SPDX headers. Consistent across the tree, so nothing regressed, but a public repo distributing binaries leaves recipients with no stated rights.

## Verified vs unverified

**Verified by execution** on this Linux box, building the binary and running it against an isolated $HOME with stubbed sudo/systemctl where needed:

- The 1024 port collision, and `dim webserver enable --port 9000` moving `desktop.port`.
- `cargo clippy` exit 101 at origin/main against exit 0 at c26f534; `cargo test` 23 passed at origin/main.
- ETXTBSY: `fs::copy` over a running executable returns os error 26, `rename` into the same path succeeds.
- The non-interactive skip firing on a pipe, and not firing under a real pty.
- The webserver config-write to code-execution chain, driven with a curl request shaped like a cross-origin form POST.
- The Content-Length abort taking down the listener.
- The health check accepting 404 and 500 with certain header orders, and correctly rejecting the real desktop's 404.
- `--dry-run` writing nix.conf and destroying an existing experimental-features line.
- `dim desktop --port 8088` exiting 2, and `dim config set webserver.port 9000` being accepted and ignored.
- The published install.sh at the R2 URL being byte-identical to the repo copy, and failing under dash.
- `dim log` reading ~/.dimos/data/actions.log; `dim install` writing to ~/.dimos/installs.
- uv and nix writing 0 bytes to stdout, which is what refuted the panic blocker.

**Verified by reading code and git history only.** These are correct as descriptions of the source; none was executed:

- Four separate service-management implementations (desktop.rs:783, service.rs:96, webserver.rs:136, uninstall.rs:85).
- The unescaped `Environment=` interpolation and its TODO (service.rs:61-62), and the launchd plist XML interpolation (desktop.rs:1070).
- /tmp staging of installers and units under fixed names before sudo execution (deps.rs:279, install.rs:1363, deps.rs:596, deps.rs:718).
- The rc.local multicast fallback producing a file with no shebang and no execute bit (sysconfig.rs:230).
- Jetson dry-run calling `ensure_sudo()` before no-op commands (boot.rs:85).
- The Intel Mac update path (update.rs:181) disagreeing with desktop.rs:206 about whether an x86_64 macOS artifact exists.
- Profile writes reporting success on a failed write (self_install.rs:274), and "HTTP/1.1 400 OK" reason phrases (webserver.rs:879).
- All README, AGENTS.md, CONTRIBUTING.md, and ai-manual-install-guide.md drift.

**Not covered:**

- No robot. Nothing ran on a Go2, a G1, or a Jetson. The apt, CycloneDDS, unitree webrtc, and jetson boot paths were read, not exercised.
- No macOS. launchd, Homebrew, xcode-select, and the plist templates are entirely unverified, and no Intel Mac was available.
- No fresh machine. Every run used an isolated $HOME on a box that already had nix, uv, and the desktop installed, so first-install behaviour is inferred.
- The CSRF vector was shape-verified with curl, not driven from a browser. Chrome's private network access may block a public page reaching loopback, which would blunt the drive-by case but not the local-process or LAN-bound cases.
- systemd restart-loop behaviour on a port collision is read off the unit text (`Restart=on-failure`, `RestartSec=5`), not observed across a reboot.
- One reviewer's measurements were taken on the wrong ref. The checkout is 10 commits ahead of origin/main on fix/jetson-non-interactive, which adds src/util/plan.rs and src/util/robot.rs and 17 tests. Any figure quoting 40 tests came from that branch; origin/main has 23. That branch also already fixes the robot half of the non-interactive skip.
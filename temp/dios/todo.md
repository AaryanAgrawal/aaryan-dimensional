# todo

## the package manager

- the release artifacts are still named `dim-<triple>`, and install.sh, update.rs and the Dockerfile
  still fetch that name. The binary is `dios` everywhere else, so a fresh install downloads dim-* and
  lands it as ~/.local/bin/dios. Rename the artifacts and the R2 paths when the next tag is cut, and
  change all three fetchers in the same commit — not before, or every existing install breaks.
- the systemd/launchd units keep their old names: dim.service, dim-webserver.service,
  dim-desktop.service. Renaming a unit on a machine that already has one is a migration (stop,
  disable, remove, write, enable), not a rename, and nothing here does that yet.
- `dios uninstall` removes ~/.local/bin/dios. A machine that was installed before the rename still
  has ~/.local/bin/dim, and nothing removes it. Same migration as the units.
- `DIM_VERSION` (install.sh) and `DIM_BRANCH` (cli.rs) keep their names — they are documented and
  people have them in scripts. Accept DIOS_* as well, then deprecate.
- a desktop package's build hook is still `dim/build.js` (commands/install.rs, deps.rs). That path is
  inside third-party packages, so renaming it is their migration, not ours.
- switch to whitelist instead of blacklist for extras
- have centralized place for changing data like, what is the default branch to clone, what system installs need to be run for each selected pip package, etc
- typed errors instead of matching on error text. Half done: "needs a human" is now a real type
  (`mode::Escalation`, matched by downcast, exit 2), and the exit code is decided in one function
  (`mode::exit_code_for`) instead of in main. Interrupted is still a substring search for
  "interrupted"/"cancelled" inside that function, so rewording an error anywhere else still changes
  whether a cancel reports as a failure. One more type finishes it.
- [done] a stage cannot prompt any more: every stage takes an `Ask`, which answers with the default
  when nobody is there, and `tests/prompts.rs` fails the build if anything under `src/pkg/setup/` or
  `src/infect/` reaches cliclack or dialoguer directly. What is left: `dios init` and `dios new`
  still prompt directly. They are wizards a person types by hand and never run as a stage, so they
  are not on the test's beat — move them onto `Ask` anyway, for one route instead of two.
- "can this machine install dimos" has two answers and two constants. setup gates on
  robot.rs::install_blockers (MIN_DISK_GB = 12), doctor gates on plan.rs::diagnose (MIN_DISK_GB =
  12), and the two are kept equal by hand. Delete install_blockers once setup consumes doctor's
  findings — that is the same wiring the plan calls "wire up the preflight", and it belongs to
  whoever owns setup/mod.rs next.
- [done] the reader's side of the doctor JSON contract now exists. infect's verb/helm.rs has
  has_blocker() plus two pinned literals — the blocked one copied from doctor.rs's own test, the
  healthy one the exact line this laptop printed at ecfc99b. Neither repo has CI, so nothing runs
  infect's copy when helm's shape moves; that is the half a contract test cannot fake.
- [done] `dios setup` grew `--smoke-blueprint` in dios/8 and verify.rs hardcodes nothing: no flag,
  no smoke test. No longer true that headless skips it: headless now runs the blueprint
  unconditionally, and the runner smokes once itself as the run's own final stage —
  `Helm::verb_args` no longer passes `--smoke-blueprint` through, because a smoke at helm time
  proves a half-built machine (verb/helm.rs says so where the flag used to be).
- decision (the plan is silent on it): `dios doctor --json` exits 0 even with blockers. A caller
  reads the findings array and counts severity == "block"; a diagnostic that refuses to report
  because it found something is useless to the tool asking it what is wrong. `dios setup`'s exit
  code stays the gate for "did the install work".
- [done] exit 0 no longer means "the install worked". run_setup now collects the stages that were
  auto-continued past unattended and exits 1 with {"failed_stages":[...]} on stderr. Was: all 13
  stages are critical=false, so a completely failed install exited 0 — and anything wrapping dios
  (CI, a provisioner) acted on that. Follow-ups: no test asserts this, and "verify install" only
  warns on a failed import, so exit 0 still does not prove dimos is importable.
- unverified: the dnf, pacman and apk package NAMES in deps.rs. No Fedora, Arch or Alpine box and no
  container runtime on this machine, so those three lists were never executed — only their command
  strings are unit-tested. A wrong name now prints the exact command and continues instead of
  failing the stage, which is the degrade-never-fail promise doing its job, but it is still a name
  someone has to check on real hardware. apt and brew are unchanged and still the only tested paths.
- decision (the plan is silent on it): the package manager is found by probing for the binary
  (apt-get, dnf, pacman, apk), not by mapping the distro ID. A derivative can carry any ID and still
  be apt-based, and it means Alpine needs no `Os::Alpine` variant — it lands as `Os::Linux` and the
  probe finds apk. macOS short-circuits to brew before the probe, as before.
- decision: musl is detected from /lib/ld-musl-<arch>.so.1, not from `ldd --version`. musl's ldd
  writes to stderr and exits 1, so cmd_output returns None on the very system we are trying to
  identify. Unverified on a real Alpine box; the path check itself is unit-tested against a temp dir.
- decision: NixOS keeps every answer it had before — glibc stays None, is_sim_supported stays false,
  the unitree SDK stage stays skipped. NixOS patches its own loader, so comparing its glibc to a
  manylinux tag decides nothing. Turning any of those on for NixOS is a separate call with its own
  evidence, not a side effect of naming more distros.
- `libc` is not in the `dios doctor --json` contract. os_display carries ", musl" for a human, but a
  machine reading the JSON still sees glibc: null on musl and cannot tell musl from "detection
  failed". Add a "libc" key when infect needs to tell those apart.
- `SystemInfo::is_jetson` and `is_old_jetson` are dead — nothing calls is_old_jetson, and is_jetson
  is called only by it. rustc does not warn because main.rs re-exports the module with `pub use`.
  Delete both when the robot code leaves helm; is_old_jetson at least no longer reads an Ubuntu
  release number, which would have called Debian 12 an old Jetson.
- `home_dir()` was defined twice by this stack (setup/install.rs and util/ui.rs, byte-identical) and
  written inline three more times. Now one `paths::home_dir()`. The remaining HOME reads deliberately
  keep their own fallbacks — unitree.rs and install.rs:701 use /tmp, desktop.rs and deps.rs use
  unwrap_or_default — so they are different questions, not more copies of this one.
- the repo is not rustfmt-clean and has no rustfmt.toml, so `cargo fmt --check` fails on ~280 places
  including build.rs on origin/main. `cargo fmt` here would be a whole-repo diff. Either adopt it in
  one formatting-only commit or drop it from the gate; today it is a check nobody can pass.
- inside `nix develop`, `ldd` resolves to the nix store's glibc (2.42 here) rather than the system's
  (2.39), so `dios doctor` run from the dev shell reports the shell's glibc. Shipped installs run the
  musl-static binary outside the shell and report the machine's. Only bites if doctor is ever run
  from inside a nix shell in CI.
- scan -> target registry: the first slice is in (src/infect/targets.rs, `targets` in
  ~/.dimos/config.json). scan records recipe-claimed sightings and tries known addresses before
  sweeping; a finished infect files recipe/lane/address/control/journal. Still open, per
  workspace/targets-design.md: names + a `dios target` CLI, fleet loops, promotion of MAC-less
  entries, reflash reset, and recording failed infects.
- scan: mDNS on wifi is a possible cheap addition — today wifi is a port sweep + declared pings
  only. Not needed for the robots we ship (a Go2 answers on 9991), so deferred.
- scan/identify: joining a robot's own interfaces still needs the robot to report both MACs (a
  wifi reply and a wired reply are two MACs). scan records each link's MAC; tying them is the
  registry's job via ssh `ip -o link`, per targets-design.md §6d.
- `--region cn`: rewrite apt/pip/nix sources to Chinese mirrors before the first fetch. The great
  firewall makes archive.ubuntu.com, pypi.org, github.com and cache.nixos.org unusable-to-slow, and
  every install in Shenzhen pays it. tuna/aliyun/ustc all mirror all three. Ask the Shenzhen office
  which they already use rather than picking one.
- offline bundle as a real release artifact, not a script: the DIMOSPAK payload (docker.rs, already
  written) + a pip wheelhouse + a nix closure. `nix copy --to file://` and
  `pip download -d wheelhouse/` are the two halves. Today pack_docker is manual and nothing in CI
  produces one.
- nix store never GCs itself: 1.1 GB on the robot after one install, 59 GB on this laptop after
  months. A long-lived robot grows until the disk stops it. Schedule nix-collect-garbage.
- tailscale: default OFF until the account question is settled. With no --ts-authkey the script
  prints a login URL and the robot joins whoever clicks it — very likely a personal account, which
  means the fleet loses remote access when that person leaves. Needs an org tailnet and a reusable
  TAGGED key (a tagged node is owned by the tailnet, not the authenticating user). See
  workspace/tailscale-decision.md.

## the modes work

- **doctor has one mode.** `dios doctor` renders for a human and `--json` for a program, but it does
  not know about `Mode`: agent mode should escalate a blocker the way a critical stage does (the
  same `Escalation` block, the same exit 2) instead of printing it and exiting 0. `--agent doctor`
  is documented in the help as if it did.
- **nothing runs a model.** The failure menu offers "let the agent try" when config `agent.model` is
  set, and choosing it escalates with the reason instead of calling anything. Either wire it to a
  model or drop the item — an option that does not do what it says is worse than three options.
- **`dios setup` stage criticality is still a literal.** All 13 call sites pass `NonCritical`, which
  is what they were, so nothing changed under anyone. A recipe author declares criticality per step;
  the package manager's own stages have no author to ask. Decide which of them are load-bearing
  (`install DimOS` and `record service PATH` are the candidates) with someone who owns setup.

## the boundary

`tests/boundary.rs` fails the build if anything under `src/pkg/` names a robot, a vendor, a recipe
or the infect layer. Three files are on its ALLOWED list (down from six in dios/8), each one a line
here. The list can only shrink: an entry whose file has gone clean also fails the build.

- **`setup/install.rs`** says `unitree` because a pip extra of the dimos package is called that,
  the platform chooser lists it by name, and the aarch64 wheel workaround names the package. Package
  names are the one honest exception; it goes only if the chooser labels ever come from the fetched
  pyproject instead of literals.
- **`compat.rs`** carries dimos' pyproject extras verbatim as a test fixture. Renaming an extra in a
  fixture would make the fixture a lie about the file it mirrors. It goes when the fixture is read
  from a checked-in copy of the real pyproject instead of a literal.
- **`commands/webserver.rs`** builds the path `<dimos.dir>/dimos/robot/all_blueprints.py`. That is a
  filename in another repo. It goes when dimos exposes its blueprint list as a command.
- **The smoke incantation is defined twice, once per side of the boundary.** `SMOKE_TIMEOUT_S` and
  the `timeout … dimos --rerun-open none run …` command line live in both `src/infect/runner.rs`
  (44, 639) and `src/pkg/setup/verify.rs` (111, 175). One shared home would cross into pkg, which
  is upstream code — so the duplication stays until upstream takes the constant, and until then the
  two must be changed together.

Delisted in dios/8, and what the deletion assumed:

- **`setup/unitree.rs` is gone.** The vendor SDK build was a duplicate of the recipe steps
  (`cyclonedds_build.sh` + `unitree_python.sh`, both wired into the g1 recipe); the recipe copy won
  because its venv/CYCLONEDDS_HOME handling is proven by the recipe's own verify steps. Consequences,
  both unverified on hardware: (1) standalone `dios setup --extras unitree` on a laptop no longer
  builds CycloneDDS/unitree_sdk2py — the pip extra installs, the native SDK is bring-up's job; run
  the g1 recipe steps by hand if a laptop needs DDS. (2) the go2 lanes run helm with
  extras=["unitree"] and get no native SDK on the laptop — believed fine (webrtc lane uses the
  webrtc driver from the pip extra, zenoh lane talks to the bridge), but if a go2 lane turns out to
  need unitree_sdk2py, add the two unitree steps to that lane. Also gone with it:
  `ensure_cyclonedds_home_in_rc` (the recipe script writes the rc export itself) and the
  "persist CYCLONEDDS_HOME" stage.
- **`setup/verify.rs`** now takes `--smoke-blueprint`; without the flag there is no smoke test, so
  an interactive `dios setup` that used to offer the hardcoded go2 sim smoke no longer does unless
  the flag is passed.
- **`commands/service.rs`** forwards named platform vars plus whatever `--env KEY[=VALUE]` the
  caller adds (bare KEY forwards the current value, KEY=VALUE sets it, systemd last-assignment
  wins). ROBOT_IP left the named list; a recipe that needs it passes `--env ROBOT_IP`. Unverified:
  no shipped recipe invokes `dios service setup` yet, so nothing exercises `--env` end to end.
  Pre-existing, moved here from a code TODO: the unit file Environment= lines are not escaped
  against values containing `"` or newlines.

## the provisioner

### Next phase (not this one)

- [done] **The runner** (`infect/runner.rs`, dios/6-runner): params from --param/env/prompt,
  `{name}` filled everywhere before anything runs, phases in order, journal per MAC, failure
  policy through `stage::handle`, all behind a `Transport` seam a test fakes. What it still does
  not do: `Escalation::notes_from(&recipe.notes)` remains uncalled — `stage::handle` builds its
  escalation without the recipe's troubleshooting table, so wiring the notes in means handing the
  table to `handle` or enriching the error above it.
- **The bringup phase.** `[network].wired` plus `net.wired-profile`, `net.wait-carrier` and
  `net.wait-reply`, run *before* matching — which is why they are not steps (see below).
- Live probing: fill `Facts` by touching the network once, so `infect recipe test` works against a
  robot as well as a recorded fact table.
- [done] `recipe new|add|remove` exist, and `add` has the trust gate: entitlements printed before
  install, a confirm naming the maintainer, and under `--agent` an unknown maintainer escalates
  (exit 2) instead of installing. `add` takes a name (index-resolved, rev-pinned, sha256-checked)
  or a git URL as the escape hatch; installs are ledgered in ~/.dimos/recipes.json.
- The fake robot (helm ships a Dockerfile impersonating a Jetson) — highest-value test target,
  since the whole pre/post-helm sequence can run against something that cannot be damaged.
- [done] Script steps execute: the runner resolves them through `manifest::script_path` (the same
  function the doctor uses, not a second copy), stages to `/tmp/infect-<id>.sh` on the robot side,
  and runs `timeout <timeout_s> bash` there. `dios verb run` still cannot run a script.
- **A lane cannot reference a step by id.** `dios doctor --recipe` was asked to fail a lane naming
  a step that does not exist, and there is no field that names one: a lane step whose id matches
  replaces that step, and one that does not appear appends. So a typo'd id silently adds a step
  instead of overriding the intended one. The doctor says which lane steps override (Info) and
  cannot say which meant to. Either give a lane an explicit `replaces = "<id>"`, or accept the
  merge rule and delete this line.
- [done] `dios doctor --recipe` is restored to files-only — manifest, verbs, scripts, placeholders,
  phases, proofs, entitlements, probes, lanes; same findings, same `--json` shape, and its --help
  says so. Judging a proof against the live machine is `dios infect check`'s job, not the doctor's.
  The week's cleanup overall is ~490 lines cut.

### What blocks a real robot

- [done] **Every robot now has an unattended smoke test.** The confirm-and-display gate is gone:
  the runner runs `timeout 120 dimos --rerun-open none run <blueprint>` (120 s bound, exit 124
  counts as alive-not-crashed) as its own final stage, after post-helm and `[config]`, under
  `bash -lc` so the post-helm exports apply. `helm.deliver` no longer forwards `--smoke-blueprint`
  — a smoke at helm time proves a half-built machine. Unproven on hardware: the robot has been
  offline since it landed.
- **`nmcli connection up <profile> passwd-file <file>` is unverified on a G1.** It is the documented
  way to hand nmcli a secret without putting it in argv, which the task requires. What is unproven
  is whether NetworkManager then *stores* the psk in the profile (secret flags default to 0, which
  should mean system-owned and saved). If it does not, the robot joins now and forgets on reboot.
  Check on hardware with `nmcli -s -g 802-11-wireless-security.psk connection show <profile>`.
- **`dimos run` cannot work with no arguments.** The plan's measure of success is not reachable:
  `dimos run` takes `robot_types` as a *required* positional, and `GlobalConfig` is
  `extra="ignore"`, so a `DIMOS_BLUEPRINT` key in `.env` would be silently dropped. `config.write`
  therefore writes only what dimos reads — `DIMOS_TRANSPORT` and env keys like `ROBOT_IP` — and the
  blueprint stays the operator's argument. Rewording the goal is the honest fix.
- **`go2-zenoh-basic` and `go2-zenoh-nav` do not exist** in `workspace/dimos` (branch
  `feat/on-run-extras`): `all_blueprints.py` has no zenoh entry at all. The names come from the plan
  and leshy's PR. The Go2 zenoh lane names them anyway; the smoke test is where that surfaces.
- **The Go2 payload has no fetch story** (DIM-1406). `[payload.go2web].source` is a repo URL;
  `payload.deliver` takes a local file. The step between them — build or download for aarch64,
  check `sha256` — is not written.
- **`publishes` for go2web is a listening socket, not a subscription.** `ss -ltnH sport eq :7447`
  proves the zenoh endpoint is up on the robot (verified that this syntax works and that it exits 0
  with no output either way, which is why `publishes_has` exists). The real proof is a subscriber
  seeing `dimos/odom/*`; dimos ships no zenoh topic CLI today (`lcmspy` and `agentspy` only).

### Decisions taken where the plan was silent

- **A verb is a pure function to a `Plan`; only `exec` touches the world.** Dry-run is therefore
  structural: `Mode::DryRun` returns before anything is spawned, so it cannot change a machine and
  cannot ask for a privilege — the bug helm had, made unreachable rather than remembered.
- **Bringup is not a step.** Steps run after matching, and you cannot match a robot you have no
  address for. `[network].wired` stays recipe data that the bringup phase feeds to the net verbs.
- **`extends` merges, one level.** The base contributes what the child did not say; the child wins
  where both speak. Steps merge by id exactly as a lane's do, entitlements are a union, probes
  concatenate. A base that extends something is refused, so a recipe is always two files.
- **`Resolved.steps` is in run order** (stable sort by phase), so a base's post-helm step cannot
  appear before the child's pre-helm ones just because the base was read first.
- **Two charsets, not one.** Anything that becomes a command word takes `[A-Za-z0-9,._:/@-]`; an
  SSID also takes a space, because office networks have them and an SSID is only ever data. A
  password is checked by nothing, which is exactly why it may only go to stdin.
- **`wifi.join` has no `key_mgmt` argument.** wpa-psk is forced, and passing the arg is an error.
  The guide's WPA3 failure is not documented here, it is unreachable.
- **`payload.deliver` requires `publishes`.** A payload that is installed, enabled and silent is the
  failure the verb exists to catch, so there is no way to declare one without a publishing proof.
- **`helm.deliver` has no check.** Re-running helm is the supported resume path and it is
  idempotent; skipping it on a weak signal ("the binary is there") would be worse than re-running.
- **`helm.deliver` reads helm's findings, not its exit code.** `dim doctor --json` exits 0 even when
  it found a blocker — that is helm's deliberate decision, and its own `--help` says "anything
  wrapping dim should gate on block". So the exit code alone would have passed a machine helm had
  just refused. `Probe::no_blockers` parses the JSON and counts `severity == "block"`. Output infect
  cannot parse counts as blocked: unreadable output means helm's contract moved, which is exactly
  when not to install on top of it. Proven by running both cases against a fake `dim` that exits 0.
- **Entitlements are enforced, not decorative.** `verb::needs` says what each verb touches by side,
  and `infect recipe show` refuses a recipe whose steps exceed its declaration. A script step on the
  robot counts as needing `ssh`; nothing else about a script can be known.
- **Tailscale is declared and off** (`enabled = false`, `[[step]] id = "tailscale"` in the unitree
  base). Which tailnet a robot joins is unsettled — `workspace/tailscale-decision.md` recommends an
  OAuth client minting a tagged single-use key on the laptop, and nobody has created it. Defaulting
  a step that silently binds a robot to an unspecified account is worse than opt-in. The script
  fails loudly when `/run/infect-ts.key` is absent rather than printing a login URL.
- **`jetson.max-perf` and the LCM sysctl tuning stay in helm for now.** The plan moves them, but
  nothing is deleted until it is replaced, and duplicating them in the G1 recipe would mean both
  tools setting the same knob. They become recipe steps in the same change that deletes
  `src/pkg/setup/boot.rs`.
- **The wifi psk file lives at `/run/infect-wifi.psk`.** Only root can write `/run`, so a
  predictable name there cannot be pre-planted as a symlink by another user, which `/tmp` allows.
- **The robot's password is read from `INFECT_ROBOT_PASSWORD`**, never a flag, and reaches `sudo -S`
  on stdin. `ssh.install-key` is the one interactive op: the operator types the factory password
  into their own terminal once, and everything after it is BatchMode key auth.

### Open

- **Untethered ssh is not a step.** The guide's step 3 (prove wifi ssh before unplugging) needs the
  robot's DHCP address, which means reading `hostname -I` on the robot into a param. Captures come
  only from probes today. It is in the G1 `[notes]` instead.
- **Contract tests exist, CI does not.** `verb/helm.rs` pins two `dim doctor --json` literals and
  the flag set `dim setup` accepts. Nothing runs them when *helm* changes, which is the direction
  drift actually travels. Neither repo has CI; until one does, the pin catches a careless edit to
  infect and nothing else.
- **Which tailnet, and whose account?** Unanswered, and it is the reason the tailscale step ships
  `enabled = false`. `workspace/tailscale-decision.md` recommends a tailnet-owned OAuth client
  (scope `auth_keys`, tag `tag:robot`) that the laptop exchanges for a single-use, pre-approved,
  non-ephemeral, 10-minute key. Nobody has created that client, the `tagOwners`/`acls`/`ssh` policy
  block is not in any tailnet, and it is unknown whether the robots already deployed joined a
  personal account. A robot on someone's personal tailnet disappears when they leave. See
  OPEN_QUESTIONS.md — this one needs Aaryan, not an agent.
- **Nothing here has met a robot.** Every fact table is written by hand; the executor has run
  against this laptop only (`net.wait-carrier` on `lo`, `config.write` into a scratch directory).
- **`facts/*.json` are hand-written, and the filenames say so.** They exist so
  `infect recipe test --facts` has data at all, and a test asserts each one picks its own robot, so
  a `Facts` schema change or a probe edit breaks the build rather than a demo. Record a real probe
  pass from the G1 and the Go2 and check those in as `facts/g1-recorded.json` — then the difference
  between a guess and a measurement is visible in `ls`.

### After the merge

- **`recipes/` is looked up relative to the working directory** (`--recipes`, default `recipes`), so
  `dios recipe list` works in a checkout and finds nothing anywhere else. Decide: embed the shipped
  recipes in the binary, or install them to ~/.dimos/recipes and default there. `recipe add` needs
  the same answer.
- **infect still calls the package manager "helm"** — the verb is `helm.deliver`, the manifest table
  is `[helm]`, and the phases are pre-helm/post-helm. It is `pkg` now and the binary is `dios`.
  Renaming those changes the recipe format, so it wants an `infect_api` bump, not a sed.
- **The pinned `dios doctor --json` literals in `verb/helm.rs` are still pinned by hand.** They now
  match `commands/doctor.rs`'s own test literal, which is what makes them a contract test — but
  nothing runs one when the other changes. There is still no CI.
- [done] **`dios infect --with <recipe>` runs the recipe** (dios/6-runner). Its `--dry-run` now
  prints the runner's own assembly — every plan it would drive, in order — instead of sharing
  `recipe::cmd::print_plan` with `recipe show`, so those two can drift again; `recipe show` keeps
  the entitlements view. Dry run and real run cannot drift from each other: both consume the one
  `assemble` list, and `dry_run` cannot even take a `Transport`.
- **`InstallPlan`/`plan::plan` is dead code** — nothing outside its own tests calls it. It survived
  the merge because the robot half was what the boundary forced out, not the whole function. Either
  `setup` consumes it or it goes.

### After the integration (dios/5-integration, 2026-08-10)

- **A remote command has no timeout.** `ssh_argv` passes `ConnectTimeout=10`, which stops applying
  once the connection is up, and nothing bounds the command itself. A robot whose login shell
  blocks on a prompt — the G1's `ros:foxy(1) noetic(2)` selector is the live suspect — hangs a step
  forever rather than failing it. docs/TESTING_TOMORROW.md step 0 is the check. If it hangs, the
  fix is a deadline on `Run::Cmd`, not only a note in the recipe.
- **`timeout_s` is enforced only on the runner's script path**, as coreutils `timeout` around the
  staged script. A verb step, a verify probe and every other ssh command still have no deadline —
  that fix is a deadline on `Run::Cmd` itself — and the blocking-login-shell hang
  (TESTING_TOMORROW.md step 0) sits in front of all of it.
- **`--with` matches a recipe's name only.** `--with g1` is refused with the names that loaded, but
  `g1` is the directory and the obvious thing to type. Decide whether a unique suffix or directory
  name resolves, and apply the same rule to `recipe show` and `doctor --recipe` or to none of them.
- [done] **A fresh scaffold is doctor-clean** (dios/9): the scaffold now writes a live `[helm]`
  (mode=dev, extras=[], smoke_blueprint still commented so the unknown-blueprint check stays
  quiet), and the pinned test expects zero findings. The cost, recorded: the scaffold is no
  longer fully inert — a hypothetical `dios infect --with <fresh>` would plan a helm delivery.
  Its one step stays `enabled = false` and it has no `[match]` probes, no `[network]` and no
  `[ssh]`, so nothing proposes it and bringup cannot reach a robot for it.
- [done] **`dios verb` is in the spec's CLI list now.** docs/PRD.md's interface section was
  regenerated from the rebuilt binary's own --help on 2026-08-11 and names verb, webserver and
  service — the old list was non-exhaustive, not a decision to delete them.
- **rustfmt is still not adopted.** infect's `rustfmt.toml` (max_width=100, use_small_heuristics=Max)
  was dropped at the merge because helm's tree is not fmt-clean. Either take it repo-wide in one
  formatting-only commit, or drop `cargo fmt --check` from the gate.
- **The nix derivation is still `pname = "dim-${rustTarget}"`.** It only names a store path
  (`/nix/store/…-dim-aarch64-unknown-linux-musl-0.3.97`). Rename it with the artifacts.

### After the nine (dios/9-integration, 2026-08-10)

- **The three branches merged clean but the seams are untested against each other on hardware.**
  What is proven by the suite and the dry runs: the runner's helm step now carries
  `--smoke-blueprint` from `[helm].smoke_blueprint` (dios/6 x dios/8 composed), and scan's
  proposal names the recipe the runner accepts. What is not: scan's captured `{robot_ip}` does
  not yet feed the runner's params — scan emits Observations via `--json` and the runner still
  wants `--param robot_ip=…` (both sides written, the pipe between them is not).
- **`dios infect` without `--with` now points at scan** in its error, but does not run it.
  Deciding whether `infect` may auto-adopt scan's single unambiguous proposal is a trust
  question, not a plumbing one.

### After the runner (dios/6-runner, 2026-08-10)

- **The helm binary the runner pushes is `current_exe` unless `--param helm_binary=` names one.**
  A robot of another arch needs the operator to `nix build .#linux-arm64` and pass the result. The
  real fix is fetching the release artifact for the target's arch, which is the same artifact
  story as the dim->dios rename above.
- **Nothing fetches a payload.** The runner expands `payload = "go2web"` from `[payload.go2web]`
  and pushes from `~/.cache/infect/go2web`, which the fetch step (DIM-1406) is supposed to
  produce. Until it exists the file must be put there by hand, and `scp` fails loudly when it is
  not.
- **Captures are values only `--param` can supply.** `{robot_ip}` on the Go2 comes from a
  port-sweep capture, and there is no live probe pass, so today it is `--param robot_ip=…`. When
  scan exists, `identify()`'s captures feed the same `Values` and the flag becomes an override.
- **`Live::identity` needs a neighbour-table entry.** `ip neigh show <addr>` only answers after
  the laptop has talked to the robot; bringup does that, and the error says to ping otherwise. A
  robot on the far side of a router has no lladdr at all and needs another identity source.
- **The runner's per-step lines are `println!`**, not the cliclack styling the setup stages use.
  Cosmetic, but the two halves of `dios infect` currently read differently.
- **"fix in a shell" is judged by the proof, unverified interactively.** After `stage::handle`
  continues past a failure, the runner re-checks the step's verify and upgrades the journal to Ok
  when it holds. The path is tested with a fake transport
  (`tests/runner.rs::a_failure_whose_proof_holds_anyway_is_not_a_failure`); nobody has driven the
  actual menu against a real shell yet.

## Found on the real G1, 2026-08-10

- THE LAST GAP FOR A ONE-COMMAND INSTALL: the recipe has no answer for sudo ON THE ROBOT. A real
  run reached the helm step and `dios setup` exited 1 with
  {"failed_stages":["jetson boot config","system config"]} — both need root, the ssh session has no
  tty and no SUDO_ASKPASS, so ensure_sudo failed fast with its remedy (correct). Supplying
  SUDO_ASKPASS by hand then completed the install, exit 0. So the fix is small and known: the
  recipe should stage an askpass helper from the [ssh].password it already declares, export it for
  the helm step, and remove it afterwards — the same shape as wifi.join's psk handling, which
  already writes a 0600 file to /run and deletes it. Do NOT put the password in the command line.
- Verified on hardware the same run: idempotence holds. wifi, git-https and cyclonedds all reported
  "already done" from their own verify, on a robot provisioned Monday. That is the case operators
  hit most and it was never tested until now.
- Verified: the ros:foxy/noetic login selector does NOT hang a non-interactive ssh
  (`ssh unitree@... 'echo hi'` -> "hi", exit 0). The whole verb layer rests on this.

## The install must prove a blueprint RUNS, not that imports work

The whole point: an install that reports success on a robot that cannot start a blueprint has not
installed anything. On 2026-08-11 that is exactly what happened — every recipe proof passed, doctor
was clean, and the first `dimos run` died on an import.

- [done] dios never ran a blueprint on a robot: `pkg/setup/verify.rs` skipped the smoke test when
  `info.is_headless()`, which is every robot, so `smoke_blueprint = "unitree-g1"` had never once
  executed. Fixed, but NOT where it was first put: running it inside the `dios setup` that helm
  invokes fires before post-helm and `[config]`, so it reproduced our own documented failures and
  broke provisioning. It is now the runner's own final stage, after post-helm and config —
  `bash -lc` so the post-helm exports apply, `timeout 120` with exit 124 counting as a pass.
  `dios setup --smoke-blueprint` still works standalone. The go2 lanes got it for free.
- [done] doctor rated the fact that predicts the most common failure as advisory. `pkg/plan.rs`
  emitted the glibc finding at `Severity::Info` with `fix: null`. Now Warn on aarch64 with the
  verified two-library LD_PRELOAD line as its fix. Deliberately never Block: helm gates on block,
  and a false block is what stops an install that would have worked.
- [done] "persist network optimizations" only half persisted — the sysctl survived a reboot, the
  `ip link`/`ip route` half could not. Now written into `/etc/systemd/system/dimos-multicast.service`.
- [wrong — the incident never happened] "a recipe that fails to parse takes down every other
  recipe" was reported from `recipes/go2/recipe.toml:32` (`kind = "ble-name"`). `Probe::BleName`
  exists at `src/infect/identify.rs:72` and `dios recipe list` lists both recipes. The finding came
  from running a **stale `target/release/dios`** built before BleName landed. `load_dir` now skips
  and reports an unparseable recipe anyway, which is worth having on its own — but the motivating
  bug was an artefact of the binary, not the tree. Rebuild before believing a CLI.

## Found on the real G1, 2026-08-11

- The blueprint reached module deployment for the first time: 10 modules deployed across 8 workers,
  every transport wired, Rerun gRPC up. Everything below is what stands between that and a robot
  that moves.
- `robot_ip` defaults to `None` and reaches the WebRTC driver as the literal string `"none"`:
  `HTTPConnectionPool(host='none', port=8081)`. Nothing validates it before dialing, and the driver's
  own error says "Check if the Go2 is switched on" on a G1. Pass `--robot-ip 192.168.123.161`.
  [done, the dios half] a recipe knows its robot's address, and now writes it: the g1 recipe
  carries `ROBOT_IP = "192.168.123.161"` in `[config] env` (recipes/g1/recipe.toml) and
  `config.write` lands it in the `.env` the robot runs with, so the flag is an override rather than
  the operator's memory. Still upstream: dimos validating the value before dialing it.
- dimos main cannot connect a G1 over WebRTC on any published driver. `connection.py` passes
  `aes_128_key=` to `unitree-webrtc-connect`, whose newest release (2.1.2, confirmed against the index
  with and without the project's `exclude-newer`) has no such parameter. Patched on the robot to pass
  it only when set. Upstream needs either the driver released or the call made conditional.
- the camera never opens: `/dev/video0` through `video5` all exist, and cv2 still fails with
  `can't open camera by index` / `Failed to open camera 0`. The guide blames an unplugged USB-C
  cable, but the nodes are present, so that explanation does not fit this failure. Unknown — needs a
  look at which of the six nodes is the head camera and whether it is a capture device at all.
- `dimos run` opens the native viewer on the robot unless told not to, and dies in wgpu
  (`libEGL DRI3 failed` → `wgpu error: Out of Memory`) because the robot is headless. `--rerun-open
  none` is not a preference on a robot, it is the only correct value; the default should follow
  headless detection, which dios already computes.
- `No direct transform found between 'world' and 'base_link'` logs once a second forever while the
  robot is not connected. One line per second for a condition that will not change on its own is
  noise that hides the real error above it.

## roadmap

- **Fleet: loop over many targets.** The target registry (`targets` in ~/.dimos/config.json) is the
  first slice; the loop itself — one command driving every filed robot, "build once, infect many" —
  is not written. Per workspace/targets-design.md.
- **Diagnose-then-repair, read-only half first.** `dios infect check` already judges every proof
  live and applies nothing, but only from the laptop that holds the recipe and journal. The
  read-only half to build is asking "what state is this machine in?" from a laptop that never ran
  the infect (ARCHITECTURE.md §14) — and only after that a repair mode that runs exactly the steps
  whose proofs fail (R12).
- **A regional mirror for China.** The index is one static JSON file plus the git repos it points
  at, so the mechanism already exists: `dios config set recipes.index <url>` pointed at a mirrored
  copy, no code path of its own. What is missing is the mirror itself. Complements the `--region cn`
  apt/pip/nix rewrite item in the package manager section — different fetches, same firewall.

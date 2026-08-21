# dios — decisions and open questions

Written 2026-08-10 against `dimos-bios` at `0252d3b`. Sources: `infect-plan.html`,
`dios-plan.html`, `tailscale-decision.md`, `china-delivery.md`, `targets-design.md`,
`simplify-dios.md`, `wendyos-study.md`, and the repo's own `todo.md` / `OPEN_QUESTIONS.md` /
`CHANGELOG.md`.

Anything marked **[agent]** was decided by an agent, not by you. Those are the ones to check.
Everything else is either yours or is a fact the code already enforces.

The tree is 19,191 lines of Rust: 12,176 under `src/pkg/`, 4,961 under `src/infect/`. Another
workflow is editing it as I write — `src/infect/recipe/{cmd,mod}.rs` are modified and
`src/util/ask.rs`, `src/util/mode.rs`, `src/infect/recipe/scaffold.rs` are new, so the Ask
injection in §6.3 is being built right now. I wrote nothing into that repo.

---

## 1. Decisions made

### Naming and structure

**The binary is `dios`, in one repo.** `dimos-infect` merged in with its history at `d32ae68`;
the Cargo package was still called `test-rs-cross`. This rules out shipping the provisioner as a
separate product and rules out the cross-repo JSON contract that the review named as the top
long-term risk. Reversible in a day at the cost of doing the merge over.

**[agent] Three things deliberately did not rename.** Release artifacts are still `dim-<triple>`,
`~/.dimos/` is still the config and state directory, and the systemd/launchd units keep
`dim.service`, `dim-webserver.service`, `dim-desktop.service`. Renaming a unit on a machine that
already has one is a migration — stop, disable, remove, write, enable — not a rename. So a fresh
install today downloads `dim-*` and lands it as `~/.local/bin/dios`, and a pre-rename machine keeps
an orphan `~/.local/bin/dim` that nothing removes. The artifact rename must change install.sh,
update.rs and the Dockerfile in one commit at the next tag, or every existing install breaks.

**[agent] The boundary became a test instead of a repo.** `src/pkg/` may not name a robot, a
vendor or a recipe, and may not reach `crate::infect`. `tests/boundary.rs` fails the build both
ways: on a violation, and on an allow-list entry whose file has gone clean, so the list can only
shrink. Six files are on it today, each one a line in `todo.md`. Two repos made a leak a compile
error for free; this buys the same property back for the price of a test someone could delete.

**`dios doctor` no longer reports a robot.** Identity is `dios infect`'s question. The `--json`
contract loses its `robot` finding; blockers and every platform key are unchanged. Consequently a
bare `dios setup --non-interactive` no longer promotes itself to a full DimOS install because it
detected a robot underneath — a recipe passes `--mode`/`--extras`, which is the same gate by a
route that does not require the package manager to look at hardware.

### The pkg/infect boundary

**One test resolves every ambiguous case: does the compat engine need this fact to pick a wheel?**
CUDA passes, so it stays in `pkg`. The Jetson's L4T version fails, even though both are read from
the same directory, so it belongs to `infect`.

**Infect is never a prerequisite for pkg.** `dios setup` works alone, on any machine, with no
orchestrator. Infect may *override* a platform fact — on a Tegra it should — but override is not
supply.

**Infect never parses human output.** Only `--json` and exit codes. That is what lets the package
manager change prompts, spinners and stage names without breaking recipes in the field.

**Exit codes now mean something** (`3ede7b9`). Before it, all thirteen stages were `critical=false`
and a completely failed install exited 0, which anything wrapping dios acted on. `run_setup` now
collects auto-continued stages and exits 1 with `{"failed_stages":[...]}` on stderr. No test asserts
this yet, and "verify install" still only warns on a failed import, so exit 0 does not yet prove
dimos is importable.

**[agent] `dios doctor --json` exits 0 even when it finds blockers.** A caller counts
`severity == "block"` in the findings array. A diagnostic that refuses to report because it found
something is useless to the tool asking it what is wrong. `dios setup`'s exit code stays the gate
for "did the install work".

**Nothing is deleted from pkg until infect replaces it.** At every point in the sequence a robot can
still be brought up with the tool that exists today.

### The recipe model

**A recipe is the unit third parties write** — a directory of manifest, steps and assets, in three
layers: a manifest the core reads without executing anything, a closed set of core verbs where the
dangerous operations are written once, and shell scripts as the escape hatch for the long tail (the
CycloneDDS build). Plus payloads, for a robot-resident binary that is neither dimos nor dios, and a
`[config]` block for what the robot should run afterwards. First-party recipes use the same external
format, so it is dogfooded from day one. Compiled-in Rust traits were rejected because they force a
third party to fork the tool.

**Steps carry a phase and the code enforces it:** pre-helm, then the install, then post-helm. The
Unitree Python bindings depend on the venv `dios setup` creates, so no simpler model can express the
G1.

**[agent] A verb is a pure function to a `Plan`; only `exec` touches the world.** Dry-run is
therefore structural — `Mode::DryRun` returns before anything is spawned, so it cannot change a
machine and cannot ask for a privilege. That is the bug the package manager had, made unreachable
rather than remembered.

**[agent] Bringup is not a step.** Steps run after matching, and you cannot match a robot you have
no address for. `[network].wired` stays recipe data that the bringup phase feeds to the net verbs.

**[agent] `extends` merges, one level only.** The base contributes what the child did not say; the
child wins where both speak; steps merge by id (replace in place, not append); entitlements union;
probes concatenate; a base that itself extends is refused, so a recipe is always two files. Three
judgement calls hide in there and none of them was made by a person — replace-in-place, the
entitlement union (a base quietly grants reach a reader of the child never sees), and the one-level
cap. Cheap to relax later, impossible to tighten once a third party ships a three-deep recipe.
`OPEN_QUESTIONS.md` #4 asks you to ratify it.

**[agent] Entitlements are an inert declaration, not a mechanism.** The wendy study proved
inertness by construction: scaffolding with `gpu,usb,persist` versus `gpio,i2c` produces
byte-identical Dockerfiles and source, differing only in four lines of JSON. We run `sudo` over ssh
and have no sandbox, so a recipe's `[entitlements]` block is something an operator reads before
trusting a stranger's recipe, and the core refusing a verb whose entitlement was never declared is
a drift check, not a security boundary. The recipe docs should say that outright so nobody mistakes
it for enforcement.

**[agent] The entitlement vocabulary stays short and closed.** Wendy's 17 types, 11 of which take
no parameters, is the target size. `oneOf` per type with `additionalProperties: false` — in TOML
that is an untagged enum with `deny_unknown_fields`, which serde gives directly, so
`{type=gpu, pins=[17]}` is rejected rather than ignored.

**[agent] Absent means absent.** A robot we could not probe for open ports has no `open_ports` key,
not `[]` and not `"unknown"`. Wendy's proto encodes the same rule with ten optional fields out of
sixteen.

**[agent] `wifi.join` forces `wpa-psk` and passing `key_mgmt` is an error.** Krishna's WPA3
workaround — `nmcli device wifi connect` fails on 20.04 with `Secrets were required (7)` — stops
being a paragraph someone must remember and becomes unreachable.

**[agent] `payload.deliver` requires a `publishes` proof.** A payload that is installed, enabled and
silent is exactly the failure the verb exists to catch, so there is no way to declare one without
one. `helm.deliver`, by contrast, has no check: re-running the installer is the supported resume
path and it is idempotent, so skipping it on a weak signal would be worse.

**[agent] Two charsets, not one.** Anything that becomes a command word takes
`[A-Za-z0-9,._:/@-]`; an SSID also takes a space because office networks have them; a password is
checked by nothing, which is why it may only travel on stdin.

**Matching is a closed set of read-only probes,** weighted, with a per-recipe threshold, and every
probe that fires records its evidence in words so the operator sees *why* infect thinks this is a
G1. **[agent]** the ambiguity margin is 10 points absolute — thresholds are per-recipe so a relative
rule would compare numbers on different scales, but 10 is a judgement, not a measurement.

### Delivery — China, Nix, offline

**Mirrors first, bundle second.** `dios setup --mirror cn` rewrites four files before the first
fetch and introduces no new artifact format. That turns a two-hour install into a normal one for a
whole office and it is configuration, not architecture.

**[agent] Aliyun for apt and PyPI, USTC for the Nix cache — not Tsinghua.** This is the one
counterintuitive number in the China work. Of 60 random store paths from this laptop, Tsinghua
served 1 and USTC 50; of the 35 that upstream definitely has, Tsinghua served **0** and USTC 35.
Tsinghua only had the 40 paths from a closure built today off current unstable. It mirrors the
channel head, not the cache.

**[agent] `ubuntu-ports`, not `ubuntu`.** The Orin NX is arm64 and Ubuntu serves arm64 from a
different host and a different path on every mirror. A `sources.list` that rewrites only
`archive.ubuntu.com` leaves the robot pointed at the slow host. Proven end to end by pulling a real
arm64 focal `.deb` through Aliyun.

**[agent] The offline artifact is a directory, not an image.** A cross-built wheelhouse plus a
`.deb` pool plus a python-build-standalone tarball, moved with rsync. Measured: 107 wheels, 512.8 MB
down, built from this x86 laptop in 5m24s, and rsync moves 1.5 MB of it when one wheel changes.
`docker load` is the only option on the list with no delta at all.

**Keep `DIMOSPAK`, change its contents.** `src/pkg/docker.rs` already implements a self-extracting
payload appended to the binary; it should carry that bundle instead of a `docker save` tar, and
become a CI-produced release artifact rather than a script someone remembers.

**Nix owns native modules; uv owns Python.** The ML stack — torch, ultralytics, transformers on
aarch64 with CUDA — is not in nixpkgs, and it is most of the install by volume. China changes how
each side is *delivered*, not where the line is. Worth naming the tension you are buying: we
designed dependencies to install on run, which is dynamic and incremental, and Nix is static and
whole-closure. "Go very Nix heavy" quietly means giving up on-run installation for everything Nix
owns.

**Nix GC is not optional.** Measured 1.1 GB on the robot after one install and 59 GB on this laptop
after months. A long-lived robot grows until the disk stops it.

### Targets

**Storage is `~/.dimos/config.json` under a flat `targets.<mac>`.** Your instruction was "name mac
and ip and whatever else, in the config file locally".

**[agent] Identity is the MAC, never the IP and never the hostname.** The G1's DHCP lease is 8 hours
and it moved during this project. `src/infect/journal.rs` is already MAC-keyed and says why in its
own header — a journal that cannot find its robot rebuilds CycloneDDS for fifteen minutes to learn
it was already built. The registry reuses that normalisation, and if the two ever disagree about
what a MAC looks like, a resume silently starts over. Those two normalisations are currently written
twice (`journal::RobotId` and `targets::Mac`) and should be one type on graft.

**[agent] Both writers go through one `upsert(root, &Observation)` where every field is optional and
absence never overwrites presence.** A cheap `dios infect scan` cannot blank what an expensive
completed `dios infect` recorded. This is the load-bearing decision in the whole registry.

**[agent] `links[]`, not a single `ip`.** A G1 is on cable and wifi at once with a different MAC per
interface, so each link carries its own mac/via/iface/last_seen and `ip` is derived from `links[0]`.
This is the one place your literal words were not followed; `dios target list` still prints an IP
column. Also: a robot reached through a router has no MAC at all — verified,
`ip neigh get 8.8.8.8 dev wlp129s0` returns "Neighbour entry not found" — so a MAC-less target filed
under `name:<slug>` and promoted later has to exist.

**[agent] `installed[]`, not a boolean.** "Installed onto" and "can talk to" are different facts,
because the Go2 zenoh lane puts our bridge on the robot while dimos runs on the laptop, and the
webrtc lane never touches the robot at all.

**[agent] Never key or name on the hostname.** Two robots called `ubuntu` is the case that breaks
it. Names are proposed from recipe tail plus MAC tail — `unitree-g1` + `8c:1f:64:00:11:22` gives
`g1-001122` — with numeric suffixes on collision. Renaming does not move the key, so the journal and
the default keep resolving.

### Failure policy and modes

**Degrade, never fail.** An unrecognised package manager prints the commands a human would run and
carries on. **[agent]** the package manager is found by probing for the binary (`apt-get`, `dnf`,
`pacman`, `apk`), not by mapping a distro ID, because a derivative can carry any ID and still be
apt-based — which also means Alpine needs no `Os::Alpine` variant. **[agent]** musl is detected from
`/lib/ld-musl-<arch>.so.1` and not from `ldd --version`, because musl's ldd writes to stderr and
exits 1 on the exact system we are trying to identify.

**No TTY is an explicit error, never a hang** — and the structural version of that rule is the one
that matters. `non_interactive` reaches every stage today, but each stage has to *remember* to
consult it, which is how `configure_jetson` hung 7/7 unattended installs (exit 124 with a tty
attached). 31 prompt sites across 8 files rely on that discipline. The decision is an injected
`Ask { Interactive | Defaults | Scripted }` with no other route to the terminal, so forgetting
becomes impossible rather than unlikely. Scripted also makes the wizard testable, which it is not
today. This is the shape that keeps recurring: correct information that nobody is forced to consult.
The same shape is `main.rs` picking its exit code by searching the error text for
"interrupted"/"cancelled", so rewording an error anywhere silently changes whether a cancel reports
as a failure — typed errors, matched on the variant.

**The failure menu is retry / fix in a shell / get help / let the agent try,** and the recipe's own
`verify` is ground truth, never the agent's claim. The agent proposes into the same machinery the
operator uses and gets no private path. With no model configured the fourth item disappears and
everything else works unchanged, which is the test of whether the agentic part is real or
decorative.

**[agent] Error text has a fixed template:** what was tried, the raw underlying error kept intact,
then every command that fixes it. Indexed array errors (`step[4] "cyclonedds": verify shell is
empty`). Enumerations list their valid members, generated from the enum so they cannot drift —
which is precisely what drifted for wendy, whose `--help` advertises three languages its own
validator rejects.

**[agent] Non-interactive defaults to the safe branch, and `--force` is split from the irreversible
case.** `dios infect --yes` must not imply "reflash the robot's network config".

**[agent] dios/9-integration merges runner + scan + unbrand** (dios/6, /7, /8 onto dios/5;
merge commits only, all six branches intact for review). Two conflicts, both resolved by keeping
both intents: `src/infect/mod.rs` declares `runner` and `scan`, TESTING_TOMORROW's cannot-test
list took the runner's exit-2 wording and unbrand's smoke_blueprint wording. The composition is
real, not just compiling: the runner's helm step now emits `--smoke-blueprint unitree-g1` because
dios/8 taught `helm.deliver` the flag and dios/6's assembly carries it. 223 tests green.

**[agent] A fresh scaffold is doctor-clean, at the price of a live `[helm]`.** `dios recipe new
demo && dios doctor --recipe demo` reports `+ clean` (the instruction was: fix the scaffold, not
the doctor). The previous position — keep the scaffold inert, pin the one Warn — is reversed in
§3 terms: the scaffold's `[helm]` block is now uncommented (mode=dev, extras=[]), its
`smoke_blueprint` stays commented so the unknown-blueprint drift check stays quiet, and the one
step still ships `enabled = false` with no `[match]`/`[network]`/`[ssh]`, so nothing proposes or
reaches a robot with it. If inert-scaffold matters more than clean-scaffold, the revert is one
comment marker plus the pinned test in `tests/recipe_doctor.rs`.

**[agent] Scan and the runner do not feed each other yet.** Scan captures `{robot_ip}` and emits
MAC-keyed Observations via `--json`; the runner takes captures only via `--param`. Wiring
scan's proposal (and its captures) into `dios infect` is a trust decision — auto-adopting a
single unambiguous match — recorded in todo.md, not taken by an agent.

---

## 2. Decisions that need you

### A. Which tailnet, and who owns the robots on it

Blocked: the tailscale step ships `enabled = false`, so no robot has a stable remote identity and
remote support means someone on the LAN. The mechanism is settled and verified against tailscale
1.102.2 — one tailnet-owned OAuth client, scope `auth_keys`, tag `tag:robot`, which the laptop
exchanges at bring-up for a single-use pre-approved 10-minute key. Tagging is the whole answer:
applying a tag removes user-based authentication, so the robot survives someone leaving, and it
disables the 180-day node-key expiry that would otherwise silently drop a warehouse robot.

What only you can answer: is there a servicerobotco.com tailnet and are you Owner/Admin on it; did
already-deployed robots join a personal account (if so they are already the failure mode and need
re-authenticating as `tag:robot`); and where the OAuth client secret lives on an operator laptop —
it is the one long-lived credential in the design and it is not in any repo.

Recommendation: create the org tailnet client and add the nine-line policy block. Until then the
tooling must never emit a login URL, because `scripts/g1-bringup.sh:359` does exactly that when no
key is given, and it never passes `--advertise-tags`, so even the keyed path produces a user-owned
node today.

### B. Delete `service.rs` and `webserver.rs`

`webserver.rs` is 899 lines and an unauthenticated remote-code-execution surface, demonstrated end
to end: a cross-origin unauthenticated `POST /api/config` wrote `dimos.dir`, and chaining it with
`POST /api/launch` created a file on disk. It reads config keys nothing sets — its `--help`
advertises `webserver.enabled` and `webserver.port` default 8088, all three false; it actually reads
`desktop.*`, so `config set desktop.port 8791` moves the webserver. It is also the sole reason ~30
crypto crates are linked. `service.rs` is 174 lines with zero callers, never registered by setup,
superseded by the desktop's per-user no-sudo service. `init.rs` (343) and `new_app.rs` (348) are
dead and do not compile against today's config — they reference `cfg.init_completed` on a
`serde_json::Value` — and are not declared as modules.

Options: delete all four now; or delete init/new_app now and put a deprecation note on the two
documented commands first.

Recommendation: delete `init.rs`, `new_app.rs` and `service.rs` tonight-safe, and delete
`webserver.rs` too unless you know of a customer script calling `dios webserver`. That is the only
thing separating "delete" from "delete after a note", and it is a question about machines an agent
cannot see. 1,764 lines and ~30 crates.

### C. Does the desktop stay in the repo

1,995 lines — 16% of the package-manager half — and it is a thing dios *installs*, downloaded from
R2, rather than code dios *contains*. It is load-bearing in `setup` today, so it is a project, not a
cut.

Options: leave it and accept the size; extract it as the first real dios package, which dogfoods the
package manager on itself.

Recommendation: extract, but not tonight and not as part of the simplification pass. The prior
question is whether the R2 download is the intended long-term shape or a stopgap, which decides
whether this is a move or a rewrite.

### D. Which China mirror

Aliyun, Tsinghua and USTC all serve apt and PyPI completely, including history — PyTurboJPEG has 37
sdists on pypi.org and all three list exactly 37. For the Nix cache the answer is not free: USTC,
because Tsinghua served 0 of 35 paths upstream definitely has.

Recommendation: ask the Shenzhen office what they already use for apt and pip and match it —
matching beats picking. Pin USTC for Nix regardless. And the prior question that is strictly better
than either: does Dimensional run an internal binary cache? If so, `--mirror cn` should point at it.

Separately, one item is yours alone: the bootstrap. `install.sh` pulls the 6.0 MB dios binary from
Cloudflare R2, which is the very first byte of every install and is reachable but not dependably
fast in China. Mirroring one static binary on a Chinese object store plus a `DIOS_BASE_URL` override
is cheap and nobody else can do it.

### E. Does `dios infect --with <recipe>` replace or supplement auto-match

Today `--with` names the robot and skips matching; the runner that walks a recipe end to end is the
next piece of work, and the command currently loads, audits and refuses loudly rather than
pretending. The match engine exists and is tested against recorded fact tables.

Options: `--with` is the only path and matching becomes `dios infect scan` output that a human reads
(simpler, one code path, an operator always names the robot); or matching stays the default and
`--with` is the override for ambiguity and for CI.

Recommendation: supplement, not replace — but make `--with` the *documented* path and matching the
convenience. The match engine's real value is the evidence lines ("ping .164: 1.2ms",
"~/g1plus_pc4_unitree_install"), which are worth keeping even when the operator already knows what
the robot is, because they are what tells you the robot is reachable in the way the recipe expects.
Matching should never act without confirmation regardless, so the two paths differ only in who types
the name.

### F. Blocking the Go2 entirely — go2web, and which extras each lane needs

`dimensionalOS/go2web` is private and unread. `[payload.go2web].source` is a repo URL,
`payload.deliver` takes a local file plus a sha256, and the step between them cannot be guessed: is
there a published aarch64 artifact, or does the operator build it, and on what, and what pins a
version. The `[payload]` table shape is a guess (DIM-1406). Separately, both Go2 lanes declare
`extras = ["unitree"]`, copied from the G1, and nobody checked it — the webrtc lane never touches
the robot and may not need it at all, and a wrong extras list is a multi-GB install of the wrong
wheels or a missing import at first run.

Recommendation: give an agent read access to go2web, or paste its README. This is the cheapest
unblock on the list and it gates the whole third deployment shape.

### G. Three smaller ones that still need a person

**Does `dimos run` get a default blueprint?** The plan's stated measure of success —
"`dimos run` with no arguments" — is not reachable: `robot_types` is a required positional and
`GlobalConfig` is `extra="ignore"`, so a `DIMOS_BLUEPRINT` key in `.env` is silently dropped. Either
reword the goal or change dimos, which is not this repo. Recommendation: reword; it is the honest
fix and the blueprint stays an argument.

**Does `dios setup` grow `--smoke-blueprint`?** Today no robot has a per-robot proof. If setup takes
the flag, the package manager learns what a blueprint is, which the boundary test says is a robot
fact. If the recipe runs the smoke itself as a post-helm step, the layering stays clean and the
change is bigger. Recommendation: the recipe runs it. Meanwhile `verify.rs` hardcodes a go2 sim
smoke behind an interactive confirm that `--non-interactive` never reaches, so it is not a fallback
either.

**Ratify the `extends` merge rule** (§1, recipe model). Cheap now, permanent once a third party
ships a recipe against it.

---

## 3. Reversals — arguments that were made and then lost

**The CUDA probe leaving the package manager.** An agent argued it was a robot fact and belonged in
infect. The design and the adversarial pass both refuted it, and the reason that held was not
tidiness but an invariant: the package manager must work standalone, so a developer with an NVIDIA
workstation gets a CUDA install by running `dios setup` and nothing else. The same test then cut the
other way on the Jetson's L4T version, which is read from the same directory and stays in infect —
which is what makes the rule a rule rather than a preference.

**`dim plan` as a command.** Proposed as part of the JSON contract, then cut as over-building
because `--dry-run` already answers the question it asked. `plan.rs` survives as pure functions with
13 tests over boards nobody owns; what was dropped is the surface.

**`--smoke-blueprint`, emitted then withdrawn.** Infect emitted the flag, clap rejects unknown
flags, and every install turned into a usage error at the robot. It is now declared per recipe and
printed as `(declared)` rather than passed, on the principle that the package manager owns its own
contract and infect does not invent flags for it. Still open, in §2.G.

**`for_match = true` on the Go2 port sweep.** In the plan, unexplained; dropped in the
implementation, because every probe already contributes both its weight and its capture on the same
hit. If it meant capture-without-scoring, the format needs the flag back.

**Two repos, then one.** `infect-plan.html` designed two products with a CLI contract between them,
precisely so a boundary leak would be a compile error. `dios-plan.html` merged them and replaced the
enforcement with a test. What moved the argument was contract drift: the exit code had already
rotted between the two halves, and the JSON shapes were next.

**The webserver as a feature.** It was treated as part of what the package manager offers; it is now
a delete candidate on evidence, because the audit demonstrated code execution through it end to end.

Worth noting for calibration: the targets skeleton's own tests caught two bugs in the design an
agent had just written — promotion of a MAC-less target was impossible because it matched by name
only when the observation had no MAC, and rename updated `targets.default` after deleting the old
key. Both were in prose that read fine.

---

## 4. What is unverified

**No robot has been touched since 2026-08-07.** Every MAC in the targets tests is a fixture, every
fact table in `recipes/` was written from Krishna's guide rather than probed off a machine, and the
whole G1 section of the plan has not been re-verified since. `dios infect probe --record` on the
real G1 is what converts those from assertions about a document into assertions about a robot.

**The G1 login-shell question is still unanswered and invalidates the verb layer if it goes wrong.**
The G1 prints a `ros:foxy(1) noetic(2)` selector on login. If that is not guarded on interactivity,
every non-interactive ssh step hangs. One command settles it:
`ssh unitree@10.0.0.190 'echo hi'`. Do it before another line of the G1 path is written.

**The container matrix has never been executed.** The fake-Jetson Dockerfile exists; no container
runtime on this machine ran it, so the pre-helm/post-helm sequence has never run against anything.

**`nmcli connection up <profile> passwd-file <file>` is unproven on a G1.** It is the documented way
to hand nmcli a secret without putting it in argv. What is unknown is whether NetworkManager then
*stores* the psk, or whether the robot joins now and forgets on reboot. Check with
`nmcli -s -g 802-11-wireless-security.psk connection show <profile>`.

**`go2-zenoh-basic` and `go2-zenoh-nav` do not exist.** Zero matches for "zenoh" anywhere in
`dimos/robot/all_blueprints.py` on `feat/on-run-extras`. The zenoh lane names them anyway. Also
unproven: `publishes` for go2web checks a listening socket (`ss -ltnH sport eq :7447`), not that
anything is on it — and dimos ships no zenoh topic CLI, so the real proof does not exist yet.

**Everything about China was measured from outside the firewall.** Reachability, completeness and
correct bytes are proven; throughput and packet loss on the path a robot in Shenzhen actually takes
are not, and cannot be from here. The wheelhouse cross-*download* was verified; installing those 107
wheels on a real aarch64 Jetson was not, and that is where a wrong manylinux tag would surface.
Torch and CUDA on a Jetson come from NVIDIA's index rather than PyPI and were not measured at all —
4.3 GB of `nvidia/` plus 1.7 GB of `torch/` in the x86 venv here, so that is the part of the problem
that dwarfs everything that was measured.

**The dnf, pacman and apk package names were never executed.** No Fedora, Arch or Alpine box. Only
their command strings are unit-tested. A wrong name prints the command and continues, which is the
degrade-never-fail promise working, but it is still a name someone has to check. musl detection is
likewise unverified on a real Alpine box.

**`config::save` is not atomic** — read-modify-write, no lock, no temp file — so two concurrent
`dios infect` runs can lose a target. `journal.rs` already writes through `.tmp` + rename for exactly
this reason, and the same class of bug was reproduced in wendy's `config.json`, where a first-run
race silently dropped a key. The fix belongs in `config.rs` and was not made, because that file is
in the repo another workflow is editing.

**The line-count math in `simplify-dios.md` is pre-merge.** It measured 13,986 lines at `7b17725`;
the tree is 19,191 today. The four deletions are still 1,764 lines and the argument is unchanged,
but "12,222 lines afterwards" is stale.

**Wendy's device model is a wire schema, not an observed response.** There is no WendyOS device on
this network, so device info, hardware, camera, wifi, run and tour were read from protobuf
descriptors and embedded docs, never run. That does not affect anything we take from it — the
entitlement, error and non-interactive lessons all came from commands that ran — but it means the
device-facts comparison in §I1 of that study is design-to-design.

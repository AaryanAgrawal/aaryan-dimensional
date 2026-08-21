# Dimensional — workspace

*Living doc — updated every session; every machine and cloud session reads this first. Any machine
should be able to clone this repo and start working from this file alone.*

Aaryan's working context at **Dimensional** (dimensionalOS — "the OS for robotics"). Started as the
Forward Deployed Engineer trial, full-time from 2026-08-07. Code lives in the clones under
`workspace/`, each its own git repo, gitignored here — so this repo's `CLAUDE.md` and `AGENTS.md`
govern that work too.

Tasks live in Linear, not here. Everything from the trial — the plan of record, the findings, the
robot-day runbook, the team direction ledger, the learning log — is archived verbatim in
[`temp/notes/workspace-trial-archive.md`](temp/notes/workspace-trial-archive.md).

---

## 0. Cold start — new machine

Run these in order. If this machine already has both repos cloned and `dimos` synced, skip to §2
Next actions.

1. **Clone this repo** (if not already here):
   ```bash
   git clone https://github.com/AaryanAgrawal/aaryan-dimensional.git
   cd aaryan-dimensional
   ```
2. **Clone `dimos` under `workspace/`** (run from the repo root — `workspace/` is gitignored in
   full; each repo in it is its own git repo, never tracked as content here, and nesting them is
   what makes this file and `CLAUDE.md` govern that work too):
   ```bash
   mkdir -p workspace && cd workspace
   GIT_LFS_SKIP_SMUDGE=1 git clone https://github.com/dimensionalOS/dimos.git
   cd dimos
   git remote add fork https://github.com/AaryanAgrawal/dimos
   git fetch fork
   git checkout feat/fiducial-relocalization
   ```
   `GIT_LFS_SKIP_SMUDGE=1` skips pulling every LFS asset (recordings, weights) at clone time — the
   repo is otherwise ~3GB. Pull specific LFS data on demand later: `git lfs pull --include=<path>`.
3. **Sync the environment** (from inside `dimos/`):
   ```bash
   uv sync --all-groups
   ```
4. **CUDA note:** map ops (feature matching, graph refinement, village-scale eval) benefit hugely
   from a CUDA-capable box — if this machine has one, pass `--device CUDA:0` to `dimos map global`
   commands (§6 CUDA-machine commands); if not (e.g. the dev Mac), `--device CPU:0` works, just
   slower. Confirm which this machine is before running anything compute-heavy.
5. **Robot connection crib** (only if this machine will drive the live Go2 — skip if this is the
   CUDA/offline-eval machine):
   - Robot: Unitree Go2 **"greenwald"** (`dim-0190056`). Power on via its side button, wait for it
     to finish booting and stand up on its own (~30-60s) — that's the robot ready signal.
   - It joins the office WiFi automatically; last known IP `10.0.0.104` (the physical asset tag
     printed on the robot, `192.168.10.190`, is **stale** — ignore it, DHCP has moved it since).
   - If `10.0.0.104` doesn't respond, re-sweep the office subnet for the WebRTC control port
     (9991):
     ```bash
     nmap -p 9991 --open 10.0.0.0/24   # adjust the subnet if the office network differs
     ```
   - Smoke-test the stack **without** the real robot first (replay path, always available, zero
     hardware risk):
     ```bash
     cd dimos
     uv run dimos --replay --replay-db=go2_bigoffice run unitree-go2-visual-relocalization
     ```
     Expect: 11 modules deployed, `color_image` autoconnected, zero tracebacks, zero `world->map`
     corrections (the replay recording has no tags in view — that's correct, not a bug). Foreground
     only — `--daemon` panics on this Mac after the fork (Zenoh's I/O driver doesn't survive it);
     if you see orphaned worker processes, that's why.
   - Once the smoke test is clean, connect to the real robot:
     ```bash
     ROBOT_IP=10.0.0.104 dimos run unitree-go2-visual-relocalization
     ```
6. **Read the rest of this file**, then continue from §2 Next actions.
7. **If continuing the Engineering v2 Linear migration**, read
   `linear-migration/HANDOFF.md`, then use `linear-migration/LINEAR_SNAPSHOT.json` as the
   verified 2026-08-17 baseline. The review artifact source is in
   `linear-migration/site-source/`.

## 1. Where everything lives

| What | Where |
|---|---|
| The repos being worked on | `workspace/` — `dimos` (upstream + Aaryan's fork; PR branch `feat/relocalization-fiducial-prior`) and `dios` (`dimensionalOS/dios`, with worktrees `dios-3-recipe-doctor` and `dios-technical-spec`). Gitignored in full: each is its own git repo, never tracked as content here. **Never delete the fork** (fork-and-pull is the PR channel — Aaryan confirmed Jul 17). |
| The open PRs | **#3162** fiducial relocalization prior + pre-map marker aggregation, draft — https://github.com/dimensionalOS/dimos/pull/3162. **#3161** `cameracalibrate` charuco + `--check`, draft. Superseded and closed: #3016, #3137. |
| Everything written that is not this doc | `temp/` — tracked, so it survives the machine: `temp/g1` (setup, wipe, bringup), `temp/dios` (architecture, PRD, the archive, the render script), `temp/linear` (Engineering v1 → v2 handoff + Linear snapshot; its review-site source was a Next.js scaffold, untracked again 2026-08-20 — in history at `e23cec8`, on the dev box at `workspace/temp/linear-site-source`), `temp/templates` (PRD template), `temp/notes` (design write-ups + the WORKSPACE trial archive). |
| The public presentation page | https://aaryanagrawal.me/dimensional — source in `site/` (canonical copy): `page.tsx`, `data-dimensional.ts`, `assets/`. Deploy home is github.com/AaryanAgrawal/portfolio: copy the three pieces into that checkout, `npx tsc --noEmit && next build`, `vercel --prod` (scope servicerobotco, project aaryan-portfolio). Edit here first, sync on deploy. |
| Trial material | Removed from the tree 2026-08-20. The writing behind #3162 is on the dimos branch `context/fiducial-trial` — start at `trial-context/INDEX.md`. The harness code and figures are in this repo's git history ≤ `c20f601`; the 11 GB of eval output and the `.rrd` files are on the dev box at `workspace/temp/trial`. |
| Scratch, run output, clones | `workspace/` — untracked, dev box only. |

## Aug 7–9 — dimos-helm + dimos-infect: the setup stack, two repos, nothing pushed

**STATE 2026-08-09.** A five-agent overnight built the robot setup stack. Both repos build, test
and lint clean; every commit is LOCAL ONLY, no remote, no PR, no Linear write. Nothing has met a
robot.

The architecture, decided and not to be redesigned: **helm is the package manager and knows
platforms only** (os/distro/version, arch, glibc/musl, gpu+cuda, python, ram/disk) — never robots,
never fails, always works standalone. **infect is how you set up a robot** — it runs on the
operator's laptop, reaches the robot, and carries one *recipe* per robot. The boundary test for any
ambiguous fact: does the compat engine need it to pick a wheel? Yes → helm. No → infect. Full plan
in `workspace/infect-plan.html`.

| What | Where |
|---|---|
| helm (the package manager) | `workspace/dimos-helm` — Rust, `nix develop --command cargo test` = **50 passed**. Branch stack `helm/1-unattended` … `helm/10-integration`, each one layer on the last, all rooted at `origin/main`. `fix/jetson-non-interactive` is a parallel branch under review — leave all of these alone. |
| infect (how you set up a robot) | `workspace/dimos-infect` — new local Rust repo, no remote configured. `cargo test` = **85 + 10 passed**, clippy clean, fmt clean. 3 commits on `main`, ~4.6k lines. |
| The tailscale decision | `workspace/tailscale-decision.md` — 281 lines, verified against tailscale 1.102.2 and its real source. No code. |
| What needs a human | `workspace/dimos-infect/OPEN_QUESTIONS.md` — 7 questions. Deferred work is in each repo's `todo.md`. |

**The helm stack, per layer** (`git diff --shortstat` on top of the previous):

| Branch | Files | Diff |
|---|---|---|
| `helm/1-unattended` | 3 | +30 / −6 |
| `helm/2-tegra-cuda` | 2 | +21 / −1 |
| `helm/3-detect` | 4 | +201 / −1 |
| `helm/4-use-detection` | 3 | +47 / −2 |
| `helm/5-plan` | 3 | +337 / −1 |
| `helm/6-bringup` | 6 | +228 / −1 |
| `helm/7-exit-code` | 2 | +25 / −1 |
| `helm/8-doctor-json` | 6 | +399 / −147 |
| `helm/9-universal` | 8 | +581 / −158 |
| `helm/10-integration` | 7 | +30 / −23 |

Verified linear: every branch has the previous one as an ancestor, all reachable from `origin/main`,
14 commits total. `helm/10-integration` is the integration layer added this session — it deletes a
`home_dir()` the stack had defined twice and written inline three more times.

### The contract, and the two places it did not hold

`dim doctor --json` is the machine interface between the two tools. Run for real, it prints one
line, exit 0, stderr empty, ten keys: `os os_version arch glibc gpu cuda python ram_gb disk_gb
findings`, each finding carrying `check / severity / detail / fix` with severity `info|warn|block`.

Two breaks found by running the binaries, both fixed on infect's side because **helm owns the
contract**:

- **infect emitted `dim setup --smoke-blueprint`, which does not exist.** `dim setup --help` lists
  fifteen flags and that is not one of them; clap rejects unknown flags, so every install would have
  died as a usage error at the robot. infect no longer emits it. The consequence is that **no robot
  has a smoke test** — `[helm].smoke_blueprint` is still declared per recipe and `recipe show` now
  prints it as `(declared)`. Open question 6.
- **infect took exit 0 as "healthy".** helm's doctor deliberately exits 0 even when it found a
  blocker (its own `--help` says anything wrapping dim should gate on `block`), so the verify probe
  passed machines helm had just refused. It now parses the findings and counts `severity == "block"`;
  unparseable output counts as blocked, because that means the contract moved. Proven end to end
  against a fake `dim` that exits 0 either way: the blocked report fails, the healthy one passes.

### What is real, what is stubbed, what needs hardware

**Real and executed:** helm's distro detection (ubuntu/debian/fedora/arch/nixos/wsl + musl vs
glibc), `dim doctor` and `dim doctor --json`, infect's recipe manifest, lane resolution, `extends`
merge, match engine, journal, entitlement audit, all nine verbs as plans, and the dry-run path —
which is safe *by construction*, since `Mode::DryRun` returns before anything is spawned.

**Stubbed:** the runner (nothing walks the phases yet), live probing, `recipe new|add|remove`, the
guided flow. Script steps are written but nothing executes them.

**Never met hardware, and every claim about it is a hypothesis:** every fact table is hand-written;
the dnf/pacman/apk package names were never run; musl detection was never run on Alpine; the tegra
branch of doctor is covered only by fixtures; and whether `nmcli … passwd-file` *persists* the wifi
psk across a reboot is unproven and is the one that would silently strand a robot.

## Aug 10 — dios: one repo, one binary, four branches integrated (nothing pushed)

> **Current location (2026-08-13):** the private repository is now
> `dimensionalOS/dios`, with its local checkout at `workspace/dios`. The names below record the
> historical Aug 10 state.

**STATE 2026-08-10.** `dimos-helm` is now **`workspace/dimos-bios`**, the binary is **`dios`**, and
`dimos-infect` has been merged into it with its history intact. Four overnight agents built on top
of that merge; this session integrated all of them onto **`dios/5-integration`**. Local commits
only — nothing pushed, no PR, no Linear, and all 11 `helm/*` branches are untouched.

The decisions, made and not to be relitigated: **one repo, one binary named `dios`**; the entry
point for provisioning is **`dios infect --with <recipe>`**; a **recipe** is the unit third parties
write; `src/pkg/` knows platforms and may never name a robot, `src/infect/` knows robots, and
**`tests/boundary.rs` is what enforces that** now that it is no longer two repos.

| Branch | What it added | Merged |
|---|---|---|
| `dios/1-merge` | the merge, the `dim` → `dios` rename, the two-layer reshape, `tests/boundary.rs` | base |
| `dios/2-modes` | `--agent` + exit code 2, `critical` per step, `Ask` so no stage can prompt | clean |
| `dios/3-recipe-doctor` | `dios doctor --recipe <name>\|all` — ten checks, no robot, ~4 ms | 2 conflicts |
| `dios/4-authoring` | `docs/recipes.md`, `dios recipe new`, the authoring checklist | 2 conflicts |

All four conflicts were in prose (`CHANGELOG.md`, `README.md`) or in one help-text block where two
agents had each re-aligned the same example column. Both intents kept in every case; nothing was
dropped. **192 tests green** (155 unit, 3 boundary, 2 prompts, 21 recipe doctor, 11 recipes), up
from 51 + 96 in the two separate repos.

### What the integration itself had to fix

Three things were only visible once the branches were in one tree, because each one straddles two
of them:

- **A dry run was an error.** `dios infect --with unitree-g1 --dry-run` bailed with "the runner is
  not built yet" — the one command you want before touching a robot was the one that refused. It
  now prints the ordered plan and exits 0, rendering through `recipe::cmd::print_plan`, which
  `recipe show` also calls so the two cannot drift.
- **The scaffold had never met the doctor.** `recipe new` (branch 4) and `doctor --recipe`
  (branch 3) were written in parallel. They agree: what the scaffold writes carries no blocker. It
  carries exactly one warning, "no `[helm]`: this installs nothing", which is the author's next
  step; `a_scaffolded_recipe_passes_the_doctor` pins both facts.
- **The recipe format had a field its own spec did not mention.** `critical` shipped on branch 2
  while `docs/recipes.md` was being written on branch 4. Now documented, and commented in what
  `recipe new` writes.

### Proven by running, not assumed

`dios --help`, `dios infect --with unitree-g1 --dry-run` (exit 0, full plan), `dios doctor --recipe
all` (exit 0, notes only), `dios doctor --json | python3 -m json.tool` (valid, ten keys),
`dios --dry-run infect bringup --with unitree-g1`, and dry runs of `ssh.install-key`, `wifi.join`
and `helm.deliver`.

**The boundary guard was watched failing**, in both directions: a robot reference added to
`src/pkg/plan.rs` failed with `src/pkg/plan.rs says: g1, quadruped, robot, unitree`, and a
`use crate::infect::…` in `src/pkg/detect.rs` tripped the second test too. Both reverted. A guard
nobody has seen fail is not a guard.

**`nix build .#linux-arm64` works** — a 6.8 MB static aarch64 binary, which is what the G1's Jetson
needs and what the previous session left unverified. It has not been executed on an aarch64 machine.

### The thing to check first, before anything else

`docs/TESTING_TOMORROW.md` is the ordered hardware plan, and its step 0 is one command:

```bash
timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=10 unitree@192.168.123.164 'echo hi'
```

Every robot-side op is `ssh <robot> '<command>'`. The G1 prints a `ros:foxy(1) noetic(2)` selector
at login; if that runs for a non-interactive shell it blocks on `read`, and **nothing bounds it** —
`ConnectTimeout` covers the connect and the auth and then stops applying, and a script step's
`timeout_s` is parsed and never enforced. So it is a hang, not a slow step, and it invalidates every
later step. `OPEN_QUESTIONS.md` §8 is what a person has to decide if it does hang.

### Still stubbed after the integration

The **runner** (nothing walks a recipe's phases; steps 3–5 of the testing doc are the plan driven by
hand with `dios verb run`), `dios infect scan`, `recipe add|remove`, and exit code 2 — `--agent` is
tested at the seam but no CLI path produces a real one, because no package-manager stage is declared
critical and the runner that reads `critical` does not exist.

## Aug 20 — repo cleaned to durable context only

`aaryan-dimensional` tracked 103 files across a trial that ended on Aug 7, and `WORKSPACE.md` had
grown to 2,467 lines. The root is now seven entries; everything written that is not this doc sits
under `temp/`, still tracked, so a thin root costs no history.

    aaryan-dimensional/
    ├── CLAUDE.md  AGENTS.md  README.md    how to work
    ├── WORKSPACE.md                       state, plan, history — 292 lines
    ├── learn/                             one Q/A deck per language
    ├── site/                              the /dimensional page
    ├── temp/                              g1 · dios · linear · templates · notes
    └── workspace/                         clones + scratch — gitignored in full

`workspace/` is gitignored wholesale, so every clone, agent scratch dir and run output is out of the
tracked set by construction rather than by allowlist upkeep. Nothing was deleted: heavy and generated
material moved to `workspace/temp/` on the dev box, and the tracked tree before the cut is at
`c20f601`.

Before the trial tree went, the writing behind PR #3162 — FINDINGS, both PR drafts, the prior-config
design with Aaryan's four open questions, BENCHMARK_METHOD, PROVENANCE, the verified simplify patch —
was committed verbatim to `trial-context/` on the dimos branch `context/fiducial-trial`, a sibling of
the PR branch so #3162's diff is untouched. **That branch is local only**: the push failed on
`lfs.dimensionalos.com` credentials. To back it up:

    cd workspace/dimos && git push -u origin context/fiducial-trial

## 2. Between machines — read-only clone variant

The canonical setup (this repo as root, `dimos` cloned inside it) lives in §0 Cold start. Use this variant instead when handing a
**second machine you don't want full SSH access** a read-only copy of this repo (not `dimos`) —
scope: this repo only, 30-day expiry.

1. github.com → Settings → Developer settings → Fine-grained personal access tokens → Generate
   new token.
2. Resource owner: `AaryanAgrawal`. Repository access: **Only select repositories** →
   `aaryan-dimensional`. Expiration: **30 days**. Permissions → Repository permissions →
   **Contents: Read-only** (leave everything else at No access).
3. Clone with the token as the password over HTTPS:
   ```bash
   git clone https://<PAT>@github.com/AaryanAgrawal/aaryan-dimensional.git
   ```

---

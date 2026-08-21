# dios — architecture

What dios is, what it may and may not own, and why the defaults are what they are. `README.md` says
how to use it; `todo.md` holds work an agent could do; `OPEN_QUESTIONS.md` holds what only a person
can settle. This file holds the shape.

Every claim below is tagged **[verified]** (run or read in this repo), **[measured]** (observed on
real hardware, with the date), or **[unverified]** (inferred, or read on the web and not tested).
The repo rule applies: a fresh run beats the code, the code beats the docs, the docs beat what
anyone said.

---

## 1. What dios is

One binary, two capabilities.

**Package manager** — given a machine, install DimOS correctly for its platform.
**Robot provisioner** — given a robot, identify it, reach it, install what it needs, leave it
configured to run.

Four principles, in force:

1. The package manager knows platforms; the provisioner knows robots. Neither crosses over.
2. The package manager works standalone. The provisioner is never a prerequisite.
3. Every step states what proves it succeeded. A step already proven is skipped.
4. Degrade rather than fail. An unsupported platform gets instructions, not an error.

Success criteria: a fresh robot reaches running DimOS in one command; a re-run changes nothing; a
new robot needs no change to the tool.

---

## 2. The line dios must not cross

This is the single most load-bearing fact in the design, and every other decision falls out of it.

```
   ┌───────────────────────────┐
   │  dimos + blueprints       │   ← dios installs and proves this
   ├───────────────────────────┤
   │  our payload: venv, deps  │   ← dios owns this
   ├═══════════════════════════┤   ═══ THE LINE ═══
   │  vendor OS                │   ← dios must NOT own this
   │  L4T kernel, Tegra CUDA,  │
   │  Tegra GL, master_service │
   │  _pc4, unitree_patch_pc4, │
   │  video_hub_pc4            │
   ├───────────────────────────┤
   │  Orin NX, custom carrier  │
   │  (a robot someone bought) │
   └───────────────────────────┘
```

On a Unitree G1 the Jetson runs Unitree's own services on Unitree's own L4T install **[measured
2026-08-10]**. Replace that OS and the robot stops being a robot. So dios is a tool that *adds a
layer to a machine it does not own* — not an OS, not an image, not a distro.

Everything in §6 and §7 is a consequence of this line.

---

## 3. Deployment shapes

A recipe declares which shape it is; `target` and lanes encode it **[verified]**.

```
  SHAPE 1 — the package manager runs ON the robot        recipes/g1
  laptop ──ssh──▶ robot: dios setup, dimos, blueprint runs here

  SHAPE 2 — no code on the robot at all                  recipes/go2, webrtc lane
  laptop: dimos + webrtc driver ──▶ robot's vendor firmware

  SHAPE 3 — a bridge on the robot, stack on the laptop   recipes/go2, zenoh lane
  laptop: dimos ──zenoh──▶ robot: go2web bridge only
```

Choosing the lane *is* choosing where the stack lands, which is why a recipe with lanes may omit
`target` **[verified]**.

---

## 4. MVP — the wizard flow (PRD issue #1)

The target shape for setting up a robot nobody has touched before. Interactive first; the agent path
follows the same stages, never a second code path (§9).

### Vocabulary

```
  INFECTOR   the operator's PC — runs dios, drives the setup
  INFECTEE   the robot or board being set up
```

These are today's `on = "laptop"` and `on = "robot"` in a recipe step **[verified]**. Same concept,
clearer names.

### The shape

One repo **per manufacturer** that Dimensional integrates with. Everything Rust, musl-static, no
system dependencies — the same property that let a dios binary built on x86 Ubuntu 24.04 run on the
G1's glibc 2.31 with nothing installed **[measured]**.

```
  operator PC
  ┌──────────────────────────────────────────────────────────────────────┐
  │ 1. install dios                                                      │
  │ 2. dios asks: which robot or board?          ──▶  G1                 │
  │ 3. downloads the WIZARD binary for that manufacturer                 │
  │      one repo per manufacturer · rust · musl · no deps               │
  │ 4. wizard runs in INFECTOR mode, and asks which setup:               │
  └───────────────────────────┬──────────────────────────────────────────┘
                              │
              ┌───────────────┴────────────────┐
              ▼                                ▼
        DIMOS-ONBOARD                     OFFBOARD
        dimos runs on the robot           dimos runs on the PC
        (= shape 1 today)                 (= shapes 2 and 3 today: webrtc, zenoh)
```

### The four stages

```
  (1) robot-specific setup     networking, ssh keys, cyclonedds — what only this robot needs
  (2) dios setup               vanilla dimos install
  (3) verification             prove it actually runs
  (4) dios register            MAC, IP, auth info → local targets.json
                               + commissions the Dimensional license key   [future]
```

### Onboard: the wizard crosses to the robot

```
  INFECTOR                                     INFECTEE
  ────────                                     ────────
  select robot
  download wizard
  copy dios + wizard  ──────────────────────▶  (both land on the robot)
  install dios        ──────────────────────▶  dios installed
                                               wizard runs in INFECTEE mode:
                                                 (1) robot-specific setup
                                                 (2) dios setup → dimos
                                                 (3) verification
  (4) dios register   ◀──────────────────────  returns to the infector
```

Stage 4 stays on the infector deliberately: the registry and the license are the operator's record
of the fleet, not the robot's (§14).

### Offboard: nothing is copied

```
  INFECTOR                                     INFECTEE
  ────────                                     ────────
  (1) robot-specific setup   ───────────────▶  vendor firmware only
  (2) dios setup → dimos on the PC             no dios, no dimos, no code
  (3) verification           ───────────────▶  (talks to it over webrtc / zenoh)
  (4) dios register
```

### What this is, against what exists

| Wizard concept | Today | New? |
|---|---|---|
| infector / infectee | `on = "laptop"` / `on = "robot"` | rename |
| onboard / offboard | deployment shapes 1 vs 2+3, chosen by lane | rename |
| stage (1) | `pre-helm` phase steps | exists |
| stage (2) | the `helm` phase | exists |
| stage (3) | `verify` clauses + the smoke stage | exists |
| stage (4) `dios register` | `src/infect/targets.rs` records MAC/addr/recipe; **licensing does not exist** | part new |
| wizard binary per manufacturer | recipes are **data** (TOML + bash), interpreted by dios | **decision** |
| downloading the wizard | the recipe index (§13) fetches by name, pinned + hashed | reuse |

So most of the MVP is machinery that already runs. Two things are genuinely new: **licensing in stage
4**, and **whether a robot's setup ships as a compiled binary or as data**.

### The open decision: compiled wizard, or data recipe?

Today a recipe is data — a TOML manifest plus bash steps — and the stated principle is that recipes
are "authored and shared without modifying the tool" (§10). A compiled per-manufacturer wizard
inverts that: adding a robot needs a Rust toolchain and a release, not a file.

Both can be true if the wizard is the **delivery vehicle** and the recipe stays the **payload** — a
manufacturer's binary embeds its recipes and the verbs unique to its hardware, while dios still
interprets the steps. That keeps §10's authoring story and gains the wizard's freedom to run
arbitrary logic where a bash step cannot.

Unresolved either way, and worth settling before code:

- **A downloaded binary that provisions a robot as root is a supply-chain surface.** The index
  already pins `rev` + `sha256` (§13); a wizard needs at least that and probably an Ed25519
  signature, verified against a public key baked into dios — the same mechanism licensing needs.
- **`dios install` is taken.** It already means "install a desktop package from a git repo or local
  path" **[verified]**. The robot-selection entry point needs its own verb.
- Where does a wizard live between runs, and does `dios update` update wizards too?

### Future state: three databases

```
  DIMOS CLOUD                                    OPERATOR PC
  ┌───────────────────────────────┐              ┌──────────────────────────┐
  │ targets (global)              │              │ targets (local)          │
  │  fleet · licensing · user auth│◀────sync────▶│  ~/.dimos/config.json    │
  ├───────────────────────────────┤              │  works offline, is the   │
  │ versioning / OTA              │─────poll────▶│  authority when isolated │
  │  recipe × firmware × dimos    │              └──────────────────────────┘
  └───────────────────────────────┘
```

The two cloud databases have opposite trust properties and must not be conflated: **versioning is
public data** (belongs in git, signed by tag, mirrorable — §13), **licensing is private** and lives
server-side only. The local target registry already exists **[verified]** and is what makes an
isolated robot workable at all.

---

## 5. Target matrix

| Target | Board | OS / glibc | GPU | Code on it | We may replace the OS |
|---|---|---|---|---|---|
| operator laptop | x86_64 | Ubuntu 24.04 / 2.39 | desktop CUDA | yes | ours |
| operator laptop | Apple ARM | macOS | none | yes | ours |
| operator laptop | x86_64 | NixOS | varies | yes | ours |
| **Unitree G1** | Orin NX, custom carrier `g1plus_pc4` | L4T R35.3.1 / Ubuntu 20.04 / **2.31** | Tegra CUDA 11.4, no `nvidia-smi` | yes, shape 1 | **no — vendor** |
| Unitree Go2 (webrtc) | — | vendor firmware | — | none | no |
| Unitree Go2 (zenoh) | vendor compute | vendor firmware | — | bridge only | no |
| Jetson devkit | Orin Nano / AGX | ours | JetPack | yes | ours |
| Raspberry Pi | Pi 4/5 | ours | none | yes | ours |

G1 facts are **[measured 2026-08-10]** from `facts/g1-measured.doctor.json` and a live run: 15 GB
RAM, 1756 GB disk free, `net.core.rmem_max = 67108864`, NV power mode MAXN, `/dev/video0`–`video5`
present, `python3` **not** on PATH.

---

## 6. Package layers — who owns what

Four package universes coexist on a provisioned robot. Confusing them is the most common source of
wasted time.

```
  ┌────────────────────────────────────────────────────────────────────┐
  │ VENDOR (dpkg, NVIDIA + Unitree)     kernel, Tegra CUDA, Tegra GL,  │  never ours
  │                                      master_service_pc4, ROS foxy, │
  │                                      Docker                        │
  ├────────────────────────────────────────────────────────────────────┤
  │ APT (dios installs)                  9 packages, deps.rs:586       │  ours, minimal
  │   curl  g++  git-lfs  pre-commit          ← plain tooling          │
  │   libgl1  libegl1  libturbojpeg           ← RUNTIME LINKAGE        │
  │   portaudio19-dev  python3-dev            ← RUNTIME LINKAGE        │
  ├────────────────────────────────────────────────────────────────────┤
  │ PYPI WHEELS (uv)                     torch, open3d, onnxruntime,   │  ours, and the
  │   + uv's own CPython 3.12.13         opencv-contrib, numpy 1.26.4  │  real risk
  ├────────────────────────────────────────────────────────────────────┤
  │ SOURCE BUILDS                        cyclonedds → ~/cyclonedds     │  ours
  │ NIX FLAKES                           dimos native modules          │  ours
  └────────────────────────────────────────────────────────────────────┘
```

**The apt surface is nine packages and should stay that way** **[verified]**. Note the split: four
are plain tooling whose absence is annoying; five are *runtime linkage* whose absence does not break
the install at all — it breaks the run, hours later, as a wgpu crash or an import error.

**The unpinned layer is PyPI, not apt** **[measured 2026-08-10]**. The failure that actually stopped
the robot connecting was `unitree-webrtc-connect` 2.1.2 not having an API dimos calls. No package
manager change fixes that.

---

## 7. Nix — five roles, and why apt stays

Nix appears in five distinct places. They are routinely conflated.

| # | Role | Off switch |
|---|---|---|
| ① | **Nix builds dios** — `flake.nix` cross-compiles to static musl for macos-arm / linux-x86 / linux-arm64 | dev machine only |
| ② | **dios installs Nix**, always. Two paths, two installers: `dios setup` uses the official multi-user installer (`nixos.org/nix/install --daemon`, `deps.rs:280`); `dios init` uses Determinate (`init.rs:105`) | `--no-nix` |
| ③ | **Nix as system-package source** — `nix develop` instead of apt/brew | off by default |
| ④ | **Runtime** — `nix build`, `nix run nixpkgs#deno`, and dimos building native modules | load-bearing |
| ⑤ | **NixOS as a host** — prints a `configuration.nix` snippet instead of mutating | automatic |

`deps.rs:15-17` states the rule that resolves the confusion **[verified]**: *"Nix is always installed
because DimOS native modules need it at runtime. The setup-method choice only controls whether system
packages come from apt/brew or from `nix develop`. Default is apt/brew."*

So "we chose apt" and "Nix is installed" are both true — different questions.

### The GPU boundary rule

> **Nix may own anything that does not touch the GPU. Everything that touches the GPU comes from the
> vendor, whatever installed it.**

Equivalently: **Nix can own whole processes; it cannot own half of one.** Two package trees coexist
fine on a filesystem. They collide inside a single process's link namespace — two glibcs, two
libstdc++s, two GL dispatch configs.

Consequences, in decreasing obviousness:

- `libgl1`/`libegl1` are the **glvnd dispatcher**; the implementation is NVIDIA's Tegra GL from the
  L4T BSP, selected via `/usr/share/glvnd/egl_vendor.d/`. A Nix-supplied GL silently falls back to
  software rendering **[unverified — reasoned, not tested]**, which is worse than a hard error.
- `g++` looks like safe tooling but is **not**: dios uses it to build CycloneDDS, which is loaded
  *into* uv's Python process. uv's CPython links the system glibc, so a Nix-built CycloneDDS puts a
  Nix-glibc library inside a system-glibc interpreter.
- Of nine apt packages, roughly three could safely move to Nix. That is not worth the churn.

### What we are not doing, and why

- **NixOS on the G1** — jetpack-nixos is a NixOS module requiring UEFI flashing on devkit carriers
  **[unverified — from its README]**. The G1 is a custom carrier with a vendor OS. §2 forbids it.
- **Replacing apt with Nix** — three movable packages, two actively harmful, and it would not have
  prevented any of the five failures in §10.
- **Nixifying the Python payload** — the wheels bundle prebuilt `.so`s that link vendor GL/CUDA. The
  right tool there is manylinux wheels built in a glibc-2.31 container, not Nix.
- **Ansible as a runtime** — see §11.

### Where Nix should be aimed instead

Build our artifacts hermetically and ship them; never compile on the robot. dios itself is the proof:
a Nix-cross-built static musl binary that runs on glibc 2.31 with nothing installed **[measured]**.

dimos's native modules are **already Nix flakes**, and they are the 10-minute OOM-prone step
**[measured]**. Nothing needs converting — only the *place the build happens* changes: an aarch64
builder (the G1 itself qualifies) plus a binary cache, and robots download closures instead of
compiling. That is R2, at near-zero packaging cost.

---

## 8. Requirements

Each traceable to an incident. Status as of 2026-08-11; "fixed in tree" means the fix landed but
has not run on the robot, which has been offline since.

| # | Requirement | Evidence | Status |
|---|---|---|---|
| R1 | Reach a robot with no prior network configuration | `dios infect scan` covers ethernet, usb (`usb0`/`l4tbr0`), wifi and bluetooth **[verified]**; the target registry (§13) now remembers what it found — names and fleet loops are still missing | partly held |
| R2 | Never compile on the robot | first blueprint run builds native modules 10+ min, OOMs on PCL/VTK | violated |
| R3 | The payload must not depend on host glibc or Python | glibc 2.31 static-TLS exhaustion | dios yes, dimos no |
| R4 | Coexist with a vendor OS that must not be replaced | §2 | holds |
| R5 | Prove the install by RUNNING a blueprint | smoke test skipped on headless, i.e. every robot; now the runner's own final stage, after post-helm and `[config]` | fixed in tree |
| R6 | Every artifact pinned and reproducible per (board, robot) | `go2web` has no published artifact or version pin | open |
| R7 | A re-run changes nothing | verified on hardware: wifi, git-https, cyclonedds all already-done | holds |
| R8 | Degrade rather than fail | NixOS branch prints a snippet instead of mutating | holds |
| R9 | A provisioned robot has a stable identity | wifi is DHCP; tailscale ships disabled pending a decision | blocked |
| R10 | Unattended runs never meet an interactive prompt | multicast prompt defaults to No and killed a run; the `ip link`/`ip route` half now persists as a boot oneshot (`dimos-multicast.service`) | fixed in tree |
| R11 | The provisioner writes runtime config, not the operator's memory | `robot_ip` defaulted to `None`, dialled as the string `"none"`; the g1 recipe now writes `ROBOT_IP` via `[config] env` | fixed in tree |
| R12 | A robot in a bad state is recoverable without a person on site | not exercised; today recovery means USB-C to HDMI and a keyboard | absent |

---

## 9. Execution model

**Stages.** `src/util/stage.rs` owns one decision: is this step load-bearing **[verified]**.

```
  stage::handle(name, result, criticality, ask)
        │
        ├── ok ──────────────────────────────▶ continue
        │
        └── failed
              ├── non-critical, nobody here ──▶ log it, remember it, continue
              ├── critical,   unattended  ────▶ abort            (exit 1)
              ├── critical,   agent       ────▶ escalate         (exit 2 + JSON needs_human)
              └── interactive             ────▶ repair menu
                                                 (a critical step is never offered "continue")
```

At the end of setup, any remembered failure prints `{"failed_stages":[...]}` on stderr and exits
non-zero — *"a run that skipped past failures must not claim success"* **[verified]**.

**Modes.** Interactive (a person resolves failures), Unattended (critical stops, others continue),
Agent (a critical failure escalates rather than guessing). Recipe authors mark which steps are
critical.

**Exit codes.** `0` ok · `1` failed · `2` needs a human · `130` interrupted. Only `--agent` produces
the JSON escalation block.

**Severity.** `info` / `warn` / `block`. A `block` is the only thing that stops an install, so a
false block is expensive — there is a test asserting exactly this **[verified]**.

---

## 10. Recipes

A recipe is data. It defines support for one robot: how to recognise it, reach it, and configure it.
Recipes are authored and shared without modifying the tool, and declare the permissions they need so
an operator can review one before trusting it.

| Table | Purpose |
|---|---|
| `[match.probe]` | how to recognise this robot — `ping`, `tcp-port`, `port-sweep`, `remote-file`, `remote-glob`, `ssh-banner`, `ble-name` |
| `[network]` | addresses, and the hint printed when there is no reply |
| `[entitlements]` | what this recipe will touch: capabilities, subnets, ports, write paths. The review surface. |
| `[[step]]` | phase, machine, verb or script, `verify` clause, `critical`, timeout |
| `[helm]` | mode, extras, `smoke_blueprint` |
| `[config]` | what to write to the robot so dimos runs — blueprint, transport, env |
| `[lane.<name>]` | one robot, more than one stack |
| `[notes]` | error string → cause and fix. **This is where every field failure is recorded.** |

**Verbs** are the operations a step can call — 9 today (`config.write`, `helm.deliver`,
`net.has-inet`, `net.wait-carrier`, `net.wait-reply`, `net.wired-profile`, `payload.deliver`,
`ssh.install-key`, `wifi.join`). A verb is idempotent: it checks first, applies only what is missing,
and proves the result.

**`[notes]` is a first-class deliverable, not a comment.** Every error a real run produces belongs
there with its cause and fix, per robot. That is how a recipe accumulates the knowledge that would
otherwise live in one person's head — and it is what an agent reads when troubleshooting.

---

## 11. Ideas worth taking from Ansible

`infect` is already a small domain-specific Ansible: recipes are playbooks, steps are tasks, verbs
are modules, `verify` is the idempotence contract. We are **not** adopting Ansible as a runtime — it
needs Python on both ends (the G1 has no `python3` on PATH **[measured]**), it breaks the
single-static-binary promise, it addresses only the provisioner half, and it has no equivalent of
entitlements or agent-mode escalation.

But four things it has, dios will otherwise reinvent badly. In payoff order:

1. **`--check` / `--diff`** — a dry run that reports what *would* change, per step. Done:
   `dios infect check --with <recipe>` judges every step's proof against the live machine —
   already holds / would run / done on a previous run — and applies nothing **[verified]**.
2. **Retries with a condition (`until`)** — the dpkg-lock case: `unattended-upgrades` holds the lock
   right after first boot, which is exactly when bring-up happens.
3. **Inventory** — the moment there are two G1s, "which robot" becomes first-class and an address
   hardcoded in a recipe stops working. This is also the shape of "build once, infect many".
4. **Per-step structured results** — `changed / ok / failed` per step. `failed_stages` is the
   beginning of this; agentic troubleshooting needs the rest.

Revisit adopting Ansible wholesale if the verb count passes ~15–20, or robots get provisioned in
bulk. Past that we would be maintaining a module library, and maintaining one badly is worse than
adopting one.

---

## 12. Failure catalogue — the reference bring-up

Five failures on a real G1, **[measured 2026-08-10]**, none of them a bug in dios. They are the
evidence behind §8 and they belong in `recipes/g1/recipe.toml` `[notes]`.

| Failure | Root cause | Layer |
|---|---|---|
| `cannot allocate memory in static TLS block` | glibc 2.31 has a fixed static TLS surplus; the tunable arrived in 2.32. Preload **both** `libGLdispatch.so.0` and `libgomp.so.1` — fixing one moves the error to the other | vendor OS |
| `TypeError: ... unexpected keyword argument 'aes_128_key'` | dimos calls a driver API no published `unitree-webrtc-connect` has (2.1.2 is newest). The class named is the driver's, aliased `LegionConnection` | PyPI |
| `HTTPConnectionPool(host='none', ...)` | nobody wrote the robot's address into config; `None` was stringified | provisioner (R11) |
| `wgpu error: Out of Memory` after `libEGL DRI3 failed` | a GUI opened on a headless robot | default not derived from target |
| multicast prompt on every boot | the `ip link` / `ip route` half cannot persist as a sysctl | install claimed persistence it did not have |

Unresolved: the camera. `/dev/video0`–`video5` exist and the user is in the `video` group, yet cv2
fails with `Failed to open camera 0`. The guide blames an unplugged USB-C cable; the nodes are
present, so that explanation does not fit. **Do not guess a fix.**

---

## 13. The recipe index — this version, not later

`dios recipe add <git-url>` already installs a third-party recipe **[verified]**, so a board can be
added without a PR against dios. What was missing, and lands in this version, is the index: install
by *name*, pin a *version*, and find out a newer one exists.

```
   AUTHOR                          INDEX                        OPERATOR
   ──────                          ─────                        ────────
   git repo                                                     dios recipe add unitree-g1
   ┌──────────────┐                                                        │
   │ recipe.toml  │                                                        │ 1. GET index
   │ steps/*.sh   │                                                        ▼
   │ facts/*.json │        ┌──────────────────────────────┐   ┌─────────────────────────┐
   └──────┬───────┘        │ index.json                   │──▶│ resolve name -> url@rev │
          │ tag v1.2.0     │  static file · R2 or git     │   └────────────┬────────────┘
          │                │  NO SERVER, NO ACCOUNTS      │                │ 2. clone @rev
          └───PR / form───▶│  a PR against the index,     │                ▼
                           │  never against dios          │   ┌─────────────────────────┐
                           └──────────────────────────────┘   │ verify sha256           │
                                        ▲                     │ infect_api <= ours?     │
   dios config set recipes.index <url>  │                     │ print [entitlements]    │
   ─── mirror for China, or an ─────────┘                     │ install to --recipes    │
       internal company index                                 └─────────────────────────┘
```

```json
// index.json — the whole registry is this file
{
  "index_api": 1,
  "recipes": {
    "unitree-g1": {
      "url":        "https://github.com/dimensionalOS/dios-recipes.git",
      "rev":        "a1b2c3d4",              // pinned; a tag is a hint, a rev is the contract
      "path":       "recipes/g1",
      "sha256":     "9f86d081…",             // of the recipe dir, checked after clone
      "infect_api": 1,
      "summary":    "Unitree G1 humanoid — shape 1, helm on the robot's Jetson",
      "maintainer": "dimensional"
    }
  }
}
```

```json
// ~/.dimos/recipes.json — what this machine installed, and from where
{ "installed": {
    "unitree-g1": { "rev": "a1b2c3d4", "source": "index", "at": "2026-08-11T09:20:00Z" },
    "acme-arm":   { "rev": "ff01ab99", "source": "https://git.acme.io/dios-arm.git" }
} }
```

```
dios recipe add unitree-g1        # by name, via the index, pinned to its rev
dios recipe add <git-url>         # unchanged escape hatch — no index required
dios recipe search lidar          # what the index offers
dios recipe update [<name>]       # installed revs vs index; --check reports without writing
dios config set recipes.index <url>
```

Four rules, and each one is why a piece of the shape above exists:

1. **The index is data, not a service.** A static JSON file. No server to run, no account to hold, no
   dios release to publish a recipe. Adding a board is a PR against the *index*, not against dios.
2. **A name resolves to a revision, and a hash proves it.** Tags move; revisions do not. The
   `sha256` is checked after clone, so a recipe rewritten under its tag fails loudly.
3. **Trust is `[entitlements]`, not the index.** The index says where a recipe is, never that it is
   safe. `add` prints the entitlements — capabilities, subnets, ports, write paths — and asks. Under
   `--agent`, an unknown maintainer is an escalation (exit 2), not a silent yes.
4. **`infect_api` gates the install.** A recipe declaring a newer api than this binary understands is
   refused with the version to upgrade to, rather than half-parsed.

The configurable index URL is also the **China answer** (§17): a regional mirror of one JSON file and
the git repos it points at, set once with `dios config set`, no code path of its own.

---

## 14. Target state — where a robot's identity lives

**Implemented: `src/infect/targets.rs`, the first slice.** Before it, `dios infect scan` could
*find* a robot on ethernet, usb, wifi or bluetooth **[verified]** but nothing persisted what it
found — a recipe hardcodes addresses, the journal records one run, and discovery without memory
meant every session started from zero.

**The identity is the MAC, not the address.** The address moves — wifi is DHCP, and the G1's
lease changed between sessions. The MAC did not: `94:ba:06:f6:f0:74` (wlan0) is what actually
re-found the robot when its IP was unknown **[measured]**, and it is already recorded in
`facts/g1-measured.env.txt`. The registry reuses `journal::RobotId`, so `targets.<mac>` and
`~/.dimos/infect/journal/<mac>.json` can never disagree about what a MAC looks like.

The shape, laptop-side, because the moment you need a robot's address is the moment it is not
answering. The two location rules collided — "its own targets.json" and "never a second config
writer" — and the writer rule won: the registry is the `targets` section of `~/.dimos/config.json`,
written through `src/pkg/config.rs`, which also makes `dios config get targets.<mac>.addrs.wifi`
work with no new CLI. It moves to its own file only if a fleet ever makes the parse cost real.

```
~/.dimos/config.json
{ "targets": {
    "4c:bb:47:ab:eb:a6": {                    // keyed by MAC; every field optional but the key
      "recipe":  "unitree-g1", "lane": null,  // lane written only when one was picked
      "macs":    { "wired": "4c:bb:47:ab:eb:a6", "wifi": "94:ba:06:f6:f0:74" },
      "addrs":   { "wired": "192.168.123.164", "wifi": "10.0.0.188" },
      "control": "192.168.123.161",           // what WebRTC dials, not what we ssh to
      "last_seen": "<iso8601>",
      "last_infect": { "at": "<iso8601>", "result": "ok", "journal": "<path>" }
} } }
```

Rules, all held by construction: one writer (`src/pkg/config.rs`), never a second store. An
address is a *cache*, never authority — scan tries a known address first, confirms the answering
MAC against the entry's MACs, and only a confirmed match skips the sweep; anything else falls back
to the declared probes. Every writer sets only fields it measured and deletes nothing, so an
operator's hand-edited value survives every re-run — and scan's recipe guess never displaces what
an infect run recorded.

In this slice: a successful `dios infect` files the robot (recipe, lane, address by kind of link,
`control` from `[config] env ROBOT_IP`, journal pointer); `dios infect scan` files every
recipe-claimed sighting and consults the registry before sweeping. Explicitly not in it: names and
a `dios target` CLI (`dios config` is the surface until then), fleet loops over many targets,
joining a robot's second interface automatically (`ip -o link` over ssh — today that is one
hand-written `targets.<mac>.macs.wifi` entry), recording failed infects (the journal holds those),
and reflash reset. The full plan for all of these is workspace/targets-design.md.

This is the "inventory" idea from §11, and it is what turns "build once, infect many" from a phrase
into a command.

---

## 15. Failure and recovery — there is no rollback, by design

A verb that fails is **not** undone. `src/infect/runner.rs` hands the failure to `stage::handle`
(§9) and either continues or aborts; nothing reverses what already happened **[verified]**.

That is the right call, and the reasoning should be written down so it is not relitigated: rolling
back a partially applied system change is usually *less* safe than leaving it. You cannot reliably
un-install an apt package, un-write a wifi profile, or un-build CycloneDDS, and a half-executed
rollback strands the machine in a state no proof describes.

What makes half-configured survivable instead is three properties that already hold:

1. **Proof-gated skip.** A step whose proof already holds is skipped — *"what makes a re-run on an
   already-provisioned robot cheap and safe"*. Verified on hardware: wifi, git-https and cyclonedds
   all reported already-done on a robot provisioned days earlier **[measured]**.
2. **A journal.** Every step's outcome is recorded and saved as it happens, so a re-run resumes
   rather than restarts (`StepOutcome::Resumed`).
3. **Proof beats testimony.** After a continued failure the runner re-checks the proof, because an
   operator may have fixed it by hand in the meantime — *"the proof, not anyone's word, is what
   judges a step"* **[verified]**.

**So the recovery model is: re-run, don't rewind.**

The real gap is not rollback — it is that the half-configured state is **not legible**. The journal
lives on the laptop that ran the infect, so a different engineer, or an agent, arriving at a robot
has no way to ask *what state is this machine in?* The state check half now exists: `dios infect
check` evaluates every proof against the live machine and applies nothing **[verified]** — every
proof is already a predicate, so no new mechanism was invented. §14's target state is the half
still missing: from another laptop the journal is empty, and only the proofs answer.

---

## 16. Standing assumptions

Things the design rests on that are cheap to break and cheap to check.

**The ROS login selector does not break non-interactive ssh.** The G1 prints a
`ros: foxy(1) noetic(2)` selector on login. If that were unguarded, every verb would break, because
the whole transport layer is non-interactive ssh. **Checked, and it is fine**: `ssh unitree@… 'echo
hi'` returns `hi` and exit 0 **[measured 2026-08-10]**, recorded as
`login_selector_hangs_noninteractive=no` in `facts/g1-measured.env.txt`.

Note the risk is subtler than hanging — it is **stdout pollution**. A selector that printed on a
non-interactive login would not block anything; it would silently prepend text to the output of every
verb that captures stdout, and proofs comparing exact output would fail for reasons no error message
would explain. The measurement above rules that out (the reply was `hi`, not `hi` preceded by a
menu), but it is a per-unit fact: a differently configured robot could differ, and this assumption
should be asserted once at the start of a run rather than assumed.

---

## 17. Open questions

Blocking, and only a person can settle them — detail in `OPEN_QUESTIONS.md`:

- **Which tailnet owns the robots?** Until answered, no robot gets a stable identity (R9).
- **How is `go2web` built and pinned?** Blocks shape 3 entirely (R6).

Cheap experiments that would each decide a direction:

- **Does the G1's USB-C do device mode?** If a Jetson presents a fixed network at `192.168.55.1`,
  R1 and R12 both become easy and bring-up stops depending on wifi. Depends on how the custom carrier
  wires the port **[unverified]**. Half an hour with a cable.
- **Can Nix build the perception stack for L4T R35 aarch64?** Decides whether §7's "aim Nix at the
  build" extends to CUDA-linked Python or stops at our own code.
- **Are dimos's Nix-built native modules separate processes or `.so`s loaded into Python?** Decides
  whether closure-copy scales safely under the boundary rule in §7.

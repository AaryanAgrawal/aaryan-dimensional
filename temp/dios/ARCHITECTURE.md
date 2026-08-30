# DimOS Installer — Architecture

**PRD:** [DimOS Installer](DIOS-PRD.md)

**Status:** Draft v2, 2026-08-30. Replaces the v1 spec and `dimensionalOS/dios` issue #1.

The v1 spec described a private coordinator with a target registry, an SSH executor, a source
resolver, and one open-source wizard repository per manufacturer. None of it is built. What is
built is a working Rust installer in a private repository and a bash installer in the DimOS
repository. This document is about moving the first into the DimOS repository and deleting the
second.

## What exists today

```text
dimensionalOS/dimos                      dimensionalOS/dios          private
  scripts/install.sh   1000 lines bash     src/            Rust, v0.3.97, 20+ commits
  pyproject.toml       21 extras           install.sh      curl bootstrap to an R2 bucket
  dimos                Python CLI          dim             static musl binary
  docs/quickstart.mdx  points at the sh    templates/      desktop apps
```

`dim` already does platform detection, system packages, the Python environment, DimOS install in
library or dev mode, sysctl and LCM tuning, Unitree setup, CUDA and ROS checks, systemd services, a
JSONL action log, self-update with rollback, and `--dry-run`, `--verbose`, and `--non-interactive`
on every command. The bash script does a subset of the same work, differently, and the docs point
at it.

## Base flow

```text
curl -fsSL https://dimensionalos.com/install.sh | bash
   │  detect os and arch
   │  download dimos-<target>
   │  verify checksum
   ▼
dimos setup
   │  system packages      apt, brew, or nix, from platforms.toml
   │  python environment   uv, pinned
   │  dimos                pinned release, or a git clone in dev mode
   │  machine config       sysctl, LCM buffers, multicast loopback
   │  robot setup          only when a robot was selected
   ▼
verify: import, LCM round trip, smoke run
```

The bootstrap script stops at running the binary. Anything that needs a platform table, a version
pin, or a rollback is Rust, and the PRD's 120-line limit on `install.sh` is what keeps that true.

Checksum verification is new. Today the bootstrapper downloads over TLS and runs the binary without
verifying it, which makes an unverified binary the first thing to execute on a fresh machine.

## Alternatives considered

| Approach | Tradeoff |
|---|---|
| **Installer inside the DimOS repository** (recommended) | One repository, one review, and the installer ships on the tag of the DimOS it installs. Costs a Rust toolchain in DimOS CI. |
| Keep `dios` separate and private, as v1 proposed | Keeps the installer insulated from DimOS churn, but every dependency change needs a matching change in a second repository, which is the drift we have now. Paul raised this and it is the strongest objection to v1. |
| One wizard repository per manufacturer, as v1 proposed | A clean boundary on paper. It needs a release pipeline, a version contract, and a permissions model per manufacturer before it installs anything, and no manufacturer wizard exists yet. |
| Bash instead of Rust | Inspectable, which is Paul's argument. It cannot give a single artifact that runs before Python exists on an unknown glibc, which is the Jetson case. Recorded as a real disagreement in the dispositions. |

Jeff suggested a compiled standalone wizard per platform. One binary with per-platform setup paths
gets the same result without a release pipeline per robot, so that is the recommendation until a
vendor path cannot be linked in.

## Target layout

```text
dimensionalOS/dimos
├── installer/                 Rust crate, binary `dimos`
│   ├── Cargo.toml
│   ├── platforms.toml         system packages and sysctl, keyed by extra
│   └── src/
│       ├── main.rs
│       ├── cli.rs
│       ├── forward.rs         unknown subcommand to the Python CLI
│       ├── setup/             deps, install, sysconfig, verify, per-robot
│       ├── doctor.rs
│       ├── update.rs
│       └── service.rs
├── scripts/install.sh         bootstrapper, 120 lines or fewer
└── pyproject.toml             unchanged
```

The crate carries its own `Cargo.toml` rather than joining `native/rust/`, whose members link
against the runtime. The installer links against nothing.

### Build targets

| Target | Triple |
|---|---|
| Linux x86_64 | `x86_64-unknown-linux-musl` |
| Linux aarch64, Jetson and G1 | `aarch64-unknown-linux-musl` |
| macOS arm64 | `aarch64-apple-darwin` |

## Where dependencies come from

Two kinds, two sources, and no new file format.

**Python packages** come from `[project.optional-dependencies]` in `pyproject.toml`, which already
declares `unitree`, `cuda`, `sim`, `mapping`, `perception`, `manipulation`, `dds`, `webrtc`,
`apriltag`, and 12 more. `dimos setup --extras unitree,cuda` selects them by name. This is the
standard Jeff pointed at, it is already how the repository works, and it means adding a dependency
to a module is a `pyproject.toml` edit.

**System packages** are the one thing PEP 621 cannot express, so they get one table keyed by the
same extra names:

```toml
[extras.unitree]
apt  = ["libeigen3-dev"]
brew = ["eigen"]
nix  = ["eigen"]

[extras.unitree.sysctl]
net.core.rmem_max = 67108864          # 64 MiB; Linux default is 208 KiB
```

Every value carries the measurement that set it on the same line. The 64 MiB above is what the
current setup already applies, and whoever moves it in owns recording which drop it was tuned
against.

The v1 proposal of an `info.yaml` per module is dropped, because it restated in YAML what
`pyproject.toml` already says. This closes DIM-1426.

`src/generated_platform_reqs.json` in `dios` is a wheel-availability matrix derived from
`pyproject.toml`. It carries a `_pyproject_hash` and was generated on 2026-03-09, so it is already
stale against the current `pyproject.toml`. Regenerate it in CI and fail the build when the hash
drifts.

## The command name

`dimos` is both the Python console script and the new binary, so resolve it rather than leaving it
to PATH order.

```text
~/.local/bin/dimos                    Rust front door
  setup doctor update service           handled here
  everything else                       exec the Python CLI in the managed environment

<venv>/bin/dimos                      Python console script
  setup doctor update service           exec the binary
  everything else                       handled here, as today
```

The Python CLI defines no `setup`, `doctor`, `update`, or `service` command today, so the forwarder
adds names and shadows nothing. It is the only change on the Python side.

**Invariant:** `dimos <verb>` does the same thing whichever one PATH resolves, asserted by a test
for every verb in both directions. Without it a developer inside an activated virtualenv types
`dimos setup` and gets a typer "no such command" error.

## Where setup runs

```text
Onboard, G1     workstation ──ssh──▶ G1              DimOS runs on the robot
Offboard, Go2   workstation                          DimOS runs on the workstation
                            ──ble, lan, webrtc──▶ Go2   and talks to the robot
```

Scanning is install-time only. The installer finds the robot on USB, Ethernet, or Wi-Fi, confirms
what it is, gets an address, and installs. It keeps no registry, does not resolve a robot by name
later, and does not follow it when the address changes, because Ivan is building that as Zenoh
autodiscovery and machine tags.

`G1_SETUP_GUIDE.md` and the per-robot Markdown files are the specification for what these paths
must do, and each one that lands deletes a document.

## Failure handling

Already implemented in `setup/mod.rs::handle_stage` and kept as is:

```rust
match result {
    Ok(()) => Ok(()),
    Err(e) if critical => Err(e),                    // stop, nothing half-applied
    Err(e) if non_interactive => { log(e); Ok(()) }  // record and carry on
    Err(e) => prompt(e),                             // continue | fix in a shell | help
}
```

A missing terminal is treated as non-interactive, and `--agent-instructions` prints the steps
instead of prompting.

## Local state

Local JSON only, in `~/.dimos/config.json` and a JSONL action log:

- installed DimOS version and selected extras;
- installer version;
- robot model and observed address, when one was set up;
- last result and time.

Addresses are observations, not identity. No secret reaches local state or the log.

## Release

The installer ships on the DimOS tag because it lives in the DimOS repository.

```text
tag v0.4.0 ──▶ CI builds 3 targets ──▶ checksums ──▶ CDN
                                          └──▶ install.sh resolves latest or DIMOS_VERSION
```

`dimos update` downloads, verifies, swaps atomically, and restores the previous binary when the new
one fails to run.

## Staged rollout

Ordered so there is always a working installer.

1. Move the crate to `dimos/installer/` and rename the binary to `dimos`, with no behaviour change.
2. Build and publish all three targets on the DimOS tag.
3. Rewrite `scripts/install.sh` as the bootstrapper, add checksum verification, and point
   `docs/quickstart.mdx` at it.
4. Resolve the command name and land the both-directions test.
5. Move system packages out of code into `platforms.toml`, and regenerate the wheel matrix in CI
   with a hash check.
6. Delete the bash installer's package-manager logic.
7. Fold `G1_SETUP_GUIDE.md` into the G1 setup path and delete the guide.
8. Stand up the nightly CI matrix behind the PRD's success metrics.

Steps 1 to 3 are the move. Steps 4 to 8 are what makes it worth doing.

The desktop, the app store, and `templates/` stay in `dios`. They are not installer work and they
need a home before that repository can be archived.

## Decisions to approve

1. The installer moves into the DimOS repository and is Apache-2.0.
2. The binary becomes the `dimos` front door, rather than staying `dim`.
3. Per-module `info.yaml` is dropped in favour of `pyproject.toml` extras plus one system-package
   table.
4. Robot identity and reconnection belong to Zenoh autodiscovery, not the installer.

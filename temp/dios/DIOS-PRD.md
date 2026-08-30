# DimOS Installer — Product Requirements

**Status:** Draft v2, 2026-08-30. Replaces the 2026-08-20 draft.

Paul and Ivan both rejected the BIOS name, so the product is the DimOS installer and the command is
`dimos`. `DIOS` survives as this file's name until the move lands. Review dispositions for every
comment on v1 are in [review-dispositions.md](review-dispositions.md).

## 1. Problem

There are two DimOS installers, in two repositories, and neither one is the answer.

| Installer | Where | What works | Gap |
|---|---|---|---|
| `scripts/install.sh` | `dimos`, 1000 lines of bash | The documented quickstart, public and versioned with DimOS | Fragile across platforms |
| `dim` | `dios`, Rust, v0.3.97 | Static binary, curl bootstrap, self-update with rollback, systemd services, Unitree and Jetson paths, months of FDE use | Private, and ships from a different repository than the DimOS it installs |

The bash script is the one users find and the Rust binary is the one that works, so every platform
fix is either made twice or silently missing from one of them.

Robot bring-up is worse than workstation setup because that knowledge lives in `G1_SETUP_GUIDE.md`,
in per-robot Markdown files, and in people's heads.

### Why now

FDEs are integrating new platforms quickly and adoption is the priority. The Rust installer already
works on real robots, so the remaining problem is that it lives in the wrong repository.

### Existing alternatives

| Alternative | What works | Remaining gap |
|---|---|---|
| Manual setup guides | Flexible and available today | Manual, slow, and drift over time |
| `scripts/install.sh` | Installs DimOS on known machines | Fragile, inconsistent across platforms, not reliably versioned |
| `dim` in a separate repository | Installs and verifies DimOS today | Drifts from the DimOS it installs |

## 2. Solution

One installer, in the DimOS repository, written in Rust.

**Install DimOS on a workstation or a robot in one command.**

```text
curl -fsSL https://dimensionalos.com/install.sh | bash
dimos setup
```

The bootstrap script detects the platform, downloads one static binary, and runs it. Everything
else is Rust in the DimOS repository, released on the same tag as the DimOS it installs.

The installer is compiled and statically linked because it runs before anything is installed, on a
machine whose libc it cannot assume. It is Apache-2.0 like the rest of the repository. A broken
DimOS install cannot break the installer, because a static binary shares nothing with it at
runtime.

### What a user does

```text
dimos setup      install DimOS on this machine, or on a robot reachable from it
dimos doctor     report machine state, read-only
dimos update     self-update, and roll back if the new binary fails
dimos service    run a blueprint as a systemd service
```

Any other subcommand is handled by DimOS itself. `dimos setup` works before DimOS exists and
`dimos run` works after it, so there is one command name to learn.

`setup` is safe to re-run and skips work it can prove is already done. `doctor`, `--dry-run`, and
`--agent-instructions` change nothing.

### Three ways it runs

- **Interactive.** A failed non-critical step offers continue, drop to a shell and fix it, or show
  help links.
- **Unattended.** Critical failures stop the run and the rest are logged and skipped.
- **Agent.** With no terminal attached, the installer prints the steps instead of prompting, so a
  coding agent can follow them on a platform we do not support.

### Non-goals

- Cloud databases, dashboards, telemetry, and OTA orchestration. State stays in local JSON.
- Accounts, organizations, licensing, and cross-workstation sync.
- Tailscale.
- Replacing a manufacturer's operating system.
- Resolving a robot by name at runtime, and following it when its address changes. Ivan is building
  that now as Zenoh autodiscovery and machine tags.
- The desktop and app store that ship in the `dios` repository today. They are not installer work
  and they need their own PRD before that repository can be archived.

## 3. Usage scenarios

### Install DimOS on a workstation

- **Trigger:** a developer wants a local DimOS environment.
- **Path:** run the curl command, choose capabilities, review the plan, and pass verification.
- **Hard case:** an unsupported capability is explained before the machine is changed.

### Prepare a new robot

- **Trigger:** an FDE opens a boxed G1.
- **Path:** the installer finds the robot on the local network, confirms what it is, installs DimOS
  on it, and proves it by running a headless blueprint.
- **Hard case:** an interrupted run resumes and repeats no completed work.

### Install where we have no support

- **Trigger:** an external user or a coding agent runs setup on an untested distribution.
- **Path:** the installer prints the steps it would take and exits without changing the machine.
- **Hard case:** a system package is never installed without asking.

### Update DimOS

- **Trigger:** a user wants a newer DimOS.
- **Path:** the installer shows what will change, applies only that, and verifies the result.
- **Hard case:** if the new binary does not run, the previous one is restored.

## 4. Product requirements

| ID | Requirement | Priority | Proof |
|---|---|---|---|
| R1 | Install and verify DimOS on a supported workstation from one command | Must | Nightly CI matrix |
| R2 | Install and verify DimOS on a supported robot, ending in a running headless blueprint | Must | G1 bring-up |
| R3 | Ship the installer from the DimOS repository, on the DimOS tag | Must | Release job |
| R4 | Delete `scripts/install.sh` as an installer and keep it as a bootstrapper | Must | Line count and content check |
| R5 | Re-running setup applies no changes | Must | Second run's action log |
| R6 | Show the target, permissions, package choices, and planned changes before applying them | Must | Interactive acceptance test |
| R7 | Never install a system package without consent | Must | Interactive acceptance test |
| R8 | On an unsupported platform, print the steps and change nothing | Must | Container test on an unknown distribution |
| R9 | With no terminal attached, print steps rather than prompt | Must | Non-interactive test |
| R10 | Verify the downloaded binary before running it | Must | Checksum test |
| R11 | Restore the previous binary when an update fails | Must | Fault-injection test |
| R12 | Record DimOS version, selected capabilities, and last result locally | Must | Offline inspection |
| R13 | Keep credentials out of local state, logs, and process arguments | Must | Security review |
| R14 | Adding a dependency to a module is a `pyproject.toml` edit and nothing else | Must | Add one extra and install it |

## 5. Success metrics

Every target is a number a test produces.

| Outcome | Target | How measured |
|---|---|---|
| Fresh-machine setup | 4 of 4 platforms green on at least 95% of nightly runs over 30 days | Nightly CI on Ubuntu 22.04 x86_64, Ubuntu 22.04 aarch64, macOS 14 arm64, Jetson Orin JetPack 6.2 |
| Time to first `dimos run` | Median 10 min or less on a fresh Ubuntu x86_64 workstation | CI wall-clock, recorded per run |
| Repeatability | A second `dimos setup --non-interactive` applies zero changes | Run 2's action log contains no `applied` entry |
| G1 bring-up | 30 min or less from boxed robot to `dimos run` on the robot, with no step outside the tool | FDE records wall-clock and any manual step on the bring-up issue |
| Unsupported platform | Exits non-zero, prints steps, leaves no partial install | Container test diffs the filesystem |
| Update safety | A corrupted download leaves the previous binary working | Fault-injection test |
| One installer | `scripts/install.sh` is 120 lines or fewer and calls no package manager | Grep in CI |

"One command" is the customer message. The engineering target is the supported matrix above, and a
guided path everywhere else.

### Launch guardrails

- No password or private key reaches local state or logs.
- A missing or incompatible requirement is explained before anything irreversible happens.
- Setup works with no cloud service.

## 6. Decisions needed

1. **The `dimos` name is already the Python console script.** The recommendation is that the binary
   becomes the front door and hands unknown subcommands to the Python CLI. The alternative is to
   keep the binary named `dim` and live with two command names.
2. **What happens to the `dios` repository.** The installer moves out and the desktop and app store
   have nowhere else to go. The recommendation is to keep `dios` private for the desktop and move
   only the installer.
3. **`dim` on existing machines.** FDEs have it on PATH from months of testing. The recommendation
   is that `dim update` installs `dimos` and leaves `dim` as a symlink for one release.

---

**Technical implementation:** [DIOS Architecture](ARCHITECTURE.md)

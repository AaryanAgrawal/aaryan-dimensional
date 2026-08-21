# DIOS — Product Requirements

**Status:** Draft, 2026-08-20

## 1. Problem

Installing DimOS and preparing a robot currently depends on fragile scripts, one-off .md
guides, remembered IP addresses, pkg/system dependency troubleshooting, and manufacturer-specific knowledge. Current system has no versioning and weak verification.

### Why now?

FDEs are integrating new platforms quickly. Each integration is creating scripts and guides with no canonical location and no dependable way to keep instructions and versions aligned across machines.

FDEs have already been testing a one-command curl installer as a better way to get DimOS running.
This release turns that into a fuller product with guided setup, better pkg resolve,
version awareness, platform-specific wizard repositories, local target memory, and end-to-end
verification.

### Existing alternatives

| Alternative | What works | Remaining gap |
|---|---|---|
| Manual setup guides | Flexible and available today | Manual, slow and drift over time |
| Existing massive install.sh | Can install DimOS on known machines | Fragile, inconsistent across platforms, and not reliably versioned |

## 2. Solution

### Customer messaging

**Install DimOS on your workstation or robot in one click.**

DIOS is the DimOS BIOS that guides and verifies setup on the current machine or a robot.

### What we are building

DIOS is the private, platform-neutral entry point for two guided experiences:

```text
PSEUDO-COMMANDS — SUBJECT TO CHANGE

install DIOS
set up DimOS on this machine
prepare a Unitree robot
```

The first experience installs DIOS and starts the guided path. DIOS downloads a pinned release of
the open-source `dimos-setup-wizard`, whose code owns the complete setup and its checks. The wizard
installs an unchanged DimOS release on a supported workstation or robot computer. The user can
choose library or development setup and optional capabilities such as simulation.

The robot preparation experience launches an open-source manufacturer wizard, such as
`unitree-setup-wizard`. It discovers supported robots reachable over USB, Bluetooth, Wi-Fi, or
Ethernet; helps the operator select one; and prepares manufacturer-specific access and dependencies.
DIOS then chains it with `dimos-setup-wizard` and starts the intended headless blueprint as the final
proof. Each manufacturer owns its complete wizard in a separate repository.

The repository boundary is deliberate:

| Repository | Responsibility |
|---|---|
| `dimos` | The existing open-source software being installed. DIOS requires no changes to it. |
| `dios` | The private, platform-neutral orchestrator: resolve, run wizards, verify, Doctor, and the local target registry. It contains no platform-specific setup. |
| `dimos-setup-wizard` | An open-source repository whose code contains the complete DimOS setup and checks. |
| `<manufacturer>-setup-wizard` | One open-source repository per manufacturer whose code contains discovery, access, setup, and checks specific to its robots. |

### Deferred

- One dependency YAML, or `info.yaml` per DimOS module. Both require schema enforcement in `dimos`.
  Wizards as code keep the MVP smaller; metadata can come later.

When a robot is saved, DIOS assigns a unique friendly name such as `oswald-go2` or `mikey-g1`. The
operator can list, inspect, and rename it later. DIOS recognizes the same robot after its address
changes instead of creating a duplicate.

**DIOS Doctor** helps a human or an agent find where the problem is.

### Non-goals

- Cloud databases or fleet dashboards
- Accounts, organizations, licensing, or cross-workstation synchronization
- Remote telemetry or delivering OTA update orchestration in this release
- Replacing a manufacturer's operating system
- Defining internal package formats, APIs, storage, or cloud architecture in this PRD

## 3. Usage scenarios

### Install DimOS on a workstation

- **Trigger:** A developer wants a local DimOS environment.
- **Expected path:** Install DIOS, start setup, choose capabilities, review the plan, and pass
  verification through `dimos-setup-wizard`.
- **Hard case:** An unsupported capability is explained before the machine is changed.

### Prepare a new robot

- **Trigger:** An operator starts the Unitree preparation experience near a new robot.
- **Expected path:** A manufacturer wizard discovers and prepares the robot, the DimOS wizard
  installs DimOS, DIOS verifies a headless blueprint, and the target is saved under a unique
  friendly name.
- **Hard case:** An interrupted run resumes completed work safely.

### Return to a known robot

- **Trigger:** A previously prepared robot reboots or receives a different address.
- **Expected path:** DIOS recognizes the same identity and updates its known address.
- **Hard case:** DIOS Doctor identifies whether the problem belongs to DIOS, the manufacturer
  wizard, or the DimOS wizard and gives a human or agent the next action.

### Update DimOS

- **Trigger:** A user chooses a newer DimOS release on a workstation or robot computer.
- **Expected path:** DIOS loads the selected version from `dimos-setup-wizard`, compares its complete
  requirements with the machine, shows the update plan, installs only what changed, updates DimOS,
  and verifies that the selected capabilities still run.
- **Hard case:** If a required package or version cannot be installed safely, DIOS explains the
  conflict before changing DimOS and leaves the existing installation usable.

## 4. Product requirements

| ID | Requirement | Priority | Proof |
|---|---|---|---|
| R1 | Install and verify an unchanged DimOS release on a supported workstation through `dimos-setup-wizard` | Must | First-time workstation test |
| R2 | Chain a manufacturer wizard with `dimos-setup-wizard` on a supported robot computer | Must | Clean target installation |
| R3 | Manufacturer wizards scan their supported USB, Bluetooth, Wi-Fi, and Ethernet paths and present likely targets for confirmation | Must | Discovery test over each supported connection type |
| R4 | Keep DIOS private and platform-neutral; keep all setup and platform-specific behavior in open-source wizard repositories | Must | Repository boundary review |
| R5 | Show the target, permissions, package choices, and planned changes before setup | Must | Interactive acceptance test |
| R6 | Resume safely and skip work already proven complete | Must | Interrupted run and immediate re-run |
| R7 | Declare a robot ready only after its intended headless blueprint runs | Must | Bounded blueprint proof |
| R8 | Assign a unique `<friendly-word>-<model>` target name and allow rename | Should | Multiple-target naming test |
| R9 | Recognize a saved target after reboot or address change | Must | Reboot and address-change test |
| R10 | Record the DimOS version, every wizard and version used, target identity, and last result locally | Must | Offline target inspection |
| R11 | Keep credentials out of target history, logs, and process arguments | Must | Security review |
| R12 | DIOS Doctor helps a human or agent find where the problem is | Must | Layered diagnostic test |
| R13 | In agent mode, return structured failures instead of prompting or guessing | Should | Non-interactive test |
| R14 | A pinned `dimos-setup-wizard` release contains all setup code and checks without adding DIOS metadata to `dimos` | Must | Install two reviewed install sets |
| R15 | Before updating DimOS, load an exact reviewed DIOS, DimOS, and wizard install set, show the plan, apply only required changes, and verify the updated installation | Must | Upgrade test between two supported DimOS releases |

## 5. Success metrics

| Outcome | Target | How measured |
|---|---|---|
| First-time workstation setup | Completes through one documented entry point | Clean supported workstation |
| Clean robot setup | Reaches a running headless blueprint without undocumented steps | Clean supported Unitree robot |
| Safe repeatability | Immediate second run makes no unnecessary changes | Compare consecutive run results |
| Stable target identity | Same target is recognized after reboot and address change | Reboot and rediscovery test |
| Platform separation | A new DimOS version or manufacturer adds no platform-specific code to DIOS and requires no DIOS-specific change to `dimos` | Repository boundary review |

### Launch guardrails

- No password or private key is stored in local target history or logs.
- A missing or incompatible requirement is explained before irreversible work begins.
- Setup remains useful without cloud services.

---

**Technical implementation:** [DIOS Architecture](https://github.com/dimensionalOS/dios/blob/main/ARCHITECTURE.md)

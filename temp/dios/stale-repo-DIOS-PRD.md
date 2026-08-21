# Archived stale repository copy — do not edit

The canonical PRD is `/home/dimos/aaryan-dimensional/dios/DIOS-PRD.md` and the reviewed copy is in
Linear. This file is retained only to preserve prior hand edits.

repo# DIOS — Product Requirements

## 1. Problem

Installing DimOS and preparing a 'target' (robot/board) currently depends on fragile scripts, one-off .md
guides, remembered IP addresses, pkg/system dependency troubleshooting, and manufacturer-specific knowledge. Current system has no versioning and weak verification.

### Why now?

FDEs are integrating new platforms quickly. Each integration is creating scripts and guides with no canonical location and no dependable way to keep instructions and versions aligned across machines.

FDEs have already been testing a one-command curl installer as a better way to get DimOS running.
This release turns that into a fuller product with guided setup, better pkg resolve,
version awareness, per-manufacture repo separation, local target memory, and end-to-end verification.

### Existing alternatives

| Alternative | What works | Remaining gap |
|---|---|---|
| Manual setup guides | Flexible and available today | Manual, slow and drift over time |
| Existing massive install.sh | Can install DimOS on known machines | Fragile, inconsistent across platforms, and not reliably versioned |

## 2. Solution

### Customer messaging

**Install DimOS on your workstation or on a station, in one-click.**

DIOS is the DimOS BIOS that installs and verifies DimOS on the current machine, or on any robot.

### What we are building

DIOS has two equally important experiences:

```text
PSEUDO-COMMANDS

install DIOS
DIOS setup
DIOS seed unitree-g1
```

The first experience installs DIOS and starts the guided path. Local setup installs DimOS on
whichever supported machine runs it, including a workstation or robot computer. The user can choose
library or development setup and optional capabilities such as simulation.

The target (robot/board) preparation experience asks for what model of robot/board the user is bringing up and open specific wizard. It discovers available targets,
including supported targets reachable over USB, Bluetooth, Wi-Fi, or Ethernet. It helps the operator
select one, prepares access, runs the standard setup on the target, and starts the intended headless
blueprint and other verifcation checks.

When a target is saved, DIOS saves details about the target (MAC, IP etc.) and asks for name or assigns a unique friendly name such as `oswald-go2` or `mikey-g1`. The operator can list, inspect, and rename it later.

A read-only check command reports what is ready, missing, or would change. It doesn't installs or modifies
anything.

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
  verification.
- **Hard case:** An unsupported capability is explained before the machine is changed.

### Prepare a new robot

- **Trigger:** An operator starts the Unitree wizard near a new robot.
- **Expected path:** Discover, select, prepare, install, verify a headless blueprint, and save the
  target.
- **Hard case:** An interrupted run resumes completed work safely.

### Return to a known robot

- **Trigger:** A previously prepared robot reboots or receives a different address.
- **Expected path:** DIOS recognizes the same identity and updates its known address in target list.
- **Hard case:** A read-only check explains any missing requirement without changing the target.

## 4. Product requirements

| ID | Requirement | Priority | Proof |
|---|---|---|---|
| R1 | Install and verify DimOS on a supported workstation through one guided setup | Must | First-time workstation test |
| R2 | Use the same setup experience on a supported robot computer | Must | Clean target installation |
| R3 | Scan USB, Bluetooth, Wi-Fi, and Ethernet for supported targets and present likely matches for confirmation | Must | Discovery test over each supported connection type |
| R4 | Keep manufacturer behavior in separate manufacturer-owned repositories | Must | Unitree wizard ships without Unitree behavior in DIOS core |
| R5 | Show the target, permissions, package choices, and planned changes before setup | Must | Interactive acceptance test |
| R6 | Resume safely and skip work already proven complete | Must | Interrupted run and immediate re-run |
| R7 | Declare a robot ready only after its intended headless blueprint runs | Must | Bounded blueprint proof |
| R8 | Assign a unique `<friendly-word>-<model>` target name and allow rename | Should | Multiple-target naming test |
| R9 | Recognize a saved target after reboot or address change | Must | Reboot and address-change test |
| R10 | Keep target identity, versions, and last result available locally | Must | Offline target inspection |
| R11 | Keep credentials out of target history, logs, and process arguments | Must | Security review |
| R12 | Make checks read-only | Must | Read-only behavior test |
| R13 | In agent mode, return structured failures instead of prompting or guessing | Should | Non-interactive test |
| R14 | Each DimOS module declares its required system packages in versioned module metadata so a DimOS release can resolve the complete dependency set needed for reliable future OTA updates | Must | Release dependency aggregation test across the selected modules |

## 5. Success metrics

| Outcome | Target | How measured |
|---|---|---|
| First-time workstation setup | Completes through one documented entry point | Clean supported workstation |
| Clean robot setup | Reaches a running headless blueprint without undocumented steps | Clean supported Unitree robot |
| Safe repeatability | Immediate second run makes no unnecessary changes | Compare consecutive run results |
| Stable target identity | Same target is recognized after reboot and address change | Reboot and rediscovery test |
| Manufacturer separation | New manufacturer adds no manufacturer behavior to DIOS core | Repository boundary review |

### Launch guardrails

- No password or private key is stored in local target history or logs.
- A missing or incompatible requirement is explained before irreversible work begins.
- Setup remains useful without cloud services.

---

**Technical implementation:** [DIOS Package Dependency Architecture](package-dependency-architecture.md)

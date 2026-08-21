# PM trial

## Terms

- **DimOS** — the software platform that runs robot applications.
- **dios** — the tool that installs DimOS and prepares robots to run it.
- **Workstation** — the operator's laptop or desktop where dios runs.
- **Target** — the robot or computer dios is preparing.
- **Seed** — the dios workflow that discovers, identifies, and configures a target.
- **Wizard** — the per-robot instructions describing how dios recognises, reaches, and configures
  one type of target.
- **Workspace** — the personal or organisational home that owns robots, members, and licenses.
- **Release artifact** — a versioned downloadable binary, wizard, or software package.

`dios` installs DimOS and configures a robot. Its PRD is included below. This trial covers the
product layer around dios: accounts, robot records, licensing, versions, releases, and updates.

Do not redesign the dios installer or wizard engine; use the existing PRD below as context. Assume
the system described below exists and works, including installation, wizards, package dependencies,
target discovery, and seeding.

Every developer should have a Dimensional account with a personal workspace, so an individual can
use dios without creating a fake organisation. A person may also join one or more organisation
workspaces. Robots and licenses belong to a workspace: personal for an independent developer, or
organisational for a team. Organisation administrators manage members and licenses, and ownership
can be transferred without losing the robot's history.

Robots need to be registered when they are seeded and found again later even when their network
address changes. The registration experience, identity model, retained data, storage boundaries,
ownership rules, and reconciliation model need to be defined.

Robots are frequently offline. The system needs defined offline behaviour, including what remains
available, where that information lives, and what happens when connectivity returns.

We need to define what is licensed, whether licenses belong to users, workspaces, or robots, and how
they are verified. The design should address offline use, expiry, revocation, transfers, and the
safety implications of enforcing a license on a physical robot.

Every dios, DimOS, firmware, and wizard version must be recorded. Installs should be pinnable and
reproducible. Before an install or update, the system should check that the whole combination is
compatible and explain any refusal.

Release artifacts need versions, checksums or signatures, compatibility metadata, and release notes.
dios should report compatible updates, but the operator chooses when to apply them. Nothing silently
updates a robot.

The system must support regional artifact mirrors, including China. It must also retain an audit
trail showing who seeded each robot, which versions and license were used, and what later changed.

## Deliverables

Produce two documents:

1. A **PRD** defining the users, problems, first useful release, delivery order, and measurable
   success criteria.
2. A **technical architecture document** defining the components, data model, local and cloud
   boundaries, APIs, security model, and online/offline behaviour.

---

# dios — PRD

## Problem

Setting up DimOS is driven by a fragile script and differs across robots and boards. FDEs are
integrating new platforms quickly, recording the work in floating Markdown guides and personal
notes. The guides drift, important steps are easy to miss, and every new platform repeats work that
should be reusable.

## Why now

The number of platforms is growing faster than the manual process can support. There is no reliable
versioning across dios, DimOS, per-robot wizards, firmware, or installed targets, so a working setup
cannot be reproduced confidently or compared with another robot. Continuing with scripts and guides
makes each integration more fragile and support harder.

FDEs have already been testing a curl command that provides a better DimOS installation path. This
release turns that tested entry point into a supported dios product and adds substantially more:
per-robot wizards, target discovery, repeatable verification, versioned artifacts, safe re-runs, and
a record of what was installed.

## Solution

One static binary, two capabilities.

**Package manager.** Given a machine, install DimOS correctly for its platform.

**Provisioner.** Given a robot, identify it, reach it, install what it requires, leave it configured
to run.

Principles:

1. The package manager knows platforms; the provisioner knows robots. Neither crosses over.
2. The package manager works standalone.
3. Every step states what proves it succeeded. A proven step is skipped, so a re-run resumes.
4. Degrade rather than fail. An unsupported platform gets instructions.

## Wizards

A wizard is data for one type of robot: how to recognise it, reach it, and configure it. Anyone can
author and share one without modifying the tool. A wizard declares the permissions it needs, so an
operator can review it before trusting it.

One static JSON index maps a wizard name to a pinned git revision and a hash.
`dios wizard add unitree-g1` installs by name, and adding a board is a PR against the
index, never against dios. The index URL is configurable, which is also how a mirror or a company
index works.

## Interface

The product interface is:

- `dios setup` — full install on this machine
- `dios doctor` — diagnostics; `--wizard <name>|all` checks wizard files with no robot present
- `dios update`, `service`, `restart`, `log`, `config`, `uninstall` — care and feeding
- `dios webserver`, `install`, `desktop` — management server and desktop packages
- `dios seed` — set up a target; `--with <wizard>` skips the match step
- `dios seed scan` — find candidates on Ethernet, USB, Wi-Fi, and Bluetooth
- `dios seed check` — judge each step live as holds, would run, or done; apply nothing
- `dios seed bringup` — reach a fresh target over the cable
- `dios wizard new|list|show|test|add|remove|search|update` — work with wizards, no target needed
- `dios verb list|run` — one operation against one machine

`wizard add <name>` is index-resolved, revision-pinned, and hash-checked. `wizard search`,
`wizard update`, and `dios config set wizards.index <url>` support discovery and mirrors.
`wizard add <git-url>` remains the explicit escape hatch.

Modes are interactive, unattended (`--non-interactive`), and agent (`--agent`). Agent mode never
prompts; a critical failure exits 2 with a JSON block saying what a human has to decide.

## Technical boundaries

dios has two layers. The package manager knows operating systems, architectures, package providers,
and DimOS requirements. It must not contain robot manufacturers, models, protocols, or wizard
logic. The seeding layer knows targets and wizards and may call the package manager. The package
manager never calls upward into seeding.

The workstation runs discovery and orchestration. The target runs the installed dios binary,
DimOS, manufacturer configuration, and the final blueprint proof. A wizard may prepare a target and
then invoke the standard `dios setup` flow there; it does not implement a second DimOS installer.

## Installation pipeline

The bootstrap detects the workstation platform, downloads the matching static binary, makes it
executable, and starts setup. Supported release targets include macOS ARM64, Linux x86-64 musl, and
Linux ARM64 musl. Exact versions can be selected through an environment variable; otherwise the
bootstrap requests the default release.

`dios setup` then detects the operating system, architecture, GPU, Jetson hardware, Python version,
RAM, disk, libc, and existing tools. It checks compatibility, installs itself under the user's local
binary directory, configures PATH, and applies platform setup where supported.

The operator chooses library or development mode. Library mode creates an application directory and
installs a released DimOS package. Development mode clones the DimOS repository and performs an
editable installation. Both use a virtual environment and support optional feature groups.

System packages come from apt, dnf, pacman, apk, Homebrew, or Nix depending on the platform. Native
runtime libraries are verified separately because a successful Python install does not prove that
OpenGL, EGL, camera, audio, or vendor SDK libraries can load.

Setup finishes by checking the virtual environment, importing DimOS, locating its CLI, and checking
GPU support when requested. When setup is part of a robot wizard, final success belongs to the
wizard's later headless blueprint test, not to package installation alone.

## Wizard contract

Each wizard is specific to a robot family or manufacturer and supplies:

1. its name, immutable version, and supported models;
2. discovery probes and identity evidence;
3. requested permissions;
4. initial network and access steps;
5. parameters passed to the standard setup engine;
6. target-specific work before and after setup;
7. runtime configuration;
8. a final target-specific blueprint proof;
9. a structured result containing identity evidence, versions, and step outcomes.

Wizard steps declare where they run, whether they are critical, what permissions they require, and
what command proves completion. Steps are ordered by phase. A re-run checks the proof first and skips
work that already holds.

The wizard index is static JSON. It maps a name to a source repository, immutable revision, path,
hash, minimum supported API version, and maintainer. dios verifies the downloaded content before it
runs. An unknown maintainer requires explicit approval and cannot be silently accepted by an agent.

## Target discovery and seeding result

Discovery can observe Ethernet, USB networking, Wi-Fi, and Bluetooth. Evidence is scored against
wizard declarations. A close match may be suggested automatically; ambiguous matches require the
operator to choose.

Seeding produces a structured result containing the selected target, identity evidence, observed
addresses, wizard, installed versions, step outcomes, and time. This is the input available to the
product layer for robot registration. The product-layer PRD and architecture must decide where it is
stored, how records are matched, which system owns each field, and how offline changes reconcile.

A run journal allows a failed seed to retry only unfinished work. Passwords, Wi-Fi secrets, and
private keys never appear in the structured result, command arguments, or logs.

## Execution and failure model

Every operation is first represented as a plan. Dry-run prints that plan and cannot touch either
machine. The executor applies one operation at a time and runs its proof afterward. A failed
operation whose proof now holds is treated as complete; otherwise its criticality decides whether
the run stops or continues.

Interactive mode may ask a person to repair a problem. Unattended mode takes defaults and stops on a
critical failure. Agent mode never prompts; a decision that requires a person exits with code 2 and
structured `needs_human` output. Ordinary failure exits 1, interruption exits 130, and success exits
0.

Remote work uses non-interactive SSH after initial key installation. Passwords reach privileged
commands through stdin or a temporary askpass file rather than command-line arguments. Temporary
secret files are permission-restricted and removed after use.

## Package dependency design

Every DimOS module has a checked-in dependency manifest containing Python requirements and abstract
system keys such as `opengl.runtime` or `audio.portaudio`.

A versioned catalog maps those abstract keys to apt, Homebrew, Nix, dnf, pacman, or apk packages for
each supported platform. Package authors declare requirements but do not provide arbitrary install
commands. dios owns generic provider adapters that query installed state, compare native versions,
install missing packages, and verify the result.

Release tooling aggregates the standard profile, optional profiles, wizard requirements,
module manifests, Python lock, Nix lock, and provider catalog. Conflicting constraints or missing
platform mappings fail before mutation. A receipt records the selected profiles, catalog digest,
lock digests, requested constraints, provider, and versions actually observed.

Version guarantees differ by provider. Python uses PEP 508 constraints and a uv lock. Nix uses
pinned inputs and realised store paths. apt uses Debian version ordering and needs a repository
snapshot for exact replay. Homebrew is rolling and normally guarantees compatibility rather than an
arbitrary historical version. Drivers, firmware, kernels, and vendor SDKs are host capabilities
verified by explicit probes rather than silently replaced.

## Success criteria

- A fresh robot reaches running DimOS in one `dios seed` workflow, and the run proves it by running
  a blueprint.
- A re-run changes nothing.
- A new robot needs no change to the tool: a wizard and an index entry.

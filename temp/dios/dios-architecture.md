# dios — Product Architecture

**PRD:** [dios-prd.md](dios-prd.md)

## Core idea

`dios setup` is the generic DimOS installer inherited from Helm. It installs DimOS on the machine
where it runs, whether that machine is a developer workstation or a robot target.

Manufacturer repositories own robot-specific wizards. A wizard prepares its target, invokes the
standard dios setup flow on that target, performs manufacturer-specific finishing work, and proves
the final robot experience.

```text
┌──────────────────┐     launches      ┌─────────────────────────┐
│    dios core     │ ────────────────▶ │ manufacturer integration│
│                  │                   │ e.g. dios-unitree       │
│ • setup          │                   │                         │
│ • doctor         │                   │ • discovery             │
│ • update         │                   │ • wizard UX             │
│ • service/logs   │                   │ • network bring-up      │
│ • target history │                   │ • firmware rules        │
└────────┬─────────┘                   │ • final robot proof     │
         │                             └────────────┬────────────┘
         │ standard setup engine                    │ orchestrates
         └──────────────────────────────┐           │
                                        ▼           ▼
                                  ┌─────────────────────┐
                                  │       target        │
                                  │                     │
                                  │ dios setup          │
                                  │ DimOS               │
                                  │ manufacturer config │
                                  │ blueprint proof     │
                                  └─────────────────────┘
```

## Repository ownership

### dios core

- `dios setup` and the existing Helm installation experience
- platform detection and compatibility
- library and development installation modes
- DimOS dependency installation
- doctor, service, update, log, config, and uninstall
- interactive, unattended, and agent execution modes
- manufacturer integration discovery and launching
- local target and version history
- common result and action reporting

dios core does not name a manufacturer, model, robot protocol, or manufacturer firmware.

### Manufacturer repository

For example, `dios-unitree` owns:

- G1, Go2, B2, and other Unitree model definitions
- Unitree discovery and identification
- Unitree network bring-up and access
- firmware compatibility rules
- the complete Unitree wizard
- Unitree-specific pre-setup and post-setup operations
- selection and verification of the final Unitree blueprint

Each manufacturer can release and test its integration independently from dios core.

### DimOS repository

- the DimOS package and modules
- extras and runtime requirements
- blueprints
- released DimOS versions
- the compatibility information needed by `dios setup`

## Workstation installation flow

```text
install.sh
   │ detect workstation platform
   │ download and verify dios
   ▼
dios setup
   │ preserve current Helm questions and modes
   │ install dependencies and DimOS
   │ configure the local environment
   ▼
local DimOS verification
```

No manufacturer integration participates in this flow.

## Robot seeding flow

```text
Operator                  dios core            Unitree integration       G1 target
   │                          │                          │                    │
   │ dios seed unitree       │                          │                    │
   ├────────────────────────▶│ verify + launch          │                    │
   │                          ├─────────────────────────▶│                    │
   │                          │                          │ discover / select  │
   │◀─────────────────────────┴──────────────────────────┤                    │
   │ confirm target + permissions                       │                    │
   ├────────────────────────────────────────────────────▶│                    │
   │                          │                          │ bring up + access  │
   │                          │                          ├───────────────────▶│
   │                          │                          │ install dios       │
   │                          │                          ├───────────────────▶│
   │                          │            dios setup runs on target         │
   │                          │◀─────────────────────────────────────────────▶│
   │                          │                          │ Unitree finishing  │
   │                          │                          ├───────────────────▶│
   │                          │                          │ blueprint proof    │
   │                          │                          ├───────────────────▶│
   │                          │ save local result        │                    │
   │◀─────────────────────────┤                          │                    │
```

## Manufacturer integration contract

A manufacturer repository supplies:

1. an integration name and immutable version;
2. supported models;
3. a wizard entry point;
4. requested permissions;
5. discovery and identification behavior;
6. pre-setup work;
7. arguments needed by the standard `dios setup` flow;
8. post-setup work;
9. a final target-specific verification;
10. a structured result for local history.

dios supplies integration verification, launch behavior, execution mode, the generic setup engine,
local target records, and common action reporting.

## Local state

The workstation stores local JSON only:

- target name and stable identity;
- manufacturer and model;
- current and previous observed addresses;
- manufacturer integration version;
- dios and DimOS versions;
- last seed result and time.

Addresses are observations, not identities. Secrets are never stored in target history.

## Compatibility rule

There are two checks:

1. **Generic setup compatibility**, owned by dios and DimOS: operating system, architecture,
   dependencies, and DimOS version.
2. **Robot compatibility**, owned by the manufacturer integration: model, firmware, required
   manufacturer software, and supported blueprint.

Both must pass before the target is changed.

## Package dependency architecture

DimOS follows a ROS2/rosdep-style model:

```text
DimOS module ──declares──▶ logical package ID
                                  │
                                  ▼
                         dimos.package.toml
                         • Python requirements
                         • abstract system keys
                                  │ release aggregation
                                  ▼
                 versioned DimOS dependency catalog
                    │          │          │
                    ▼          ▼          ▼
                   uv         apt        brew / Nix
                    └──────────┬───────────┘
                               ▼
                       dios install plan
```

Package authors declare dependencies, but never installation commands. A reviewed catalog maps
abstract system keys to provider packages by OS and release. The catalog is versioned with DimOS,
not compiled into dios.

dios owns generic provider adapters for uv, apt/dpkg, Homebrew, and Nix. Each adapter knows how to
query installed state, compare versions using that provider's rules, install, and verify. Package-
specific shell commands are not accepted from module manifests.

Each DimOS release aggregates the standard profile, optional profiles, package manifests, Python
lock, Nix lock, and provider catalog. A setup plan is the union of:

1. the standard DimOS profile;
2. optional profiles selected by the user, such as simulation;
3. requirements imposed by a manufacturer integration;
4. later, package IDs required by a blueprint.

Conflicts and missing platform mappings fail before mutation. dios records both the desired graph
and provider versions actually observed; exact reproducibility is claimed only where the provider
can deliver it.

The future `dimos run` hook must inspect blueprint package metadata before importing modules or
starting workers. It asks dios to check the complete plan and prompts before installing. Catching a
`ModuleNotFoundError` after launch is not a sufficient dependency system.

## Migration from the current code

1. Preserve current Helm behavior behind `dios setup`.
2. Define the manufacturer integration boundary.
3. Create the Unitree repository and wizard.
4. Move Unitree-specific code and recipes out of dios core.
5. Rename the user-facing provisioning flow from `infect` to `seed`.
6. Add the local `dios target` experience.
7. Introduce logical package manifests and generate current Python extras from them.
8. Add the reviewed system-provider catalog and dios provider adapters.
9. Replace runtime import-triggered installation with blueprint dependency preflight.
10. Verify the new split on a real G1.

The migration should move behavior before deleting it. The working setup path remains usable at
every step.

# DIOS Technical Spec

**PRD:** [DIOS: DimOS BIOS](https://linear.app/dimensional/document/dios-dimos-bios-prd-a28b2066e646)

## Repository boundaries

The new implementation is private `dios` plus open-source wizards. `dimos` stays unchanged.

| Repository | Owns |
|---|---|
| `dimos` | The software being installed. No DIOS additions. |
| `dios` | Private orchestration, verification, Doctor, target registry, auth, cloud, and licensing. No platform setup. |
| `dimos-setup-wizard` | Open-source Rust code for complete DimOS setup and checks. |
| `<manufacturer>-setup-wizard` | Open-source Rust code for that manufacturer's discovery, setup, and checks. |

LCM setup lives in `dimos-setup-wizard`. CycloneDDS and Unitree SDK setup live in
`unitree-setup-wizard`. A new manufacturer adds a wizard, not code in `dios` or `dimos`.

<img width="820" alt="DIOS repository boundaries" src="https://github.com/dimensionalOS/dios/raw/refs/heads/docs/dios-technical-spec/docs/technical-spec/diagrams/runtime-resolution.png">

## Wizard contract

A wizard is a pinned Rust binary. Setup is code, not a configuration schema. DIOS passes no setup
values.

Every wizard exposes the same commands:

```text
info       identify wizard, version, and protocol
plan       show mutations
setup      apply, then verify
verify     read-only readiness check
doctor     read-only findings for a human or agent
```

Dry-run cannot mutate. JSON and exit codes are stable APIs. Exit 0 means ready, 1 failed, and 130
interrupted.

## Setup and Seed

For a workstation, DIOS downloads and runs `dimos-setup-wizard`.

For a robot, DIOS runs its manufacturer wizard, then `dimos-setup-wizard` where DimOS will run. The
manufacturer wizard discovers and prepares the robot. The DimOS wizard installs DimOS. DIOS verifies
a headless blueprint and saves the target.

Offboard setups run both wizards on the workstation. Onboard setups copy DIOS and the pinned wizards
to the robot and run them there.

## Versioning — review question

One install must pin four things together:

```toml
schema = 1
dios = { version = "1.0.0", protocol = 1 }
dimos = { version = "0.0.13.post1", git_rev = "<commit>" }

[[wizard]]
name = "dimos-setup-wizard"
version = "0.1.0"
git_rev = "<commit>"
sha256 = "<release-content-hash>"

[[wizard]]
name = "unitree-setup-wizard"
version = "0.1.0"
git_rev = "<commit>"
sha256 = "<release-content-hash>"
```

**Proposed MVP:** Dimensional publishes this signed install set. DIOS verifies it and writes the
exact result to `dimos.lock`. Re-runs use that lock. Updates verify a new set before replacing it.

## Doctor

`dios doctor` runs DIOS checks, then calls `doctor` on every wizard in `dimos.lock`.

Anything not specified here stays at parity with `scripts/install.sh` today.

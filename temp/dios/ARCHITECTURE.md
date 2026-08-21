# DIOS technical spec

**PRD:** [DIOS: DimOS BIOS](https://linear.app/dimensional/document/dios-dimos-bios-prd-a28b2066e646)

## the idea

DIOS is a small private app that starts setup.

It only downloads a wizard, runs it, and saves the result.

It knows nothing about Linux packages, LCM, CycloneDDS, Unitree, or any other machine.

That specific code lives in open-source wizards.

`dimos` stays unchanged.

Adding a DimOS version or robot should mean releasing a wizard, not changing DIOS.

## repos

| repo | job |
|---|---|
| `dios` | Download and run wizards, then save their results. |
| `dimos-setup-wizard` | Install and check DimOS, including LCM. |
| `unitree-setup-wizard` | Find and prepare Unitree robots, including CycloneDDS and the Unitree SDK. |
| `<manufacturer>-setup-wizard` | Hold setup code for one manufacturer. |
| `dimos` | Be DimOS. Nothing for DIOS lives here. |

Each new manufacturer gets a seperate wizard repo.

## setup

For a workstation, DIOS runs `dimos-setup-wizard`.

For a Unitree robot, DIOS runs `unitree-setup-wizard` and then `dimos-setup-wizard`.

The first wizard prepares the robot and the second installs DimOS.

The DimOS wizard runs a blueprint to prove the setup works.

DIOS then saves the target and the exact verisons used.

## wizards

A wizard is a normal Rust program with code for one specific job.

Every wizard supports `info`, `plan`, `setup`, `verify`, and `doctor`.

Humans get text, agents get JSON, and dry-run changes nothing.

There are no configurators and no setup YAML files.

## versioning

The simplest option is for every release to pin the exact next release it needs.

```text
unitree-setup-wizard release
  -> exact dimos-setup-wizard release
       -> exact dimos git commit
```

A workstation starts at `dimos-setup-wizard` and uses the DimOS commit it pins.

Each pin includes a version, git commit, and release hash.

DIOS checks the pins and writes the final list to `dimos.lock`.

A re-run uses the lock, so it installs the same thing again.

An update starts from a newer wizard and replaces the lock only after setup passes.

There are no version ranges, no compatibility solver, and no version files in `dimos`.

DIOS only needs one stable wizard API, so setup changes do not require DIOS releases.

## doctor

DIOS Doctor runs each wizard's Doctor and shows which layer failed.

DIOS does not understand the checks; it only shows what the wizards report.

## not in the MVP

- dependency YAML files
- `info.yaml` files in DimOS modules
- a configurator system
- additions to `dimos`

Metadata can come later if we ever need it.

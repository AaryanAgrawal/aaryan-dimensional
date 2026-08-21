# DIOS technical spec

## overview

DIOS is a small private launcher. It downloads the right open-source wizards, runs them, and records
what they installed.

DIOS does not know how to install DimOS or prepare a robot. That specific code lives in the wizards.
Adding a DimOS version or manufacturer should never require a DIOS change.

The main rules are:

- `dios` only downloads, runs, and records wizards.
- Wizards contain all setup code and checks.
- `dimos` contains nothing for DIOS. It is installed exactly as it is.

## basic flow

1. The user installs DIOS and chooses a workstation or robot.
2. DIOS downloads the chosen wizard release.
3. A manufacturer wizard finds and prepares the robot, when needed.
4. `dimos-setup-wizard` installs and checks DimOS.
5. `dimos-setup-wizard` runs a blueprint to prove the setup works.
6. DIOS saves the target and exact verisons used.

A workstation only needs `dimos-setup-wizard`. A Unitree robot needs `unitree-setup-wizard` first.

For onboard setups, the wizards run on the robot computer. For offboard setups, they run on the
workstation where DimOS will run.

## how the repos fit together

| repo | what it owns |
|---|---|
| `dios` | Downloads and runs wizards, then saves their results. |
| `dimos-setup-wizard` | Everything needed to install and check DimOS, including LCM. |
| `unitree-setup-wizard` | Unitree discovery and setup, including CycloneDDS and the Unitree SDK. |
| `<manufacturer>-setup-wizard` | Discovery and setup for one manufacturer. |
| `dimos` | The software being installed. Nothing for DIOS lives here. |

A new manufacturer gets a seperate wizard. New setup work only changes that wizard.

## what a wizard does

A wizard is a normal Rust program with setup code for one specific job. It can:

- explain what it is and which version is running
- show what setup will change
- perform setup
- check whether setup worked
- diagnose problems later

Humans get clear text. Agents get JSON. Dry-run shows the plan without changing the machine.

There is no configurator framework. DIOS does not pass setup values into a wizard. The wizard knows
what it needs and keeps that code beside its checks.

## versioning — review question

Use a simple chain of pins:

```text
unitree-setup-wizard release
  -> pins one dimos-setup-wizard release
       -> pins one exact dimos git commit
```

The same pattern works for every manufacturer. A workstation starts at `dimos-setup-wizard` and
uses the DimOS commit it pins.

The pins live as constants in each wizard release. DIOS reads them, downloads those exact releases,
checks their hashes, and writes the final chain to `dimos.lock`. Re-runs use the lock. An update
starts from a newer wizard release and writes a new lock only after setup passes.

DIOS only needs one stable wizard protocol, not a new release for every setup. Nothing is added to
`dimos`.

## doctor

DIOS Doctor first checks DIOS, then asks every wizard in `dimos.lock` to run its own checks. The
result should tell a human or agent which layer failed and what to try next.

## moving setup code

LCM setup belongs in `dimos-setup-wizard`. CycloneDDS, the Unitree SDK, and other Unitree-only setup
belong in `unitree-setup-wizard`.

Nothing new is added to `dimos`. If old setup code is removed later, that PR contains deletions only.

## not in the MVP

- dependency YAML files
- `info.yaml` in each DimOS module
- a generic configurator system
- changes to DimOS APIs

YAML or module metadata would require a schema enforced by `dimos`. Wizard code keeps the first
version smaller; metadata can come later.

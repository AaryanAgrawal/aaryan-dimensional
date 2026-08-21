# DIOS technical spec

**PRD:** [DIOS: DimOS BIOS](https://linear.app/dimensional/document/dios-dimos-bios-prd-a28b2066e646)

## base overview

DIOS sets up DimOS on a workstation or robot.

DIOS is a small private app installed before DimOS.

It downloads setup wizards, runs them, and saves what happened.

DIOS contains no code for a specific machine, robot, or DimOS version.

All specific setup code lives in open-source wizards.

`dimos` stays unchanged.

<img width="760" alt="DIOS repository boundaries" src="https://github.com/dimensionalOS/dios/raw/refs/heads/docs/dios-technical-spec/docs/technical-spec/diagrams/runtime-resolution.png">

| repo | what it owns |
|---|---|
| `dios` | Downloading and running wizards, Doctor, and the target history. |
| `dimos-setup-wizard` | Installing and checking DimOS, including LCM setup. |
| `unitree-setup-wizard` | Unitree discovery and setup, including CycloneDDS and the Unitree SDK. |
| `<manufacturer>-setup-wizard` | Setup for one manufacturer. |
| `dimos` | DimOS itself, with nothing added for DIOS. |

A new manufacturer gets a new wizard repo.

Adding one should not change `dios` or `dimos`.

In the diagrams, `dimos` is blue, `dios` is amber, the DimOS wizard is green, and manufacturer wizards are purple.

Grey means the item is not a repo.

## what stays in DimOS

Normal language dependency files stay in `dimos` unchanged.

These include `pyproject.toml`, `uv.lock`, `Cargo.toml`, `Cargo.lock`, `CMakeLists.txt`, `flake.nix`, and `flake.lock`.

Wizards handle what those files cannot: system packages and machine setup.

LCM setup belongs in `dimos-setup-wizard`.

CycloneDDS and the Unitree SDK belong in `unitree-setup-wizard`.

Greptile CI should check that a DimOS PR also updates the right wizard when system requirements change.

This keeps code and setup from drifting apart.

## words used below

**Package dependency** means software installed with apt, Nix, Brew, or another package manager.

**System dependency** means machine setup such as an LCM multicast route or a CUDA driver.

**Wizard** means a repo and binary that sets up one kind of machine or robot.

**Target** means a board or robot being set up from a workstation.

## wizard interface

A wizard is a static Rust binary for each supported CPU architecture.

It should not depend on tools already being installed on the target.

Every wizard answers the same five commands:

```console
$ dimos-setup-wizard info --json
{"api":1,"name":"dimos-setup-wizard","version":"0.1.0"}

$ dimos-setup-wizard plan
sudo sysctl -w net.core.rmem_max=67108864
sudo ip route replace 224.0.0.0/4 dev lo
...

$ dimos-setup-wizard setup
$ dimos-setup-wizard verify
$ dimos-setup-wizard doctor --json
```

`info` identifies the wizard and reports its pins.

`plan` shows every change without making one.

`setup` applies the changes and then checks them.

`verify` only checks whether setup worked.

`doctor` explains what is wrong and how to fix it.

Exit `0` means ready, `1` means failed, and `130` means interrupted.

Every finding says what was found, what was wanted, and the fix when one exists.

Those fields are the contract; each wizard owns its own check names.

DIOS learns a wizard's name and API by running `info`.

DIOS does not keep a list of manufacturers in its code.

There are no configurators and no setup YAML files.

Setup is normal code inside each wizard.

## setup and seed

Setup installs DimOS on the current machine.

Seed starts on a workstation and prepares another target.

Both paths use the same `dimos-setup-wizard`.

Both paths verify DimOS and update the target history.

### workstation setup

DIOS downloads and runs `dimos-setup-wizard` on the workstation.

<img width="320" alt="DIOS Setup flow" src="https://github.com/dimensionalOS/dios/raw/refs/heads/docs/dios-technical-spec/docs/technical-spec/diagrams/setup-flow.png">

### offboard seed

The manufacturer wizard and DimOS run on the workstation.

They connect to the robot through its normal interface, such as WebRTC on a Go2.

<img width="320" alt="DIOS offboard Seed flow" src="https://github.com/dimensionalOS/dios/raw/refs/heads/docs/dios-technical-spec/docs/technical-spec/diagrams/offboard-flow.png">

### onboard seed

DIOS and the pinned wizards are copied to the robot computer.

The wizards run there and install DimOS there.

<img width="320" alt="DIOS onboard Seed flow" src="https://github.com/dimensionalOS/dios/raw/refs/heads/docs/dios-technical-spec/docs/technical-spec/diagrams/onboard-flow.png">

### target history

After setup, DIOS saves the target's nickname, address, identity, installed versions, and last result.

The MAC address is the main identity when one is available.

This lets DIOS recognize the same target after its IP changes.

Secrets never go in the target history.

## versions

The three parts change at different speeds.

| part | changes when |
|---|---|
| `dimos` | DimOS code changes. |
| a wizard | Setup for that machine changes. |
| `dios` | The small wizard API changes. |

DIOS should stay on API `1` while setup changes around it.

A new robot, package, or DimOS release should only need a wizard release.

### simplest pinning model

Every wizard release pins the exact next release it needs.

```text
unitree-setup-wizard release
  -> exact dimos-setup-wizard release
       -> exact dimos git commit
```

A workstation starts at `dimos-setup-wizard` and follows its DimOS pin.

Each pin includes the release, git commit, and binary hash.

DIOS follows the pins and refuses a missing hash or wrong wizard API.

There are no version ranges and no compatibility solver.

Nothing about this is stored in `dimos`.

## dimos.lock

`dimos.lock` records exactly what a machine has installed.

It lives beside the target history.

```jsonc
// ~/.dimos/dimos.lock
{
  "lock_api": 1,
  "target": "52:54:00:95:d1:42",
  "dios": { "version": "1.0.0", "wizard_api": 1 },
  "dimos": {
    "version": "0.0.13.post1",
    "rev": "091143364",
    "dir": "/home/unitree/dimos"
  },
  "wizards": {
    "unitree-setup-wizard": {
      "version": "0.1.0",
      "rev": "<commit>",
      "sha256": "<release-hash>"
    },
    "dimos-setup-wizard": {
      "version": "0.1.0",
      "rev": "<commit>",
      "sha256": "<release-hash>"
    }
  }
}
```

DIOS updates the lock after each completed step.

An interrupted run still leaves a truthful record.

A re-run uses the lock instead of choosing new versions.

Passing a lock to another machine installs the same versions there.

An update starts with a newer top-level wizard and replaces the lock only after verification passes.

Nobody edits the lock by hand.

## doctor

`dios doctor` runs on either a workstation or robot.

DIOS reads `dimos.lock` and runs Doctor from every recorded wizard.

Each wizard checks the setup it owns and gives the next action.

DIOS only combines the answers and shows which layer failed.

It does not understand wizard-specific checks.

A missing recorded wizard is itself a blocking problem.

```console
$ dios doctor
  + dios: ready

  dimos-setup-wizard 0.1.0
  - multicast: not enabled
    run DimOS setup again

  unitree-setup-wizard 0.1.0
  - cyclonedds: wrong revision
    run Unitree setup again
```

DIOS Doctor helps a human or agent find where the problem is.

## later, not now

We may add one dependency YAML or an `info.yaml` beside each DimOS module later.

Either option needs a schema enforced in `dimos`.

Wizard code keeps the MVP smaller and requires no DimOS change.

Anything not covered here stays close to `scripts/install.sh` today.

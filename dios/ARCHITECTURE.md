# DIOS Technical Spec

**PRD:** [DIOS: DimOS BIOS](https://linear.app/dimensional/document/dios-dimos-bios-prd-a28b2066e646)

## Base overview

DIOS resolves the dependencies for a DimOS release or blueprint, compares them with the machine,
and executes one versioned plan. Manufacturer wizards contain their own target requirements through
the same interface.

**DIOS** is the DimOS BIOS. It lives outside DimOS and is installed on a machine first, like Epic
Games Launcher, Adobe Creative Cloud, or NVIDIA GeForce Experience.

**Package dependency** is software installed through a package manager such as apt, Nix, or Brew.

**System dependency** is required machine configuration, such as LCM multicast settings or a CUDA
driver.

**Wizard** is a separate GitHub repository for each manufacturer. It contains manufacturer-specific
dependencies and setup, keeping less uniform integration work outside the main DimOS repository.

**Target** is a board or robot seeded from a workstation. Seeding installs DIOS on the target first
and runs Setup locally. The target registry then records information including IP address, MAC
address, Bluetooth identity, installed versions, and nickname.

<img width="820" alt="DIOS repository boundaries" src="https://github.com/dimensionalOS/dios/raw/refs/heads/docs/dios-technical-spec/docs/technical-spec/diagrams/runtime-resolution.png">

Each manufacturer wizard lives in its own repository. Unitree-specific dependencies and setup,
including CycloneDDS and the Unitree SDK, move from DIOS into the Unitree wizard repository.

## Setup and Seed

Setup installs vanilla DimOS on the current machine. Seed reuses this same Setup flow instead of
maintaining another DimOS installer.

**DIOS Setup**

<img width="420" alt="DIOS Setup flow" src="https://github.com/dimensionalOS/dios/raw/refs/heads/docs/dios-technical-spec/docs/technical-spec/diagrams/setup-flow.png">

Seed starts on a workstation and downloads the selected target wizard. Both paths verify the
installation and update the workstation's target registry.

**Offboard**

The wizard and Setup run on the workstation and connect to the target, such as WebRTC to a Go2.

<img width="420" alt="DIOS offboard Seed flow" src="https://github.com/dimensionalOS/dios/raw/refs/heads/docs/dios-technical-spec/docs/technical-spec/diagrams/offboard-flow.png">

**Onboard**

DIOS and the wizard are copied to the target, where Setup runs locally.

<img width="420" alt="DIOS onboard Seed flow" src="https://github.com/dimensionalOS/dios/raw/refs/heads/docs/dios-technical-spec/docs/technical-spec/diagrams/onboard-flow.png">

## Key eng decisions

## 1. Where does `info.yaml` live?

```yaml
schema: 1

package_managers:
  apt: [libeigen3-dev]
  brew: [eigen]
  nix: [eigen]

custom_dependencies:
  lcm_network:
    receive_buffer_bytes: 67108864
    loopback_multicast: true

  rust:
    toolchain: "1.93.1"
    components: [rustfmt, clippy]
```

`info.yaml` declares the packages and machine configuration required by one runnable module.

Do we keep one beside every runnable module, or one large file for all of DimOS? A file beside each
module keeps requirements with their code; release CI can aggregate them into one index for DIOS.

```text
some_module/
├── module.py
└── info.yaml
```

## 2. What package names do modules use?

Modules can list provider names directly, or use logical IDs backed by a central mapping. Direct
names are simpler for the MVP; logical IDs avoid repetition but create another registry to maintain.

Python dependencies stay in the root `pyproject.toml` and `uv.lock`. Other languages keep their
existing native build and lock files.

## 3. Where does non-package setup code live?

A system configurator is versioned code for machine state such as LCM multicast/sysctl settings or
Rust installed through rustup. It provides `check → plan → apply → verify`; YAML contains values,
never commands.

<img width="520" alt="LCM system configurator" src="https://github.com/dimensionalOS/dios/raw/refs/heads/docs/dios-technical-spec/docs/technical-spec/diagrams/lcm-configurator.png">

Putting every configurator in DIOS gives one registry but makes DimOS changes depend on a DIOS PR.
Keeping each configurator with DimOS or its manufacturer wizard lets its metadata, implementation,
and tests change together. We propose the latter, with DIOS owning only the protocol and runner.

## 4. What is versioned with a release?

Release CI can generate one dependency index from the selected module metadata, existing language
locks, and configurator registry. DIOS reads that index instead of rediscovering dependencies during
every setup.

Python and Nix can be locked. Apt and Brew normally change with their repositories, so we need to
decide whether recording observed versions is enough initially or whether any packages require exact
constraints or repository snapshots.

## Other decisions

- Can blueprints add requirements, or do requirements come only from modules and manufacturer wizards?
- How does a clean machine run a DimOS-owned configurator before DimOS is installed: a standalone
  release runner or a temporary staging environment?
- How are manufacturer wizard configurators pinned and trusted?
- Does a failed update require universal rollback, or a verified recovery path where rollback is
  unavailable?

Verbose, dry-run, non-interactive, agent, and Doctor modes all use the same resolver. Dry run and
Doctor never change machine state; runtime records remain local JSON and contain no secrets.

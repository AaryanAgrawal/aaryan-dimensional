# One-click DimOS install — findings

From a 7-agent recon on 2026-08-07, including a real install on the G1 at `10.0.0.190`.
Verified means executed. Everything else is marked.

## The headline: the torch failure did not reproduce

DimOS installed on the G1 and torch imports fine.

    $ python -c 'import torch; print(torch.__version__)'
    2.6.0+cpu

Tested in 10 import orderings and a 105-shared-object worst case. `libtorch_cpu.so` uses 119
`R_AARCH64_TLSDESC` relocations and zero TPREL, so it never draws on the static TLS surplus.

**Why it works here: the GPU is misdetected.** Both probes shell `nvidia-smi`, which does not exist
on Tegra, so dim concludes `CPU only` and installs the CPU wheel. The CPU wheel is not the one that
would trip the surplus. There is no Jetson CUDA wheel to install anyway — `pyproject.toml:315-324`
has the only Jetson extra commented out (404 URLs), and it targets JP6 / CUDA 12.6 / cp310 while the
board is JP5.1.1 / CUDA 11.4 and dim installs Python 3.12.

So the `LD_PRELOAD` workaround and the #3057 branch pin both protect against something not observed
on this board. Do not carry either. If the crash is real it most likely came from a Jetson CUDA
wheel, which could not be tested because none exists.

`G1_SETUP_GUIDE.md:271` documents the symptom, so it is a written report that one run failed to
reproduce — not folklore, and not confirmed.

## The actual blocker: unattended install is impossible

`configure_jetson()` never took `non_interactive`, unlike every other stage. It called
`cliclack::confirm` unconditionally.

- 7/7 attempts in `~/.dimos/data/actions.log` → `failed: not connected`
- over `ssh -tt` it blocks until `timeout 45` kills it (exit 124)

Two further defects behind it, both found by running the patched binary on the robot:

- `boot.rs` shells `sudo` directly via `run_cmd` and never calls `ensure_sudo()`, unlike
  `deps.rs:488` and `unitree.rs:139`.
- `ensure_sudo()` only knew how to ask on a terminal, so with no TTY it died on
  `sudo: a terminal is required` instead of using the standard askpass mechanism.

**Fixed on branch `fix/jetson-non-interactive` in `dimos-helm`** — 3 files, +30/-6, each change copying
an existing house pattern. `cargo check` clean, cross-built for aarch64-musl, verified on the G1:

    # without askpass, no tty: fails fast with the remedy instead of hanging
    ■ 'jetson boot config' failed: sudo password needed and there is no terminal to ask on.
      Set SUDO_ASKPASS to a helper, grant NOPASSWD, or run with --no-nix

    # with askpass: the stage that failed 7/7 now passes unattended
    ◆ Jetson boot config applied

Not pushed — no PR opened.

Still open: the apt and Nix stages shell sudo through other paths and were not re-tested end to end.

## GPU misdetection — fixed

`detect_gpu` and `doctor::check_cuda` both shelled `nvidia-smi`, which does not exist on Tegra, so
the one board in the fleet with a GPU reported `CPU only`. Both now fall back to
`/etc/nv_tegra_release` + `nvcc`. Verified on the G1:

    GPU:  NVIDIA GPU (CUDA 11.4)          # was: CPU only
    +  CUDA: 11.4 (tegra, no nvidia-smi)  # was: nvidia-smi not found

This changes what `dim doctor` reports, not which torch wheel installs — there is no Jetson CUDA
wheel to select.

## Other verified defects

| Defect | Evidence |
|---|---|
| Default install ships no DimOS | `dim setup --dry-run --non-interactive` → `dim + desktop installed (skipped DimOS install)` |
| `--extras unitree` silently becomes `dimos[]` | resolves exit 0, no warning. `todo.md` already flags this |
| `dimos` not on PATH after install | only at `<project>/.venv/bin/dimos` |
| `--dry-run` ran the real Nix installer | observed on the robot; one agent found the opposite on x86 — unresolved conflict |
| numpy silently downgraded 2.3.5 → 1.26.4 | required by the Unitree SDK |
| `dim doctor` never mentions DimOS | 17 host probes, no import check, no blueprint preflight |

## What already exists — do not rebuild

- **Lazy on-run deps, for native modules.** `dimos/core/native_module.py:403` `_maybe_build()` shells
  `build_command` at module start when the executable is missing. 12 modules declare it. This is the
  pattern to copy for Python extras.
- **Lazy registries.** `all_blueprints.py` maps name → `"module:attr"`; `get_all_blueprints.py:47`
  imports on demand. `adapter_registry.py:39` `LazyAdapterRegistry` reads manifests without importing.
- **Platform-aware wheel resolution.** `dim::util::compat::check_extras_compat` against an embedded
  table keyed `linux_aarch64_min_glibc`. Right place to extend; today it receives nothing about the board.
- **Robot discovery, for Go2.** `landiscovery.py:106` multicast probe returns serial + ip + iface + mac.
- **A docker install path in dim.** `dim::docker::{detect_payload, get_latest_image, run_docker_mode}`.
  Never inspected. A working 15.2 GB `dimos-g1-exclusive-dev` image is already on the robot.
- **Containers work on this board.** docker 24.0.7 + nvidia runtime; `ubuntu:22.04` with
  `--runtime nvidia` gets CUDA (`cuInit=0`, `device0=Orin`).

## Architecture for one-click

```
dim setup                          dimos run <blueprint>
  |                                   |
  |- probe.board  -> BoardRecord      |- name -> "module:attr"   (nothing imported)
  |     /etc/nv_tegra_release         |
  |     /proc/device-tree/model       |- read `requires` from the registry row
  |     /usr/local/cuda               |
  |                                   |- missing extra? install it now
  |- probe.robot -> candidate         |
  |                                   |- import module
  |- doctor(board, robot)             |
  |     pass / fixable / blocked      |- native missing? _maybe_build   (EXISTS)
  |                                   |
  |- install(profile)                 |- start
```

Detection proposes, the operator confirms. Nothing auto-picks a robot.

**Robot detection must live in `dim`, not dimos.** dim is a static-musl Rust binary and runs before
Python 3.12 exists — the robot's only interpreter at that point is 3.8.10.

**Do not key robot family on `192.168.123.x`.** Verified on the G1: `.164` is the Jetson's own eth0,
and `.161` — dimos's Go2 default (`test_connection.py:148`) — is `REACHABLE` on this G1 too.

## Built: board + robot detection, preflight, conditional install

Branch `fix/jetson-non-interactive` in `dimos-helm`, 8 commits, +293/-10 across 10 files.
27 tests pass (4 new). Cross-built aarch64-musl and run on the G1.

`src/util/robot.rs` is new: `BoardRecord::detect` reads `/proc/device-tree/model` and
`/etc/nv_tegra_release`; `detect_robot` reads the vendor install directory and SDK example set and
returns a model, a family, a blueprint, and the evidence for each. Filesystem only — no network,
no vendor daemon, safe to run before every setup.

Bare `dim setup`, no flags, from `/` on the robot:

    Board:    NVIDIA Orin NX Developer Kit (L4T r35.3, CUDA 11.4)
    Robot:    g1plus_pc4 (humanoid) -> unitree-g1
    library install -> /home/unitree/dimos

Three behaviour changes fall out of that record:

- **Install by default on a robot.** The old `no_dimos` default existed to avoid installing to a
  surprising path (`<cwd>/my-dim-app`). A detected robot answers that objection, so the install
  runs and lands in `$HOME/dimos` rather than wherever the operator happened to `cd`.
- **Preflight.** `install_blockers` refuses up front instead of dying part-way through a multi-GB
  install. `MIN_DISK_GB = 12`, from the measured footprint: 3.9 GB project + 5.3 GB uv cache +
  1.1 GB nix.
- **Blueprint proposed, not chosen.** An unrecognised model returns `None` rather than a guess.

## Dependencies on run

`get_all_blueprints.py` now catches `ModuleNotFoundError` at the import seam, installs the extra
that ships the missing module, and retries. `uv sync --extra` in a source checkout,
`uv pip install "dimos[extra]"` against an installed wheel. `DIMOS_NO_AUTO_INSTALL=1` opts out.

The mapping is import name to extra, not blueprint to extras — which is why this needs no change to
the generated registry. An import no extra provides raises exactly as before rather than guessing.
torch resolves to `perception`, via `transformers[torch]`.

Branch `feat/on-run-extras` off dimos `main`, +85/-2 across 2 files. ruff and mypy clean, 6 tests
pass. **The install path itself has never executed** — the only unmapped-and-absent module in either
environment was `cupy`, and triggering a CUDA download proves nothing about the mechanism.

Deliberately on its own branch: the fiducial PR branch is untouched.

## The full flow, on the G1

    Board:    NVIDIA Orin NX Developer Kit (L4T r35.3, CUDA 11.4)
    Robot:    g1plus_pc4 (humanoid) -> unitree-g1
    ●  running diagnostics...
      +  network: HTTPS to pypi.org OK
      +  kernel: rmem_max = 67108864 (OK)
      +  CUDA: 11.4 (tegra, no nvidia-smi)
    ●  library install -> /home/unitree/dimos

## Ranked

| # | Work | Effort |
|---|---|---|
| 1 | Non-TTY sudo (askpass / `sudo -S`) for the Nix and apt stages | 1 d |
| 2 | Install DimOS by default; keep `--no-dimos` | 0.5 d |
| 3 | Loud extras resolution; error on an empty spec | 0.5 d |
| 4 | GPU probe: `/usr/local/cuda` + `/etc/nv_tegra_release`, not `nvidia-smi` | 0.5 d |
| 5 | `dimos doctor <blueprint>` — turns "installed" into "can run" | 2 d |
| 6 | Board record threaded into `check_extras_compat` | 2 d |
| 7 | Robot detection in dim | 3 d |
| 8 | Extras column on the registry + lazy install at that seam | 5 d |

Item 1 is the only thing between here and an unattended install. The jetson-prompt half is done.

## Unverified

- The static TLS crash. Never reproduced.
- Whether a Jetson CUDA torch wheel would trip the surplus. No such wheel exists to test.
- Whether CPU-only torch is fast enough for the perception blueprints. Not benchmarked.
- Whether `--dry-run` honors the Nix stage. Two agents disagree.
- No blueprint was ever executed. All robot evidence is install-time and import-time only.

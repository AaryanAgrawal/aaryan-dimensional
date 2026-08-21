# simplify-dios — what does not belong in a package manager + robot provisioner

Read-only audit of `/home/dimos/aaryan-dimensional/workspace/dimos-bios` at commit `7b17725`.
Goal against which every file was judged: *a very lightweight and simple dios repo* — a package
manager for dimos plus `dios infect --with <recipe>`, that must never fail.

Everything labelled VERIFIED I ran. Everything labelled HYPOTHESIS I could not execute. Nothing in
the repo was modified; `git status` is clean.

## How I verified

- Toolchain: nix rust 1.97.0, `CARGO_TARGET_DIR=/tmp` (repo untouched).
- `cargo build`: clean, **0 warnings**. Binary `dios` built.
- Ran the built binary under an isolated `HOME=/tmp/dios-audit-home`.
- Line counts from `wc -l`. Call graphs from `grep` over `src/`.

Today the crate is **13,986 lines** of Rust across 34 files (plus a 32-line stray `test_sudo_env.rs`
at the root that is not in the build).

---

## Verdict table

| File | Lines | Verdict | One-line reason |
|---|---|---|---|
| `src/commands/init.rs` | 343 | **delete** | Dead. Not declared as a module; cannot compile against today's config. |
| `src/commands/new_app.rs` | 348 | **delete** | Dead. Same — references `cfg.init_completed`, a field that no longer exists. |
| `src/commands/webserver.rs` | 899 | **delete** | Unauthenticated RCE; reads dead config keys; sole reason ~30 crypto crates are linked. |
| `src/commands/service.rs` | 174 | **delete** | Zero callers, setup never registers it, superseded by `desktop.rs` (per-user, no sudo). |
| `test_sudo_env.rs` + `test_sudo_env.sh` | 32 + shell | **delete** | Scratch experiment at repo root, not in the build. |
| `src/commands/desktop.rs` | 1995 | **move out** | The desktop is a *package* dios installs (downloaded from R2), not code dios contains. |
| `src/docker.rs` | 244 | **keep, gated** | Dead on normal builds, but the only offline-install path for China. Keep as that, explicitly. |
| sysctl / `is_systemd` / hostname probes | — | **simplify** | One fact with three or four homes — the CUDA-bug shape, still present. |

**A lightweight dios**, deleting only the four dead/unsafe items (init, new_app, webserver, service)
and leaving desktop in place: **12,222 lines**, and ~30 fewer crates in the tree.
Extracting the desktop as a package on top of that: **~10,227 lines** — 27% smaller than today.

---

## The four deletions, with evidence

### 1. `init.rs` + `new_app.rs` — 691 lines, dead, do not even compile (delete)

VERIFIED. Neither file is declared as a module anywhere:

```
$ grep -rn "mod init\|mod new_app" src/     # → nothing
src/commands/mod.rs:10: // NOTE: init.rs and new_app.rs exist but are not wired up yet
```

They are not merely unused, they are stale against the current code. `new_app.rs:10` does:

```rust
let cfg = config::load()?;
if !cfg.init_completed { ... }
```

but `config::load()` returns `serde_json::Value`, which has no `.init_completed`. These files are
from an older config design and would fail to build if wired in. There is no interface to preserve —
no `dios init`, no `dios new` command exists in `cli.rs`. **Pure delete, zero risk.**

### 2. `webserver.rs` — 899 lines (delete)

Three independent problems, each sufficient on its own.

**(a) It advertises config keys nothing reads.** VERIFIED.

```
$ grep -rn '"webserver\.' src/          # → nothing. No code reads webserver.*
```

Every accessor in the file reads the `desktop.*` namespace (`desktop.port`, `desktop.on_boot`,
`desktop.host`, `desktop.ssl_cert`, `desktop.ssl_key`). But `dios webserver --help` says:

```
desktop.port      number — listen port (default 1024)     ← the code
--port <PORT>     defaults to config webserver.port, then 8088   ← the help lies
enable  # start on boot (config webserver.enabled=true)          ← no such key
```

`webserver.enabled`, `webserver.port`, and the default `8088` appear only in help text. The real
default is `desktop.port = 1024`. Three provably-false help lines.

**(b) It collides with the desktop.** VERIFIED by running it.

```
$ dios config set desktop.port 8791
$ dios webserver status
  bind: 127.0.0.1:8791     ← setting the *desktop* port moved the *webserver*
```

The webserver and the desktop share port 1024 and the entire `desktop.*` config block. There is no
port setting where both can run. `dios webserver disable` flips `desktop.on_boot=false`, which is
also the desktop's boot switch. The README calls this a "boot fallback for the desktop"; it cannot
be a fallback for something it cannot coexist with.

**(c) Unauthenticated remote code execution.** VERIFIED end to end against the running server.

No route checks any credential or `Origin`:

```
/healthz        -> 200
/api/status     -> 200
/api/config     -> 200   (GET dumps full config)
/api/blueprints -> 200
/api/runs       -> 200
```

`POST /api/config` takes `{"updates": {...}}` with no auth, no CSRF token, and `Content-Type:
text/plain` (a simple request — a browser form on any website reaches it). It writes any dotted key,
including `dimos.dir`. `POST /api/launch` then runs `source <dimos.dir>/.venv/bin/activate && dimos
run <name>`. Chain them:

```
$ curl -X POST .../api/config -H 'Origin: https://evil.example' \
      --data '{"updates":{"dimos.dir":"/tmp/pwned-dimos"}}'      → {"ok":true}
$ curl -X POST .../api/launch --data '{"name":"pwn-bp"}'          → {"ok":true,"pid":...}
→ /tmp/RCE_PROOF_1786347111 appeared on disk.   CODE EXECUTION CONFIRMED
```

Default bind is `127.0.0.1`, so the direct threat is any website the operator visits driving these
requests from their browser — the server has no defense against it. If anyone ever sets
`desktop.host = 0.0.0.0`, it is open to the LAN.

**Cost of keeping it:** `webserver.rs` is the *only* file that imports `rustls`, `rustls_pemfile`,
`rustls_rustcrypto`. VERIFIED — deleting it lets you drop 3 direct dependencies and ~30 transitive
crypto crates (`aes`, `sha2`, `ecdsa`, `p256`, `p384`, `rsa`, `chacha20`, `ed25519`, `x25519`, `der`,
`spki`, `pkcs*`, `poly1305`, `ghash`, …) from a 238-crate tree. This is the single biggest
"lightweight" win available.

**Interface note:** `dios webserver` is a documented public command (README, AGENTS.md). No script
in this repo calls it (`install.sh`, `run/*`, docs invoke it nowhere). It is a documented interface,
not a code dependency — removing it breaks a customer script only if one exists that we cannot see.
Given it is an unauthenticated RCE, that is the right trade.

### 3. `service.rs` — 174 lines (delete)

VERIFIED. Its only callers are the CLI dispatcher in `main.rs`. `dios setup` never calls it:

```
$ grep -rn "service::" src/setup/   # → nothing. setup wires only desktop::
```

It writes a `sudo`-owned systemd unit (`/etc/systemd/system/dim.service`) and persists a
`ServiceState` via `paths::service_state_path()` — which is **written and never read** (VERIFIED:
the only `service_state_path` reference besides its definition is the write in `service.rs:111`).
`desktop.rs` already manages a boot service per-user (launchd on macOS, `systemctl --user` on Linux)
with **no sudo**, and it is what setup actually uses. `service.rs` is the older, root-owned, macOS-
incapable version of a job already done better elsewhere. Jeff's read that it can go matches the code.

**Interface note:** same as webserver — `dios service` is documented in README/AGENTS.md, invoked by
no script here. Documented interface, not a code dependency.

### 4. Root scratch files (delete)

`test_sudo_env.rs` (32 lines) and `test_sudo_env.sh` sit at the repo root, are not referenced by
`Cargo.toml` or `build.rs`, and probe how `sudo` passes env vars. Development scratch. Not shipped,
not built.

---

## `desktop.rs` — 1995 lines, the largest file (move out, don't delete)

Under "dios is the package manager," the desktop is the clearest example of a **package**, not
part of the manager. VERIFIED from the code: `desktop.rs` downloads a `deno compile` binary from R2
(`static_data.json` → `pub-…​.r2.dev`, `desktop_version: 0.1.1`) via `curl` and unpacks it into
`~/.dimos/data/desktop`. The UI binary is not in this repo. dios ships 1995 lines of Rust to manage
a versioned artifact it fetches at runtime — which is exactly what `dios install` already does for
every other package (`pkgs.installed.<name>`, clone-or-symlink into `pkgs.dir`).

Honest caveat: this is a **product decision, not a free delete.** Today `desktop.rs` is load-bearing —
`setup/mod.rs:564` calls `desktop::setup_configure`, and `dios install` exists to feed apps to the
desktop. Extracting it means giving the desktop its own recipe/package and having setup install it
like anything else. That is the move that makes dios "just a package manager." I flag it as the
biggest simplification with the biggest blast radius; treat it as its own project, not a cut to
approve tonight.

## `docker.rs` — 244 lines (keep, but label it)

VERIFIED. It is entered only when the running binary has a `DIMOSPAK` payload appended
(`main.rs:27`); a normal `cargo build` has none, so on every ordinary invocation `detect_payload()`
returns `None` and this code never runs. The release review calling it "dead" is right *for normal
builds*. But it is the self-extracting offline installer — the best China install path we have. Keep
it, and say so in a comment at the top, so the next reviewer does not delete it as dead. If you want
it out of the core binary, it belongs in the packaging pipeline (`run/pack_docker`), not `src/`.

---

## Simplifications — one fact, several homes (the CUDA-bug shape)

The CUDA double-probe is already fixed: `doctor.rs` reads `rec.system.cuda_version` from the single
`MachineRecord` instead of re-running `nvidia-smi` (`doctor.rs:177` even documents why). Good. The
same shape survives in three other places:

**1. The LCM receive-buffer value `67_108_864` lives in three independent copies.** VERIFIED.

```
src/setup/sysconfig.rs:9   RECOMMENDED_SYSCTL  net.core.rmem_max = 67_108_864   (writes it)
src/docker.rs:148          its own literal     net.core.rmem_max = 67_108_864   (writes it again)
src/commands/doctor.rs:209 MIN_RMEM_MAX        67_108_864                       (checks it)
```

Three writers/checkers of the same kernel tunable. Change the threshold in one and doctor passes a
machine that setup would still fix, or vice versa. Collapse to one `const` in a shared module.

**2. `is_systemd()` is copy-pasted in three files.** VERIFIED.

```
src/commands/service.rs:15     std::path::Path::new("/run/systemd/system").exists()
src/commands/webserver.rs:83   std::path::Path::new("/run/systemd/system").exists()
src/commands/uninstall.rs:99   Path::new("/run/systemd/system").exists()
```

Deleting service.rs and webserver.rs removes two of the three for free; move the survivor to `util`.

**3. `hostname` is shelled out in three places** (`doctor.rs:338`, `webserver.rs:862`,
`desktop.rs:1706`). Minor, but it is the same probe three ways. One `util::hostname()` covers it
(and one of the three dies with webserver).

---

## Unknowns I could not resolve

- Whether any **customer script** outside this repo calls `dios service` or `dios webserver`. Both
  are documented public commands; neither is invoked by anything in the repo. I cannot see customer
  machines. This is the only thing standing between "delete" and "delete after a deprecation note."
- Whether the R2 desktop download is the intended long-term shape or a stopgap — decides whether
  "move desktop out" is a real project or a rewrite.
- `docker.rs`'s actual use in the field (China offline installs). It is dead on normal builds by
  construction; its value is entirely in the packaging path I could not exercise here.

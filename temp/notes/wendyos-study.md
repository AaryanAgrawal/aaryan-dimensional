# WendyOS, read closely

A study of the `wendy` CLI as a shipped design, done by running it. Written for dios, which is
becoming one binary: a package manager for dimos plus `dios infect --with <recipe>`.

The reason to look at wendy at all is that they already shipped the two things we are about to
build. They have a target registry (`wendy device info`, `hardware list`, `discover`) and they
have a per unit declarative manifest that a third party writes (`wendy.json` with entitlements).
Both are worth copying in parts. Both also contain a mistake we would otherwise make ourselves.

## Method

Everything below was run, not read, unless it is marked otherwise.

```
wendy version:  2026.08.07-174446   (binary 32,111,760 bytes, statically linked Go, stripped)
CLI state:      ~/.wendy/{config.json, milestones, analytics_id}
walked:         86 help pages recursively + 30 hidden commands probed by name
scaffolded:     8 projects into /tmp/wstudy/{a..i}
agent installer: /tmp/wendy-agent.sh, 725 lines, downloaded and read, NOT executed
```

Nothing was installed. Runs that would write CLI state used `HOME=/tmp/wendyhome` so Aaryan's
`~/.wendy` was left alone. The one exception is the very first `wendy --help`, which is read only.

Where I say "read, not run" I am quoting the docs and JSON Schema that ship *inside* the binary.
`strings` on it yields 105,347 lines, including the complete `wendy.json` JSON Schema, every CLI
reference page, and the protobuf descriptors. That is itself a finding, see "Ship the schema
inside the binary" below.

---

## 1. The command surface

The recursive walk found 86 help pages. Probing by name found ~30 more that are hidden from
`--help`: `watch`, `os` (7), `auth` (8), `discover`, `json` (3), `mcp` (3), `completion` (6),
and `device {get-default, sync-time, os-logs, telemetry-stream, version, enroll, usb-setup}`.
The real surface is around 140 leaf commands.

The top level groups them by *what you are doing*, not by noun, and that is the first thing worth
stealing:

```
Develop & Deploy:  init  run  install  tour
Manage:            project  device  fleet
Cloud:             cloud
Settings:          analytics  cache  help
```

Cobra's default is one flat `Available Commands:` list. Four named sections with the verbs you
reach for first at the top is a deliberate edit, and at 11 visible entries it still fits on a
screen. Their `device` group does the same thing one level down: `Common Commands` /
`Device Management` / `Hardware`.

### Device local versus cloud

This matters because we are not doing cloud.

| Cluster | Pages | Needs cloud? |
|---|---|---|
| `device ros2 *` | 17 | no |
| `device *` (everything else) | 46 | no, except `enroll`, `unenroll`, `rename` |
| `fleet *` | 8 | yes (group = a tag on a cloud Asset) |
| `cloud *` | 8 | yes |
| `auth *` | 8 | yes |
| `os *`, `install`, `discover`, `json`, `cache`, `analytics`, `completion`, `mcp` | ~25 | no |
| `init`, `run`, `watch`, `project *` | ~6 | no |

So roughly 27 of ~140 commands are cloud only, and they are cleanly separable — they live under
`cloud`, `fleet`, `auth` plus three `device` verbs. Nothing in the local path imports them. That
separation is real and it is the reason the LAN half of this tool is usable standalone, which is
exactly the half we want.

Two hedges they built for people without cloud, both worth noting:

- `fleet run --lan` and `fleet apps --lan` resolve a device group over mDNS with a glob on device
  names (`camera-*`) and no cloud session at all. Fleet targeting without a fleet service.
- `wendy auth login --api-key --cloud-grpc host:port` points at a self hosted `pki-core`. The
  cloud is swappable, not welded in.

---

## 2. The scaffold, dissected

```
$ wendy init --app-id demo-app --target wendyos --language python \
    --entitlement gpu,usb,persist --persist-name demo-data --persist-path /data \
    --assistant skip --git-init no
Created wendy.json for demo-app
Created pyproject.toml, source package, and Dockerfile (using uv)
Your project is ready! Run wendy run to build and deploy.
```

Four files, about 40 lines of content total.

```
demo_app/__init__.py   17 lines: a main() that installs SIGINT/SIGTERM handlers and prints hello
pyproject.toml          9 lines: name, version, requires-python, empty deps, one [project.scripts]
Dockerfile             13 lines: uv base, copy pyproject + uv.lock*, uv sync --frozen, CMD uv run
wendy.json             22 lines: the whole declaration
```

`wendy.json` from that command:

```json
{
  "appId": "demo-app",
  "version": "0.1.0",
  "platform": "linux",
  "language": "python",
  "entitlements": [
    { "type": "network" },
    { "type": "gpu" },
    { "type": "usb" },
    { "type": "persist", "name": "demo-data", "path": "/data" }
  ],
  "python": {}
}
```

`--target wendyos` writes `"platform": "linux"`. The flag name and the file value are deliberately
different: `wendyos` is the thing the user is thinking about, `linux` is the thing the builder
needs. The schema accepts `wendyos` as an alias and resolves it before building.

### The diff

I scaffolded four and diffed them.

```
a: --entitlement gpu,usb,persist --persist-name demo-data --persist-path /data
b: --entitlement gpio,i2c --gpio-pins 17,27,22 --i2c-device /dev/i2c-1
c: --all-entitlements (+ the field flags gpio/i2c/persist require)
d: --target wendy-lite --no-extra-entitlements
```

`diff a/Dockerfile b/Dockerfile` differs in exactly one line, the `CMD` module name. The
pyprojects are identical modulo the app name. The source files are identical modulo the app name.

**The entitlements are the only thing that differs.** Requesting GPU, USB and a persistent volume
versus requesting GPIO pins 17/27/22 and an I2C bus changes nothing about the generated code, the
build, or the container definition. It changes four lines of JSON.

That is the design, and it is the single most important thing in this study. The declaration of
what hardware an app needs is metadata consumed at deploy time by the thing that constructs the
container. It is not code generation, it is not a template variable, it does not leak into the
build. A third party writing an app never writes a device path, a cgroup rule, a group membership,
or a CDI hook. They write `{ "type": "gpu" }`.

Scaffold `c` with `--all-entitlements` produces 11 entitlements: network, gpu, bluetooth, usb,
gpio, spi, i2c, audio, camera, input, persist. Same four files.

Scaffold `d` (`wendy-lite`, the ESP32 WASM target) produces `Package.swift` + `Sources/lite-app/
main.swift` + `wendy.json` and drops the `python` block entirely. The manifest stays the same
shape across a Python container target and a Swift on ESP32 target. `platform` selects the
backend, everything else is stable.

### The entitlement vocabulary

`wendy json schema` prints the full JSON Schema (20,178 bytes). Parsed:

```
network        req=-              params=mode,serviceCIDR,ports
bluetooth      req=-              params=mode
video          req=-              params=mode,allowlist      (deprecated -> camera)
gpu            req=-              params=-
persist        req=name,path      params=name,path
audio          req=-              params=-
camera         req=-              params=mode,allowlist
usb            req=-              params=-
i2c            req=device         params=device
gpio           req=-              params=pins
spi            req=-              params=-
input          req=-              params=-
serial         req=device         params=device
display        req=-              params=-
notifications  req=-              params=-
admin          req=-              params=-
build          req=-              params=-
```

17 variants. 11 of them take no parameters at all. Six take one or two, and only three have a
required parameter. The vocabulary is short and most entries are a bare noun.

The `oneOf` per type with `additionalProperties: false` is what makes this work. `{"type":"gpu",
"pins":[17]}` is rejected, not silently ignored. Each entitlement carries only the fields that
mean something for it.

What each grant actually does, from the docs embedded in the binary (read, not run):

- `gpu` — on Jetson: adds the app to the `video` group, injects NVIDIA CDI specs, sets CUDA env
  vars. On Raspberry Pi: exposes `/dev/vcio` for board telemetry. Explicitly hardware specific.
- `display` — `/dev/dri` with cgroup `rw` and no `mknod`, membership in `video` and `render`, plus
  the compositor's Wayland socket via `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR`. At most one per app.
- `audio` — mounts `/dev/snd`, ALSA permissions.
- `bluetooth` has two modes with different mechanisms: `kernel` adds `CAP_NET_ADMIN`/`CAP_NET_RAW`
  and seccomp filters for HCI sockets; `bluez` gives D-Bus access to the BlueZ daemon.
- `network` mode is an enum of five: `host`, `host-admin`, `none`, `bridge`, `mesh`. The schema
  says the implicit default (`host`) "is deprecated and will change to `bridge` in a future
  release", and encodes `if mode == mesh then serviceCIDR required else serviceCIDR: false`.
- `admin` — bind mounts the agent's unix socket into the container, unauthenticated, full local
  device control. The schema text says it outright: "the entitlement gated socket mount is the
  entire trust boundary".
- `build` — `CAP_SYS_ADMIN` plus the `unshare`/`clone(CLONE_NEWUSER)` syscalls, so a device can
  build images for itself. Labelled "Privileged equivalent: a container host escape surface."

Three of the seventeen (`display`, `admin`, `build`) carry an "at most one per app" constraint
enforced at validation. Two are explicitly marked as trust boundaries in the schema description
itself, so the warning travels with the schema into any editor that reads it.

---

## 3. The agent, enrollment, and how a device is addressed

`https://install.wendy.dev/agent.sh`, 725 lines. Structure:

```
1-50     re-exec under bash if invoked via sh, arg parsing (-y, -d DIR), usage
50-75    OS + arch detect, SUDO="" unless non-root
75-130   >>> wendy-install-shared  ... <<< wendy-install-shared
130-235  homebrew helpers, apt/dnf/yum install-or-upgrade helpers, confirm(), stage_enrollment()
235-370  macOS path (brew cask, or signed zip with codesign --verify before /Applications)
370-465  Linux package manager paths: apt repo, dnf/yum repo, pacman/AUR
465-720  no package manager fallback: tarball + systemd units written inline
720-725  verify, then stage_enrollment
```

Six things in it are worth having.

**The shared block is fenced and byte identical across two scripts.** The comment says so:

```
# Shared installer helpers. This block MUST be byte-identical in cli.sh and
# agent.sh (enforced by .github/scripts/install-scripts_test.sh).
```

Two curl-to-bash installers, one duplicated region, a CI test that diffs the region. No submodule,
no templating, no build step for a shell script. We have `install.sh` in dios already; if a second
one ever appears this is the answer.

**Version resolution has a fallback chain, and the reason is written down.**

```
resolve_version() = $WENDY_VERSION  ->  GCS manifest.json "latest"  ->  GitHub releases API
```

with the comment "so the mainstream install paths never call the rate-limited GitHub API". The
GitHub API is the *fallback*, not the primary. `manifest_latest` greps for `"latest"` specifically
and not `"latest_nightly"`, using `head -1` and a sed capture, so it needs no `jq`.

**`|| true` inside a command substitution, explained.**

```bash
# `|| true` keeps a failed fetch (e.g. missing manifest) from tripping the
# script's `set -e` inside the command substitution, so we can fall through.
v="$(manifest_latest || true)"
```

**Secrets are written with `( umask 077; ... | tee )`, never a heredoc.**

```bash
( umask 077; printf '{"token":"%s","cloudHost":"%s"}\n' "$token" "$cloud_host" \
    | $SUDO tee /etc/wendy-agent/enrollment.json >/dev/null )
$SUDO chmod 600 /etc/wendy-agent/enrollment.json
```

The comment says the file is created 0600 from birth and "the chmod below is a defensive backstop,
not the sole protection." That is the correct pattern and the correct comment.

**macOS install verifies the signature before copying, not after.** `codesign --verify --deep
--strict` on the extracted bundle, refuse on failure, with a comment explaining that Gatekeeper's
first launch check happens "only after the bytes are already on disk". Notarization via `spctl` is
downgraded to a warning because an unstapled build should still install. Two checks, two different
severities, both justified in the code.

**Extraction uses `ditto`, not `unzip`**, "confines writes to the destination directory rather than
honoring archive path-traversal entries the way a bare `unzip` might."

### What the agent ends up being

```
binary      /usr/local/bin/wendy-agent
unit        /usr/lib/systemd/system/wendy-agent.service
              After=network-online.target dbus.service containerd.service
              Requires=containerd.service
              Restart=always  RestartSec=2  LimitNOFILE=65536
              EnvironmentFile=-/etc/default/wendy-agent
env         /etc/default/wendy-agent      (WENDY_NETWORK_MANAGER=auto|connman|networkmanager|force-*)
config      /etc/wendy-agent/config.json  (0600, seeded with "{}")
enrollment  /etc/wendy-agent/enrollment.json (0600, only if a token was staged)
state       /var/lib/wendy-agent/storage
volumes     /var/lib/wendy/volumes
mDNS        /etc/avahi/services/wendy-agent.service  ->  _wendyos._udp  port 50051
```

Plus two more systemd units for a local containerd registry (`wendyos-dev-registry-import` runs
once, guarded by `ConditionPathExists=!/var/lib/wendyos/dev-registry-imported`, and
`wendyos-dev-registry` runs the registry container on `0.0.0.0:5000`). The one shot import guarded
by a sentinel file is a clean idiom.

### Enrollment

Two paths, and only one of them is a real enrollment.

*Pre-seed at install:* `WENDY_ENROLLMENT_TOKEN` + `WENDY_CLOUD_HOST` in the environment cause
`stage_enrollment` to drop `/etc/wendy-agent/enrollment.json` and `systemctl try-restart
wendy-agent`. The agent self enrolls on startup. The docs say the token is minted with a 1 hour
TTL and embedded in the copy-pasteable command that `wendy install` prints.

*Post hoc:* `wendy device enroll` creates an enrollment token from the CLI's stored auth session
and calls `WendyProvisioningService/StartProvisioning` on the device to install mTLS certs.
`wendy device unenroll` calls `Unprovision`, which deletes the certs and restarts the agent into
unprovisioned mode, then revokes the certs and deletes the cloud asset.

Without a token, nothing happens. The agent just runs and advertises itself. **A device is fully
usable unenrolled** — that is why the whole LAN half of the CLI works with no account.

### Addressing

Four mechanisms, in this order of precedence:

1. `--device <host>` global flag, accepting `host` or `host:port`. Help text: `Device address,
   e.g. mydevice.local:50051 or 192.168.1.10:50051`. Port defaults to 50051.
2. `wendy device set-default <host>` writes `defaultDevice` into `~/.wendy/config.json`, and
   `get-default` (hidden) reads it back.
3. mDNS. `_wendyos._udp` on port 50051, advertised by an avahi service file with
   `<name replace-wildcards="yes">%h</name>`. `wendy discover` browses it. `fleet --lan` globs
   over the names it returns.
4. USB NCM — enumerates host adapters whose name or description contains "wendy"
   (case insensitive; `/sys/class/net` on Linux, `SCNetworkConfiguration` on macOS, PowerShell
   `Get-NetAdapter` on Windows).

The transport is gRPC on 50051 in both directions. `strings` gives the full method set: 14 services
(`WendyAgentService`, `WendyContainerService`, `WendyVideoService`, `WendyAudioService`,
`WendyTelemetryService`, `WendyProvisioningService`, `WendyShellService`, `WendyFileSyncService`,
`WendyDeviceInfoService`, `ROS2Service` in v2, plus cloud services). The CLI is a thin client over
that; almost every `device` subcommand is one RPC.

There is device identity pinning. The binary contains `reading pin store: %w`, `writing pin store:
%w`, and `Device %q now presents a different identity than the one you pinned.` I did not find
where the pin store file lives without a real device to enroll, so treat the mechanism as read
only: they do trust on first use on the device's public key, which is the `public_key` field of
`GetDeviceInfoResponse` below.

---

## 4. The device model

This is the part we should study hardest, because our target registry has to hold roughly this and
theirs has been in the field.

### `GetDeviceInfoResponse`, from the protobuf descriptor in the binary

```
version            string     agent version
os_version         string?    optional
cpu_architecture   string
public_key         string?    optional        <- the identity that gets pinned
featureset         repeated string            <- open ended capability flags
device_type        string?    optional
has_gpu            bool?      optional
gpu_vendor         string?    optional
jetpack_version    string?    optional
cuda_version       string?    optional
gpu_arch           string?    optional
disk_used_bytes    uint64?    optional
disk_total_bytes   uint64?    optional
mem_total_bytes    uint64
cpu_count          uint32
partitions         repeated DiskPartition

DiskPartition:  mountpoint  filesystem  device  used_bytes  total_bytes
```

Ten of sixteen fields are proto3 `optional`, confirmed by the synthetic `_field` oneofs at the end
of the descriptor. The docs are explicit about why:

> Each is omitted from both the human-readable output and the JSON map when the agent does not
> report it (e.g. non-GPU devices or older agents), so consumers should treat every field as
> optional.

**Absent, not zero, not "unknown".** A device with no GPU has no `gpu_vendor` key. A device whose
agent is too old to read `/proc/meminfo` has no `memTotalBytes` key. There is no sentinel value to
misread. The one place they do use a sentinel is human-readable output only: `gpuVendor` renders as
`unknown` when a GPU is present but the vendor is unreported, and that distinction (GPU exists,
vendor unknown) is genuinely different from absent.

`featureset` is the escape hatch: a repeated string of capability flags. It is how a version
independent feature check works without a version comparison. From the docs:

> A WendyOS target must also advertise the `wendyos-update` featureset flag; without it, the update
> is rejected with a dedicated error.

and the error itself:

> `This WendyOS image does not support OTA updates because the wendyos-update engine was not found
> on the device. Reinstall or upgrade to a WendyOS image with OTA support.`

That is the right shape. Do not ask "is the agent newer than 0.14"; ask "does it advertise the flag
for the thing I am about to do".

### `HardwareCapability` — four fields, and that is all

```
category      string
device_path   string
description   string
properties    map<string, string>
```

`ListHardwareCapabilities` takes an optional `category_filter`. The help text names the categories
in use: `gpu, usb, i2c, gpio, camera` and elsewhere `audio, serial, storage, network, bluetooth,
input, display, can, spi`.

This is a deliberately open model. Every heterogeneous hardware fact on the device — a GPU, a
camera, an I2C bus, a USB device — is one row of `{category, device_path, description, properties}`.
No per category struct. No union. No schema migration when a new kind of hardware shows up. The
typed part is exactly the three fields every capability has, and everything vendor specific lives
in a string map that no consumer is required to understand.

Set that against the *other* place they model the same territory, `GetDeviceInfoResponse`, which
has six dedicated GPU fields (`has_gpu`, `gpu_vendor`, `gpu_arch`, `jetpack_version`,
`cuda_version`, plus `featureset`). Both models exist in the same binary. The typed one is for
facts that drive decisions the CLI itself makes (can I do an OTA, is this arch compatible, is there
enough disk). The open one is for the inventory nobody wants to keep up with. Splitting on *who
consumes it* is the right seam, and it is the seam we should copy.

### The discovery record

`wendy discover --timeout 5s --json`, run here for real:

```json
{
  "usbDevices": [],
  "lanDevices": null,
  "bluetoothDevices": null,
  "ethernetDevices": null,
  "externalDevices": [
    { "id": "local", "displayName": "This PC", "providerKey": "local",
      "isWendyDevice": false, "os": "linux", "cpuArchitecture": "amd64" }
  ]
}
```

Two things. The top level is bucketed **by transport**, not a flat list, because a device found on
two transports is genuinely two facts about one device — the interactive table's Type column shows
`USB, LAN` for that case. And every record carries `providerKey`, so discovery is a set of
pluggable providers and `local` (this machine) is just one of them. The local run targets (this PC,
Docker/OrbStack, Apple Container) are providers indistinguishable in shape from a real robot.

The default hides local targets from the human table but `--json` always includes them, "so scripts
and MCP callers continue to receive the full set". Human output is filtered for signal, machine
output is complete. Different audiences, different defaults, stated in the docs.

### Where device facts live

Nowhere, on the CLI side. There is no device cache in `~/.wendy`:

```
$ ls ~/.wendy
analytics_id  config.json  milestones
$ cat ~/.wendy/config.json
{ "analytics": { "enabled": true } }
```

`config.json` after `set-default` gains exactly one key, `defaultDevice`. That is the whole
registry: a name. Every fact about the device is fetched live over gRPC each time, and the only
persisted thing is which device you meant. `wendy discover` re-browses mDNS on every invocation
(default 5s) and caches nothing.

For us that is a real decision to make rather than a thing to copy blindly. Wendy can do this
because the agent is always running and always answers. dios `infect` runs against a robot that
has nothing installed yet, so we cannot ask it what it is — which is exactly why
`src/infect/identify.rs` scores weighted probes instead. Their `Facts` is an RPC response; ours
(`facts/g1-handwritten.json`: `subnets`, `ping`, `open_ports`, `remote_files`, `ssh_banners`) is a
recorded probe pass. Same role, opposite direction.

---

## 5. UX details worth stealing, with the exact text

### Errors name the fix, in commands

```
$ wendy device info
✗ no device specified; use --device flag or set a default with 'wendy device set-default'
```

```
$ wendy device info            # default set to an unreachable name
✗ default device "other-robot" is set but could not be reached: dns: A record lookup error:
  lookup other-robot on 127.0.0.53:53: server misbehaving
  Confirm it with 'wendy device get-default'; change it with 'wendy device set-default' or
  clear it with 'wendy device unset-default'.
```

The template is: **what was tried, the raw underlying error verbatim, then every command that
changes the situation.** The DNS error is not swallowed or prettified — a `server misbehaving`
from systemd-resolved is a different problem from NXDOMAIN and the operator needs to see which.
Three next commands, because from that state there are exactly three sensible moves.

Enumerations list themselves:

```
$ wendy project entitlements add bogus
✗ unknown entitlement type "bogus"
Valid types: network, bluetooth, video, gpu, persist, audio, camera, usb, i2c, gpio, spi,
input, serial, mcp, display, notifications, admin, build
```

```
$ wendy init --language cobol ...
✗ invalid language "cobol" (valid: swift, python)
```

Array errors are indexed:

```
✗ invalid wendy.json: entitlement[4]: serial entitlement requires a device
✗ entitlement[2]: i2c device must be in i2c-N format, got "/dev/i2c-1"
```

`entitlement[2]`, the rule, and the offending value quoted. Other messages in the binary follow the
same form: `components[%q].discovers[%d]: as %q is not a valid environment variable name`,
`%s[%d]: network mode "mesh" requires a serviceCIDR`.

More of the same, pulled from the binary (read, not run):

```
Could not connect to device. Is it powered on and connected to the network?
  Resolving a .local name needs mDNS: ensure avahi-daemon is running and UDP 5353 isn't
  firewalled (e.g. 'sudo ufw allow 5353/udp'), or connect by IP.
  Or connect directly by IP: wendy device connect <ip>:50051
```

```
multiple devices match %q; use a more specific name
--central %q is ambiguous, matched %d devices (%s); name one exactly
device belongs to org %d; authenticate for that org with 'wendy auth login'
unenroll is destructive; pass --yes to confirm when not running interactively
architecture mismatch: device is %s but host is %s
This FROM forces linux/amd64 but the target device is arm64. It will run under QEMU
  emulation (slow) or fail to start. Use an arm64/multi-arch base image.
```

That last one is a build linter finding, and it is the model for a good diagnostic: what is wrong,
what will happen if you ignore it, what to do instead.

### Prompts fall back to flags, and the help page proves it

`wendy init --help` carries **nine** worked examples, and every one of them is a complete
non-interactive invocation. Not `wendy init [flags]` with a flag table underneath — nine copy-
pasteable command lines covering the nine shapes a user actually wants:

```
# Fully non-interactive WendyOS Python app with persist storage
wendy init \
  --app-id demo-app \
  --target wendyos \
  --language python \
  --entitlement gpu,usb,persist \
  --persist-name demo-data \
  --persist-path /data \
  --assistant skip
```

Every interactive prompt has a flag, and the pairs are visible in the flag names: the wizard asks
"which entitlements" → `--entitlement`; "any extra ones?" → `--no-extra-entitlements`; "git init?"
→ `--git-init yes|no`; "start Claude?" → `--assistant claude|codex|skip`. A parameterised prompt
gets a second flag for its parameter (`--gpio-pins`, `--i2c-device`, `--persist-name`,
`--persist-path`). Nothing is prompt-only.

When there is no TTY it says so instead of hanging:

```
$ wendy tour < /dev/null
✗ wendy tour requires an interactive terminal          (exit 1)
```

```
$ wendy init < /dev/null
✗ picker: could not open a new TTY: open /dev/tty: no such device or address
```

and for template variables specifically: `schema question %q requires input in non-interactive mode
(use --var %s=VALUE)` — the error tells you the flag *and* the key.

Non-tty output degrades to JSON automatically. `wendy discover` renders a live refreshing table on
a TTY and emits a JSON object into a pipe, with no flag. Same for `wendy cache list` and
`wendy cloud discover`.

### `-y` is not one thing

There are three distinct affirmations and they are not merged:

- `-y, --yes` on `wendy run` — "Automatically accept all interactive prompts". The blanket one.
- `--force` on `wendy install`, `apps remove`, `volumes remove` — skip the confirmation.
- `--yes-overwrite-internal` on `wendy install` — a separate flag whose only job is to authorise
  wiping a non removable drive. `--force` does not cover it.

The dangerous case gets its own name, so `--force` in a script cannot silently grow into "wipe the
laptop's internal SSD". `wendy device update -y` is scoped tighter still: it applies an available
OS update without prompting, and *without* `-y` a non-interactive run reports the available update
and does not apply it. Non-interactive defaults to the safe branch rather than erroring.

### stdout / stderr hygiene

Correct, and verified:

```
$ wendy discover --timeout 2s --json 2>/dev/null | python3 -c "import sys,json; json.load(sys.stdin)"
VALID JSON
$ wendy device info --device bogus.local --json 2>/dev/null   # -> nothing on stdout
$ wendy device info --device bogus.local --json 2>&1 >/dev/null
✗ dns: A record lookup error: ...                              # exit 1
```

Errors, the analytics banner, and the update nag all go to stderr. `--json` stdout stays parseable
even on failure, because on failure stdout is empty and the exit code is 1.

### The update nag prints the command

```
A new version of the Wendy CLI is available: 2026.08.10-054004 (you have 2026.08.07-174446)
Update with: curl -fsSL https://install.wendy.dev/cli.sh | bash
```

Both versions, then the literal command. It is throttled by a timestamp in config:

```json
{ "lastCLIUpdateCheck": "2026-08-10T07:30:48Z", "availableCLIUpdate": "2026.08.10-054004" }
```

The result is cached, so the nag prints on every invocation but the network call does not happen on
every invocation.

### `milestones` — the onboarding state machine

```
$ cat ~/.wendy/milestones
first_run
first_real_command
init_success
```

A newline delimited file of milestone names. This is how the CLI stops talking to you. On
`first_run` it prints the analytics notice and `New to Wendy? Run 'wendy tour' for a guided setup.`
Once `init_success` is recorded, that hint is gone. The docs say the ambient
"install shell completions?" prompt is suppressed the same way, either by completing the tour or by
dismissing it once.

It is the simplest possible mechanism — append a line to a file — and it is the difference between
a CLI that teaches you once and one that nags forever. Nothing in it needs to be structured. We
should have this on day one, because it is much harder to retrofit hints than to retrofit their
suppression.

### `tour`

`wendy tour` is a step-by-step flow through device discovery → Wi-Fi → provisioning → deploying a
sample → first steps. From the docs: "Where possible it prefills values automatically to reduce
manual entry. At the Wi-Fi configuration step, `wendy tour` attempts to detect the host machine's
current Wi-Fi network and prefill the SSID field." Strings in the binary: `Welcome to Wendy`,
`Let's get you set up from scratch`, `Enter when ready`, `4. Power on the`, `Detected: `.

The tour also installs shell completions as one of its steps. It is not a demo; it does real setup,
which is why finishing it silences the ambient prompts.

### Progress on long operations

Read, not run (no device here), but the strings show the vocabulary:

```
Reusing %s layer(s) already on device; chunking %s.
%d of %d services unchanged and already on device; skipping their build/push.
This incremental build took %s. A quick scan found %d build-config issue(s):
Waiting for the device to report its final status (QSPI programming can take several minutes)...
Waiting for agent to restart...
Device is not connected to WiFi — downloading artifact to serve locally...
Note: block map unusable (%v); flashing the full image.
Offline — using cached WendyOS %s; cannot confirm it is the latest build.
```

The pattern: say what is being skipped and why, name the slow thing before it is slow ("QSPI
programming can take several minutes"), and announce every degradation as a `Note:` that continues
rather than an error that stops.

### Success tells you the next command

```
Your project is ready! Run wendy run to build and deploy.
Hostname set to %s (mDNS: %s.local)
OS update applied; the device is rebooting. Reconnect once it is back online.
Enrollment token staged; the device will enroll on startup.
Device reset to unprovisioned state.
```

Plus ambient tips after a successful run:

```
Tip: Validate your wendy.json against the schema with 'wendy json validate'
Tip: Grant hardware access (GPU, camera, GPIO) via entitlements in wendy.json
Tip: Reach a device behind NAT by forwarding a port with 'wendy cloud tunnel'
```

Every success message either names the next command or states the new observable state
("the device is rebooting", "will enroll on startup"). None of them is just "Done."

### The MCP surface, and one tool in it

`wendy mcp serve` exposes 33 tools over stdio. I listed them by driving the JSON-RPC handshake:

```
device_connect device_disconnect device_info device_list device_set_default
hardware_capabilities container_{list,start,stop,delete,attach,stats}
wifi_{list,connect,disconnect,status,known_networks} bluetooth_{scan,connect,disconnect}
telemetry_{logs,metrics,traces} os_update os_update_status
provisioning_{start,status} cloud_{connect,discover,enroll_device,tunnel} run wendy_status
```

One of them is the idea worth taking:

```
wendy_status — Return current MCP session connection state and a plain-English suggested
               next step. Call this first
```

A machine readable "where am I and what should I do next". The human CLI encodes that in prose
inside error messages; the agent surface makes it a callable. If dios grows an agent surface, that
is the first tool to write, and `dios doctor` is already most of the way there.

Also note the MCP surface is **stateful** (`device_connect` / `device_disconnect` establish a
session) where the CLI is stateless (`--device` per invocation). They chose differently for the two
audiences rather than forcing one model on both.

### Ship the schema inside the binary

`wendy json schema` prints the full JSON Schema. `wendy json validate` validates a file against it.
Both work with no network and no device. The binary also embeds every CLI reference doc — I read
`docs/clients/wendy-cli/commands/device/info.md`, `docs/apps/wendy-json.md`, the debugging guides,
and the Claude skill definitions straight out of `strings`.

The schema is a real artifact: `$id: https://wendy.dev/schemas/wendy.json`, draft 2020-12,
`required: ["appId"]`, `additionalProperties: false` at top level and on every entitlement variant.
A user can put `"$schema"` in their `wendy.json` and get editor completion for entitlements.

For us: `dios infect schema` printing the recipe schema, and `dios infect validate recipes/g1`, are
each an afternoon and they make the recipe format writable by a third party without reading our
source.

---

## 6. Six bugs I hit, and what each one teaches

These are not nitpicks. Every one of them is a trap we are positioned to walk into.

**1. `wendy init` writes a `wendy.json` that `wendy run` rejects — using the example from its own
`--help`.**

```
$ wendy init --app-id edge-sensors --target wendyos --language python \
    --entitlement gpio,i2c --gpio-pins 17,27,22 --i2c-device /dev/i2c-1 --assistant skip
Your project is ready! Run wendy run to build and deploy.

$ wendy run
✗ invalid wendy.json: entitlement[2]: i2c device must be in i2c-N format, got "/dev/i2c-1"

$ wendy json validate
✗ entitlement[2]: i2c device must be in i2c-N format, got "/dev/i2c-1"
```

That flag value is copied verbatim from `wendy init --help`. Three sources of truth disagree: the
help example says `/dev/i2c-1`, the JSON Schema's description says `I2C device path (e.g.
"/dev/i2c-1")`, and the runtime validator demands `i2c-N`. The validator exists and is correct.
`init` simply does not call it.

**2. Same class: `entitlements add` writes a config that violates the schema's own `required`.**

```
$ wendy project entitlements add serial          # schema: required ["type","device"]
Added "serial" entitlement
$ wendy json validate
✗ entitlement[4]: serial entitlement requires a device
```

**3. Same class: `--app-id "bad id!"` violates `pattern: ^[a-zA-Z0-9._-]+$` and is written anyway.**

```
$ grep appId wendy.json
  "appId": "bad id!",
```

The lesson from all three: **every writer must call the validator before it writes.** They built
one good validator and then wrote three code paths that bypass it. In dios that means
`recipe::manifest::validate()` runs on write, not only on load, and the CLI examples in `--help`
are generated from, or tested against, the same fixtures the validator sees.

**4. Flags are validated after prompting.**

```
$ wendy init --app-id y --all-entitlements --entitlement gpu --assistant skip < /dev/null
✗ picker: could not open a new TTY

$ wendy init --app-id ii --target wendyos --language python --all-entitlements \
    --entitlement gpu --gpio-pins 17 --i2c-device /dev/i2c-1 ... < /dev/null
✗ --all-entitlements cannot be combined with --entitlement
```

The correct error exists. It only fires once enough *other* flags are present to get past the
prompts. Argument validation belongs before any I/O, interactive or otherwise.

**5. A first-run write race silently dropped the setting.**

```
$ HOME=/tmp/wendyhome wendy device set-default nonexistent-robot
[first-run analytics banner]
Default device set to: nonexistent-robot
$ cat /tmp/wendyhome/.wendy/config.json
{ "analytics": {...}, "lastCLIUpdateCheck": "...", "availableCLIUpdate": "..." }   # no defaultDevice

$ wendy device set-default nonexistent-robot     # second run, no banner
$ cat /tmp/wendyhome/.wendy/config.json
{ "analytics": {...}, "defaultDevice": "nonexistent-robot", ... }                  # now it sticks
```

Two code paths in one process read-modify-write the same JSON blob. On first run the background
update check finishes last and writes back a struct that never saw `defaultDevice`. It reproduces
only on the very first invocation, which is the worst possible time. `dios config` writes
`~/.dimos/config.json` the same way — worth checking whether anything else in the process writes
that file concurrently.

**6. Help and reality disagree in two more places.**

`wendy init --help` says `--language`: `python, swift, rust, node, or cpp`. Reality:

```
$ wendy init --language rust ...
✗ invalid language "rust" (valid: swift, python)
```

(`rust`/`node`/`cpp` are presumably template-only, but the flag help does not say so.) And the
error message from `entitlements add` lists 18 valid types including `mcp`, while the shipped
schema has 17 `oneOf` variants and no `mcp`. Two hardcoded lists.

---

## 7. What is over-built, given our scope

We are not doing containers, not doing cloud, not doing OS images. That deletes most of this.

**The whole cloud tier.** `cloud` (8), `auth` (8), `fleet` (8), `device enroll/unenroll/rename`.
About 27 commands, an mTLS PKI, an enrollment token service, a tunnel broker, an org/asset model
with roles. Their own hedges tell you it is optional: `fleet --lan` targets a device group over
mDNS with no cloud at all, and `auth login --api-key --cloud-grpc` points at a self hosted
pki-core. A robot is usable unenrolled. Skip all of it.

**The container plane.** `WendyContainerService` has 15 methods including `QueryChunks`,
`WriteChunks`, `QueryLayers`, `WriteLayer` — a content defined chunking protocol so a redeploy only
ships changed bytes, with an `--chunking auto|force|off` flag and a registry-push fallback. Plus a
containerd registry running on the device as a systemd unit with its own one-shot image import.
Genuinely good engineering for their problem. Our problem is `pip install` and a systemd unit on a
robot that already has a filesystem.

**OS images and flashing.** `wendy install`, `wendy os *`, A/B slot OTA with `tegrauefi`/`ubootenv`
connectors, rollback with retry counters and health commit, bmap accelerated flashing, T234
flashpacks, RCM recovery mode over USB, GPT partition validation. The `osUpdate` block in
`device info` alone is ~15 nested fields. We do not own the OS on a G1 or a Go2; JetPack 5.1.1 is
whatever Unitree shipped.

**The ROS 2 subsystem.** 17 subcommands, an agent-side sidecar container that joins the app's DDS
domain, `echo`/`hz`/`graph`/`bag record`/`lifecycle`/`component load`. The mechanism is elegant —
`wendy device ros2 *` needs no SSH and no `setup.bash` sourcing because the agent starts a CLI
sidecar in the right domain. But dimos is LCM, and we have `wendy device shell` equivalents already.

**Media plumbing.** `WendyVideoService/StreamVideo` (H.264 or VP8/WebM depending on device
capability), `WendyAudioService/StreamAudio` with a jitter buffer (`--buffer-ms`, default 30),
a real time VU meter, network camera credential storage. `wendy device camera view` opening a live
window from a robot is a great demo. It is not a package manager.

**The dashboard/TUI tier.** `device dashboard`, `device top` (2s refresh, per container CPU/mem/
GPU), the live `discover` table with 7 keybindings, OTLP logs/metrics/traces streaming. Nice, and
each one is a maintenance burden that competes with correctness.

**Multi-service and fleet manifests.** `services` maps, `dependsOn`, `isolation` modes,
`resources` limits, `components` with per-group placement and a `--central` device, `readiness`
probes, `hooks.postStart` with `openURL`/`cli`/`agent` variants. Our recipes already have
`[[step]]` with `phase`/`on`/`verify`, which is the same job at a tenth the surface. Do not grow it.

**`analytics` as a top-level group.** Three subcommands, a `~/.wendy/analytics_id` UUID, a
first-run notice, an env var override. For a tool at our stage the group is bigger than the
feature.

**One judgement call that went the wrong way for them but might go the right way for us:** the
`admin` and `build` entitlements. Both are documented as privileged-equivalent escape hatches
("the entitlement gated socket mount is the entire trust boundary", "a container host escape
surface"). They exist because the sandbox is real and someone eventually needs out of it. Our
recipes run as `sudo` over SSH — we have no sandbox to escape, so we get the expressive power for
free and the honesty for free too. Our `[entitlements]` block is a *declaration for the operator to
read*, not a mechanism. That is worth being explicit about in the recipe docs, so nobody mistakes
it for enforcement.

---

## 8. The call

Ordered by how much each is worth to us.

### Take this, exactly like this

**T1. Entitlements as inert declarative metadata, one flat list of `{type, ...params}` objects.**
Grounded in: `diff a/Dockerfile b/Dockerfile` differing by one line while the entitlement lists
differ completely. Our `recipes/g1/recipe.toml` already has `[entitlements]` with
`laptop`/`robot`/`network`/`writes`. Keep it inert, keep it out of step logic, keep the vocabulary
short. Their 17 types with 11 taking no parameters is the target size.

**T2. `oneOf` per entitlement type with `additionalProperties: false`.** From `wendy json schema`:
`{"type":"i2c"}` requires `device`, `{"type":"gpu"}` accepts nothing else. Reject
`{"type":"gpu","pins":[17]}` rather than ignoring the extra key. In TOML this is an untagged enum
with `deny_unknown_fields`, which serde gives us directly.

**T3. Absent means absent.** Every optional device fact is omitted from JSON rather than zeroed or
stringified as "unknown". Their docs state the rule and their proto encodes it with ten `optional`
fields out of sixteen. Our `Facts` should do the same — a robot we could not probe for open ports
has no `open_ports` key, not `[]`.

**T4. A `featureset` list of capability flags, checked by name, never by version comparison.**
Their `wendyos-update` flag gates OTA and produces a dedicated error naming the missing capability.
Cheaper and more honest than `if agent_version >= x`.

**T5. The error template: what was tried, the raw underlying error, then every command that fixes
it.** Verbatim from the default-device failure above. Note the raw `dns: A record lookup error:
lookup other-robot on 127.0.0.53:53: server misbehaving` survives intact; it is the only thing that
tells you your resolver is broken rather than the name being wrong. Our recipes' `[notes]` table is
the same instinct applied to known failure strings; this is the instinct applied to unknown ones.

**T6. Indexed array errors.** `entitlement[2]: i2c device must be in i2c-N format, got
"/dev/i2c-1"`. Index, rule, offending value quoted. For us: `step[4] "cyclonedds": verify shell is
empty`.

**T7. Enumerations list their members in the error.** `Valid types: network, bluetooth, ...` and
`invalid language "cobol" (valid: swift, python)`. One list, generated from the enum, so it cannot
drift — which is exactly what drifted for them, so generate it.

**T8. `~/.wendy/milestones`, a newline delimited list of milestone names.** Trivial, and it is what
lets a CLI teach once and then shut up. Ship it before shipping the first hint.

**T9. `dios infect schema` and `dios infect validate`.** They embed a real JSON Schema with an
`$id` and expose both commands offline. Makes the recipe format writable by a third party without
reading our source.

**T10. Every prompt has a flag, every flag pair is shown in `--help` as a complete command line.**
Nine full non-interactive examples in `wendy init --help`. Not a flag table.

**T11. No TTY produces an explicit error, never a hang.** `✗ wendy tour requires an interactive
terminal`, exit 1. And `schema question %q requires input in non-interactive mode (use --var
%s=VALUE)` names the flag and the key.

**T12. Split `--force` from the irreversible case.** `--yes-overwrite-internal` exists separately
from `--force` on `wendy install`. For us: `dios infect --yes` must not imply "reflash the robot's
network config".

**T13. Non-interactive defaults to the safe branch.** `wendy device update` without `-y` in a
non-interactive run *reports* the available OS update and does not apply it. It does not error and
it does not act.

**T14. Success names the next command or the new observable state.** `Your project is ready! Run
wendy run to build and deploy.` / `OS update applied; the device is rebooting. Reconnect once it is
back online.` Never "Done."

**T15. `Note:` for degradations that continue, `✗` for failures that stop.** `Note: block map
unusable (%v); flashing the full image.` / `Offline — using cached WendyOS %s; cannot confirm it is
the latest build.` Two glyphs, two meanings, consistently.

**T16. The fenced shared block in the installer with a CI test enforcing byte identity.** If dios
ever has a second install script.

**T17. `( umask 077; printf ... | tee )` for any file containing a secret, with the chmod as a
stated backstop.** Our recipes take `wifi_password = { type = "secret" }`.

**T18. Version resolution: explicit override → own manifest → GitHub API as fallback.** With the
stated reason (rate limits). `dios` installs from R2 already, so this is close to what we do; the
piece to copy is the ordering and the `|| true` inside the substitution.

**T19. Update nag prints both versions and the literal update command, throttled by a timestamp in
config.** `lastCLIUpdateCheck` + `availableCLIUpdate` cached, so the nag is free after the first
check.

### Take the idea, different mechanism

**I1. Their four-field `HardwareCapability` — `{category, device_path, description, properties}` —
for the open ended inventory, and typed fields only for facts that drive a decision.** The seam is
*who consumes it*, and that is what to copy. Our version is not device paths: it is
`{category, locator, description, properties}` where locator is an address, an interface, or a
path depending on category. Our `identify.rs` `Facts` already splits this way by accident
(`ping`/`open_ports` typed, `remote_files` open) — make it deliberate.

**I2. Discovery bucketed by transport, with a `providerKey` on every record.** `wendy discover
--json` returns `usbDevices`/`lanDevices`/`bluetoothDevices`/`ethernetDevices`/`externalDevices`
and marks `"providerKey": "local"` for this machine. For dios the transports are different — wired
subnet ping, mDNS, the Go2's webrtc lane where the robot is untouched — but "a device found two
ways is two facts about one device" is exactly our Go2 problem, since webrtc-lane and zenoh-lane
are the same robot. Bucket by lane, carry the provider.

**I3. Live facts versus recorded facts.** Wendy stores no device cache because the agent always
answers. We cannot: `infect` runs before anything is installed, which is why `identify.rs` scores
weighted probes against a recorded `Facts`. Take the *discipline* — one probe pass, recorded, and
everything after it pure (the comment in `identify.rs` already says this) — and reject the "always
ask live" mechanism.

**I4. The human/machine output split with different defaults.** They hide local run targets from
the human table and always include them in `--json`, stated in the docs. We should adopt the rule
(human output filtered for signal, machine output complete) without adopting their specific filter.

**I5. `wendy_status` — a single "where am I, what next" callable.** Their MCP tool is described as
"Call this first". `dios doctor` is already 80% of this; what it lacks is a single suggested next
action in plain English at the end.

**I6. `project optimize` — a linter over the user's config that emits machine applicable fixes.**
Real output from our scaffold:

```json
{ "analyzer": "arch-image", "severity": "warning", "title": "No .dockerignore",
  "detail": "Without a .dockerignore the whole context ... is sent to the builder",
  "fix": { "description": "create a default .dockerignore", "file": "...", "new": "..." } }
```

`--fix` applies them, `--severity` sets the exit threshold, `--agentic` emits an agent context
bundle. The idea for us is a recipe linter (`dios infect lint`): a step with no `verify`, a
`timeout_s` missing on a build step, a `[network]` subnet that no probe covers. Not a Dockerfile
analyzer.

**I7. `tour` as real setup rather than a demo.** Theirs does discovery → Wi-Fi → provisioning →
deploy → completions, prefills from the host where it can (detects the laptop's current SSID for
the Wi-Fi step), and finishing it suppresses the ambient prompts. Ours is `dios infect` itself
run in its most guided mode, not a separate command.

**I8. The stateful agent surface next to the stateless CLI.** Their MCP has `device_connect` /
`device_disconnect` sessions while the CLI passes `--device` per invocation. If dios grows an agent
surface, do not force the CLI's statelessness onto it.

### Leave it

**L1. The entire cloud tier** — `cloud`, `auth`, `fleet`, enroll/unenroll/rename, mTLS PKI,
enrollment tokens, tunnel broker, orgs and roles. ~27 commands. Their own `--lan` and `--api-key`
escape hatches prove it is severable.

**L2. Containers, and the chunked deploy protocol.** `QueryChunks`/`WriteChunks`/`WriteLayer`,
`--chunking auto|force|off`, the on-device containerd registry with two systemd units. Correct
engineering for their problem, which is not ours.

**L3. OS images, flashing, and A/B OTA.** `wendy install`, `wendy os *`, bmap, T234 flashpacks, RCM
recovery, slot health with retry counters, the ~15-field `osUpdate` block. We do not own the OS on
a Unitree.

**L4. The ROS 2 subsystem, all 17 commands.** dimos is LCM.

**L5. Media streaming.** `StreamVideo`, `StreamAudio` with jitter buffer, VU meter, camera
credential store, Foxglove bridging.

**L6. The TUI tier** — `dashboard`, `top`, the 7-keybinding live discover table, OTLP
logs/metrics/traces.

**L7. Multi-service and fleet manifests** — `services`, `dependsOn`, `isolation`, `resources`,
`components`, `--central`, `readiness`, `hooks`. Our `[[step]]` with `phase`/`on`/`verify` does the
job. Do not grow it.

**L8. `analytics` as a top-level command group.**

**L9. Their three-sources-of-truth failure.** Do not let `--help` examples, the schema, and the
runtime validator drift apart. Concretely: generate the enum lists in error messages from the enum,
generate or test the `--help` examples against the validator, and call `validate()` on every write
path — `init`, `entitlements add`, and anything else that touches the manifest.

**L10. Prompting before validating flags.** `--all-entitlements cannot be combined with
--entitlement` is the right error and it fires too late. Validate arguments before any I/O.

**L11. Read-modify-write of one config blob from two code paths.** Their first-run race dropped
`defaultDevice` silently. `dios config` writes `~/.dimos/config.json`; make sure exactly one writer
owns it, or make the write a merge rather than a replace.

---

## Appendix: artifacts left on disk

```
/tmp/wendy_help_full.txt   86 help pages, recursive walk
/tmp/wstrings.txt          105,347 strings from the binary
/tmp/wendy.schema.json     wendy json schema, 20,178 bytes
/tmp/wendy-agent.sh        the agent installer, downloaded and read, never executed
/tmp/wstudy/{a..i}         8 scaffolded projects
/tmp/wendyhome/.wendy/     isolated CLI state used for the write tests
```

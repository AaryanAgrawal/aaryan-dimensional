# Shipping dimos to China without Docker

Measured on this laptop (Ubuntu 24.04, x86_64, nix 2.34.8, uv 0.11.26) on 2026-08-10.
Every number below came out of a command that ran. Anything I could not run is marked
**untested** and says why.

---

## Recommendation

Do not ship an image, redirect the endpoints: every upstream `dios setup` touches has a live and
complete Chinese mirror, including the Nix binary cache, so a `dios setup --mirror cn` that writes
four config files fixes the ordinary case with no new artifact format at all.

For the genuinely offline robot, ship a plain directory (an aarch64 wheelhouse, a `.deb` pool and a
python-build-standalone tarball) and sync it with rsync: I cross built the real dimos core
wheelhouse from this x86 laptop in 5m24s (107 wheels, 512.8 MB down, 1633.0 MB installed) and rsync
moves 1.5 MB of it when one wheel changes.

Keep the `DIMOSPAK` self extracting payload that `src/pkg/docker.rs` already implements, but change
what is inside it from a `docker save` tar to that bundle, because `docker load` is the only option
on this list with no delta at all.

---

## 1. Mirrors

### What is reachable

Every mirror answered. Times are from outside China and mean nothing about the trip inside the
firewall; the point of the table is that the paths exist and serve the right bytes.

| endpoint | code | time |
|---|---|---|
| `mirrors.aliyun.com/ubuntu/dists/focal/Release` | 200 | 0.60 s |
| `mirrors.tuna.tsinghua.edu.cn/ubuntu/dists/focal/Release` | 200 | 1.62 s |
| `mirrors.ustc.edu.cn/ubuntu/dists/focal/Release` | 200 | 5.66 s |
| `mirrors.aliyun.com/ubuntu-ports/dists/focal/Release` | 200 | 1.10 s |
| `mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/dists/focal/Release` | 200 | 1.84 s |
| `mirrors.ustc.edu.cn/ubuntu-ports/dists/focal/Release` | 200 | 1.65 s |
| `repo.huaweicloud.com/ubuntu-ports/dists/focal/Release` | 200 | 1.43 s |
| `mirrors.aliyun.com/pypi/simple/numpy/` | 200 | 0.31 s |
| `pypi.tuna.tsinghua.edu.cn/simple/numpy/` | 200 | 2.06 s |
| `mirrors.tuna.tsinghua.edu.cn/nix-channels/store/nix-cache-info` | 200 | 0.64 s |
| `mirrors.ustc.edu.cn/nix-channels/store/nix-cache-info` | 200 | 0.67 s |

**`ubuntu-ports`, not `ubuntu`.** The Orin NX is arm64, and Ubuntu serves arm64 from
`ports.ubuntu.com`, a different host and a different path on every mirror. A `sources.list` that
only rewrites `archive.ubuntu.com` leaves the robot pointed at the slow host. All four mirrors carry
`ubuntu-ports`; I fetched a real arm64 focal `.deb` through Aliyun to prove it end to end:

```
pool/main/g/gcc-10/libgomp1_10-20200411-0ubuntu1_arm64.deb  200  91984 B  1.01 s
dpkg-deb -I  ->  Architecture: arm64
```

The focal arm64 `Packages` index is 131,022 lines, so the whole pool is there, not a subset.

### PyPI mirrors are complete, including history

The worry with a mirror is that it prunes old versions. It does not. `PyTurboJPEG` has 37 distinct
sdists on pypi.org, and Aliyun, Tsinghua and USTC each list exactly 37, including the 1.8.2 that
dimos pins.

Two apparent mirror gaps I chased turned out to be real facts about the wheels, not mirror lag:
`numpy==2.3.4` has no cp310 wheel (numpy 2.3 dropped 3.10) and `PyTurboJPEG==1.8.2` has no wheel at
all. Both fail identically against pypi.org.

### The Nix binary cache — use USTC, not Tsinghua

This is the one worth checking carefully, and the answer is not the one everybody assumes.

Both mirrors expose `/nix-channels/store` and both serve a correct `nix-cache-info`
(`StoreDir: /nix/store`, `Priority: 40`). They are not the same thing underneath.

| sample | Tsinghua | USTC | cache.nixos.org |
|---|---|---|---|
| 60 random paths from this laptop's `/nix/store` | 1 | 50 | 50 |
| 35 of those that upstream definitely has (older nixpkgs rev) | **0** | 35 | 35 |
| 40 paths from a closure built today off current `nixpkgs-unstable` | 40 | 40 | 40 |

Tsinghua mirrors only what is reachable from the channel revision it currently carries. USTC mirrors
the cache. Our `flake.lock` pins `nixpkgs` at `d1c15b7d5806` (lastModified 1771207753, February
2026), which is not the current channel, so Tsinghua will 404 on most of our closure and Nix will
silently fall through to `cache.nixos.org`, which is the host we were trying to avoid.

USTC serves real NARs, not just metadata. I pulled one and verified the hash:

```
URL: nar/191279s1gmdlx8y98yn6drwd1xlqv21z7a24pdl2zql8zidzl8fc.nar.zst
FileSize: 75359            downloaded: 75359 B
FileHash: sha256:1ngg1dgrbr09k4i5daqq3h2f88mqqpls6xja1np4isgcr3bin3l7
computed: sha256:1ngg1dgrbr09k4i5daqq3h2f88mqqpls6xja1np4isgcr3bin3l7
```

Neither is a lazy proxy: a fabricated hash 404s on USTC exactly as it does upstream.

Tsinghua wins the other half. It mirrors the Nix **release tarballs**, which USTC does not:

```
mirrors.tuna.tsinghua.edu.cn/nix/nix-2.34.8/nix-2.34.8-aarch64-linux.tar.xz   206
mirrors.tuna.tsinghua.edu.cn/nix/nix-2.28.4/nix-2.28.4-aarch64-linux.tar.xz   206
mirrors.ustc.edu.cn/nix/                                                      404
```

So: installer from Tsinghua, substituter from USTC.

### The exact config

`/etc/apt/sources.list` on the Jetson (focal, arm64):

```
deb https://mirrors.aliyun.com/ubuntu-ports/ focal main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu-ports/ focal-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu-ports/ focal-backports main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu-ports/ focal-security main restricted universe multiverse
```

Leave `/etc/apt/sources.list.d/nvidia-l4t-apt-source.list` alone. It points at
`repo.download.nvidia.com`, has no Chinese mirror, and rewriting it breaks JetPack updates.

`~/.config/pip/pip.conf` and the uv equivalent:

```ini
[global]
index-url = https://mirrors.aliyun.com/pypi/simple/
extra-index-url = https://pypi.tuna.tsinghua.edu.cn/simple/
trusted-host = mirrors.aliyun.com pypi.tuna.tsinghua.edu.cn
```

```sh
export UV_DEFAULT_INDEX=https://mirrors.aliyun.com/pypi/simple/
export UV_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple/
export UV_PYTHON_INSTALL_MIRROR=https://gh-proxy.com/https://github.com/astral-sh/python-build-standalone/releases/download
```

`UV_INDEX_URL` still works but is the deprecated spelling; `UV_DEFAULT_INDEX` is current in uv
0.11. The `--mirror` flag on `uv python install` is real (`uv help python install` documents
`--mirror` and `--pypy-mirror`); the GitHub proxy above returned 200 from here, and it is the only
line in this document I would not bet on staying up, because those proxies churn.

`/etc/nix/nix.conf`:

```
substituters = https://mirrors.ustc.edu.cn/nix-channels/store https://cache.nixos.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

USTC first, upstream as fallback. USTC re-serves upstream's signatures, so the key list does not
change.

Nix installer, if you install Nix at all:

```sh
curl -L https://mirrors.tuna.tsinghua.edu.cn/nix/nix-2.34.8/nix-2.34.8-aarch64-linux.tar.xz \
  | tar -xJ && ./nix-*/install --no-daemon
```

`Dockerfile:24` and three call sites in `src/pkg/` currently fetch `https://nixos.org/nix/install`,
which is a 302 to `releases.nixos.org`. That is the line to replace.

### What has no mirror

Grepping every URL literal in `src/`:

```
10  github.com
 4  astral.sh
 3  raw.githubusercontent.com
 3  nixos.org
 3  get.docker.com
 1  install.determinate.systems
 1  pypi.org
```

plus the R2 bucket in `install.sh` that ships the `dios` binary itself. `nixos.org` and `pypi.org`
are solved above. `astral.sh` is solved by installing uv as a wheel instead of a shell script:
`uv-0.9.9-py3-none-manylinux_2_28_aarch64.whl` is on the Aliyun PyPI mirror. `github.com` and
`raw.githubusercontent.com` are the ones with no clean answer, and they are how dios clones dimos
and fetches the Unitree SDK. `get.docker.com` and `install.determinate.systems` stop mattering the
moment we stop shipping Docker.

The bootstrap is its own problem: `install.sh` pulls the 6.0 MB `dios` binary from
`pub-4767fdd15e6a41b6b2ce2558d71ec8d9.r2.dev`. That is Cloudflare R2, reachable in China but not
dependably fast, and it is the very first byte of the install. A mirror of one 8 MB static binary on
a Chinese object store is a cheap fix and belongs on the list.

---

## 2. Nix closures

`nix copy --to file://` writes an ordinary binary cache into a directory: one `.narinfo` per store
path, one compressed NAR per path, and a `nix-cache-info`. `nix copy --from file://` reads it back.
No daemon on either side, no registry, no network.

Measured, with `python3 + numpy + opencv4 + scipy` plus a 16 MB source tree on top:

| | paths | uncompressed | artifact | build time |
|---|---|---|---|---|
| `hello` | 5 | 36.2 MB | 7.7 MB (xz) | 6.2 s |
| python env | 180 | 1009.6 MB | 221.6 MB (xz) | 76.0 s |
| python env | 180 | 1009.6 MB | 301.7 MB (zstd) | 1.3 s |
| env + source | 181 | 1025.0 MB | 312.9 MB (zstd) | 1.4 s |
| env + source, `nix-store --export \| zstd -19` | 181 | 1025.0 MB | 247.9 MB | 24.0 s |

xz is 26 percent smaller than zstd and roughly 60 times slower to produce. For a box you build once
and ship over a bad link, take xz. The single file `nix-store --export` variant is smaller still
(247.9 MB) because it compresses the whole closure as one stream, but it is monolithic and gives up
the entire incremental story, so it is the wrong shape here.

Restoring the 312.9 MB cache into a clean store, offline, took **0.67 s**:

```
nix copy --offline --from file:///tmp/nixexp/bundle --to /tmp/nixexp/reststore \
  --option trusted-public-keys "$(cat dios.pub)" $OUT
```

### The gotchas, all reproduced

**Signatures.** A path you built yourself has no `Sig:` line, and the importer refuses it:

```
error: cannot add path '/nix/store/w433...-dios-fake-app' because it lacks a signature by a trusted key
```

Two fixes, both verified. Sign at export and trust at import:

```sh
nix key generate-secret --key-name dios-1 > dios.key
nix key convert-secret-to-public < dios.key > dios.pub     # dios-1:vPiL0Ifr4e+...
nix copy --to "file:///out?secret-key=$PWD/dios.key" $OUT
nix copy --from file:///out --to /target --option trusted-public-keys "$(cat dios.pub)" $OUT
```

or skip the check with `--no-check-sigs`.

**But `--option` is ignored when a daemon is involved and you are not root.** This machine has
`trusted-users = root` and `require-sigs = true`, which is the default. Importing into the real
`/nix/store` as an ordinary user:

```
warning: ignoring the client-specified setting 'trusted-public-keys', because it is a restricted
         setting and you are not a trusted user
error: cannot add path '/nix/store/iwnj...-dios-trust-probe' because it lacks a signature by a trusted key
```

`--no-check-sigs` fails identically. So the public key has to go into `/etc/nix/nix.conf`, written
once by root. That is a one-time setup step, not a per-delivery step.

**Root.** `/nix` is `drwxr-xr-x root root`, and a non-root user cannot create it (`mkdir: Permission
denied`). Nix needs root exactly twice, both once per robot: create `/nix`, and add the trusted key.
Everything after that is unprivileged.

**Store paths do not relocate.** A closure copied into a chroot store lands at
`<root>/nix/store/<same-hash>-<name>`, and every ELF inside still has `/nix/store/...` baked into
its interpreter and RPATH. You cannot untar a Nix closure into `/opt` and run it. This is why the
one-time root step is not optional.

---

## 3. Python wheelhouse

`pip download -d wheelhouse/` then `pip install --no-index --find-links wheelhouse/`. The
interesting part is doing it for a machine you are not on.

I built the **real dimos core dependency set** (the 31 lines under `dependencies` in
`dimos/pyproject.toml`) for aarch64 from this x86 laptop, through the Aliyun mirror:

```sh
pip download -d wh-dimos --no-cache-dir \
  --platform manylinux_2_17_aarch64 --platform manylinux2014_aarch64 \
  --platform manylinux_2_27_aarch64 --platform manylinux_2_28_aarch64 \
  --platform manylinux_2_31_aarch64 \
  --python-version 3.10 --implementation cp --abi cp310 \
  --only-binary=:all: -i https://mirrors.aliyun.com/pypi/simple/ -r core-reqs.txt
```

```
107 wheels
download size : 512.8 MB
installed size: 1633.0 MB
wall time     : 5m24s
```

Compressing it is not worth much, because wheels are already deflate zips:

| form | size |
|---|---|
| directory | 512.8 MB |
| `tar \| zstd -19` | 486.3 MB |
| `mksquashfs -comp zstd -Xcompression-level 19` | 503.2 MB |

### What breaks, concretely

**The platform tag set is the whole game.** My first attempt passed only
`--platform manylinux2014_aarch64` and died on line 2 of the requirements:

```
ERROR: Could not find a version that satisfies the requirement eclipse-zenoh<2.0,>=1.0.0
       (from versions: 0.5.0b9, 0.6.0b1, 0.7.0rc0, 0.7.2rc0, 0.10.0rc0)
```

`eclipse-zenoh` 1.9.0 publishes `manylinux_2_28_aarch64` and nothing older. The tags actually in use
across our dependencies today:

| package | aarch64 tags |
|---|---|
| eclipse-zenoh 1.9.0 | `manylinux_2_28_aarch64` |
| numpy 2.5.2, scipy 1.18.0, numba, llvmlite | `manylinux_2_27_aarch64.manylinux_2_28_aarch64` |
| pin 4.1.0, rerun-sdk 0.35.0 | `manylinux_2_28_aarch64` |
| opencv-contrib-python | `manylinux2014_aarch64` and `manylinux_2_28_aarch64` |
| sqlite-vec 0.1.9 | `manylinux_2_17_aarch64` |
| cryptography 50.0.0 | up to `manylinux_2_34_aarch64` |
| open3d-unofficial-arm 0.19.0.post9 | `manylinux_2_31_aarch64`, `manylinux_2_35_aarch64` |

The Jetson's glibc is 2.31 (Ubuntu 20.04), so the usable ceiling is `manylinux_2_31` and passing
`manylinux_2_34` would hand the robot a wheel it cannot load. `--platform` is a whitelist with no
implied ordering, so all five tags have to be listed.

**Python 3.11 is not a legal choice for this robot.** `open3d-unofficial-arm` 0.19.0.post9 ships
`manylinux_2_31_aarch64` for cp310 and cp312, but for cp311 it ships only `manylinux_2_35_aarch64`,
which wants glibc 2.35. dimos requires `>=3.10,<3.13`. On the Jetson that leaves **3.10 or 3.12**.

**Sdist-only pins cannot be cross built.** `PyTurboJPEG==1.8.2` is `PyTurboJPEG-1.8.2.tar.gz` and
nothing else, so `--only-binary=:all:` rejects it outright:

```
ERROR: Could not find a version that satisfies the requirement PyTurboJPEG==1.8.2
       (from versions: 2.5.0)
```

Dropping `--only-binary` does not help: pip will happily download the sdist, and then the robot has
to compile it, which means `libturbojpeg0-dev`, a compiler, and a working toolchain on a device with
no network. There are three ways out, in order of how much I like them: unpin to 2.5.0, which ships
a `py3-none-any` wheel; or build the wheel once in an aarch64 `manylinux_2_31` container and put it
in the bundle; or accept a compile on first boot. dimos already knows about this class of problem,
the `pyproject.toml` comment about `embreex` having no aarch64 wheel is the same failure.

**There is no Python to install into.** Ubuntu 20.04 arm64 ships `python3 3.8.2-0ubuntu2`, and
`focal` main plus universe contain zero packages named `python3.10`, `python3.11` or `python3.12`. I
grepped the arm64 `Packages` indices to confirm. dimos needs 3.10 or newer. deadsnakes is on
Launchpad and has no Chinese mirror. So the bundle has to carry an interpreter:
`cpython-3.10-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz` from python-build-standalone,
about 30 MB, which is also exactly what `uv python install` fetches.

---

## 4. The single-artifact options, side by side

For a 512.8 MB wheelhouse or a 312.9 MB Nix closure carrying the same thing.

| | size | root to install | runtime needed on robot | incremental |
|---|---|---|---|---|
| plain directory + rsync | 512.8 MB | no | none | **yes, sub-file** |
| tarball | 486.3 MB | no | none | no |
| squashfs | 503.2 MB | **yes**, to mount | kernel squashfs, or squashfuse | no |
| Nix closure as a file cache | 312.9 MB | once, for `/nix` and the key | `nix` binary | yes, per store path |
| OSTree | untested | yes | ostree | yes, per file |
| `DIMOSPAK` payload (today) | image size | no, to extract | Docker, because it calls `docker load` | no |
| Docker via registry | image size | yes, daemon | Docker | yes, per layer |
| Docker via `docker save` | image size | yes, daemon | Docker | **no** |

Verified rather than assumed:

- `mount -o loop wh.squashfs mnt` as a non-root user: `failed to setup loop device`. `unsquashfs`
  works unprivileged, but then squashfs is a tarball with extra steps and no delta.
- `tar -xf` unprivileged: 107 files out, fine.
- `mkdir /nix-test`: `Permission denied`.
- squashfs came out *larger* than `tar | zstd` on this input. Recompressing zips does nothing, and
  squashfs pays block overhead on top.

`src/pkg/docker.rs` is the piece worth keeping. The layout is
`[binary][zstd tar][u64 size LE]["DIMOSPAK"]`, `detect_payload()` reads the 16 byte trailer,
`extract_payload()` streams it through `zstd::Decoder` to disk. None of that is Docker specific.
Only `load_image()` and `check_docker()` are, and they are 30 lines. Swap the payload for a bundle
directory and the same self-extracting binary ships something that needs no daemon and no root.

**Untested:** I have no Docker on this machine and no ostree, so the two Docker rows and the OSTree
row are reasoning from how those tools work, not measurement.

---

## 5. Incremental update

This is the axis that decides the question, because the first install happens once and every
install after it happens weekly.

**Wheelhouse, measured.** I rebuilt one wheel with a one-line change inside it and rsynced the
directory:

```
Total file size:             537,665,891 bytes
Total transferred file size:   1,719,416 bytes
Literal data:                  1,489,912 bytes
Matched data:                    229,504 bytes
sent                           1,497,999 bytes
```

1.5 MB moved out of 513 MB, **0.28 percent**, and rsync's rolling checksum found 229 KB of the
changed wheel unchanged and did not resend it.

**Nix, measured.** Same experiment on the 181 path closure, changing one line in one `.py` inside a
16 MB source tree:

```
paths only in v2: 1 of 181
delta compressed: 11.3 MB of 312.9 MB total (3.6%)
```

Both ship only what changed. The difference is granularity: rsync's unit is a block inside a file,
Nix's unit is a whole store path. My changed path was the entire 16 MB source tree, so Nix resent
all of it. Nix's binary cache protocol has no sub-file delta, it fetches whole NARs. For dimos,
whose source tree is one store path, that means every `.py` change costs the compressed size of all
of dimos.

**Docker.** With a registry and well ordered layers, a change to the source layer ships only that
layer, which is the same story as Nix. Without a registry, which is the situation behind the
firewall and the situation `DIMOSPAK` implements today, `docker save` produces one tar with every
layer in it and `docker load` has no notion of "I already have that". Every delivery is the full
image. That is the strongest single argument against the current path.

**Tarball and squashfs:** nothing. Byte one changes and the whole file is new.

---

## 6. What to actually do

### What Aaryan sets up once

1. Generate a signing key, if the Nix path is taken later. `nix key generate-secret --key-name
   dios-1`. Secret in the release runner, public in the recipe.
2. Mirror the `dios` binary itself. One 6.0 MB file (measured: Content-Length 6,307,808) on a Chinese object store, plus a `DIOS_BASE_URL`
   override in `install.sh`. Without it the bootstrap is the slowest step of the install.
3. Decide the interpreter: 3.10 or 3.12, because 3.11 has no `open3d` wheel for glibc 2.31. Pin it
   in the recipe.
4. Deal with `PyTurboJPEG==1.8.2`. Either unpin to 2.5.0, or build the aarch64 wheel once in a
   `manylinux_2_31` container and commit it to the bundle.
5. On each robot destined for China, once, as root: `/nix` and the trusted key, **only if** the Nix
   path is taken. The wheelhouse path needs neither.

### What the tooling does every time

`dios setup --mirror cn` writes four files and changes nothing else:

```
/etc/apt/sources.list                    -> mirrors.aliyun.com/ubuntu-ports
~/.config/pip/pip.conf                   -> mirrors.aliyun.com/pypi/simple
~/.config/uv/uv.toml (or the env vars)   -> same, plus UV_PYTHON_INSTALL_MIRROR
/etc/nix/nix.conf                        -> mirrors.ustc.edu.cn/nix-channels/store first
```

`dios bundle build --target aarch64-jetson-focal --recipe <r>` on the x86 build machine produces:

```
bundle/
  wheels/            107 wheels, 512.8 MB     pip download --platform ... --only-binary=:all:
  debs/              apt pool subset          fetched by Filename: from the arm64 Packages index
  python/            cpython-3.10 tarball     python-build-standalone, ~30 MB
  MANIFEST.json      sha256 per file, recipe id, target triple
```

`dios bundle sync <host>` rsyncs it, and `dios infect --offline --bundle <dir>` installs with
`--no-index --find-links`, `dpkg -i`, and the shipped interpreter. Second delivery onward, rsync
moves the changed wheels only.

Skeletons for all of this are in `workspace/china-delivery/`, with the exact flags from the runs
above baked in.

---

## What I could not test

- **Anything from inside China.** Every timing here is from a host outside the firewall. I verified
  that the mirrors exist, are complete and serve correct bytes. I did not and cannot verify
  throughput or packet loss on the path a robot in Shenzhen would take. Someone with a box there
  needs to run the same reachability loop; the script is in the skeleton directory.
- **Docker.** Not installed on this machine. The two Docker rows in the table are reasoned from how
  layers and `docker save` work, not measured.
- **OSTree.** Not installed. Listed for completeness, untested.
- **The robot side of the wheelhouse.** I verified the cross *download*. I have no aarch64 Jetson
  here, so `pip install --no-index --find-links` against those 107 wheels on real hardware is
  unrun, and that is where a wrong `manylinux` tag would surface.
- **The Nix daemon accepting our key.** I reproduced the failure exactly, including the
  "restricted setting" warning. I have no sudo here, so I could not edit `/etc/nix/nix.conf` and
  watch the same import succeed. The equivalent import into a store I own does succeed, so the
  mechanism is proven and only the privileged edit is unrun.
- **`gh-proxy.com`.** Returned 200 today. GitHub proxies churn constantly and this one should be
  treated as a value in a config file, never as a constant in the source.
- **Torch and CUDA.** The `misc` and `agents` extras pull torch, and on a Jetson those come from
  NVIDIA's index rather than PyPI. `pypi.nvidia.com` answered 200 and
  `pypi.jetson-ai-lab.io` 302 from here, and that is all I checked. The x86 venv on this laptop is
  13 GB, of which 4.3 GB is `nvidia/` and 1.7 GB is `torch/`, so this is the part of the problem
  that dwarfs everything measured above, and it is a separate piece of work.

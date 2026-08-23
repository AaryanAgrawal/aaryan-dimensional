# DIOS environment traps

Environment and toolchain failures hit on real hardware, for DIOS to replicate and check for.
**Append only. Nothing is deleted from this list.**

1. **Toolchain present but not on PATH.** nix-provisioned host, `cargo build --release` →
   `cargo: not found`, while cargo sits in `/nix/store/…-cargo-1.95.0/bin`. Fatal to the stack.

2. **Late dlopen loses the static TLS budget (aarch64).**
   `libgomp.so.1: cannot allocate memory in static TLS block`, 11,452x, error count still 0.
   Silent dead perception.

3. **Host network config not persistent across reboot.** `ip link set lo multicast on` and
   `ip route add 224.0.0.0/4 dev lo` needed for LCM; autoconfig needs a tty for sudo, so it fails
   over ssh.

4. **Private artifact store with no credentials.** `git lfs pull` → could not read Username for
   `lfs.dimensionalos.com`. Blocks sim assets, URDFs, models.

5. **Stale vendored-dependency hash.** nix `hash mismatch in fixed-output derivation` for
   voxel-ray-tracing. On main, so broken for everyone. Only shows on a cold rebuild, and is flaky.

6. **Build input pinned to a branch name.** Same commit under a different local branch →
   `NAR hash mismatch in input 'git+file:…?ref=refs/heads/<branch>'`.

7. **Optional dependency hides components from CI.** No `unitree_sdk2py` → G1 hardware blueprints
   cannot be imported, so their tests skip instead of fail. Hid two breakages in one day.

8. **Stale entry points and editable installs.** Console script shebangs and the editable path
   pointing at directories that no longer exist; imports only worked via the current directory.

9. **Interactive-only paths in automated runs.** sudo wants a tty; the viewer websocket closes with
   1008 unless the URL carries `/ws`, while the data stream still connects so it looks fine.

10. **Repo config silently cancels an explicit fetch.** `.lfsconfig` sets
    `fetchexclude = data/.lfs/*`, so `git lfs pull --include="data/.lfs/<asset>"` exits 0 and
    fetches nothing — the pointer file is left in place and the failure only shows up later as a
    missing asset. Needs `-X ""` to clear the exclude.

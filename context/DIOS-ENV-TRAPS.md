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

10. **Rust toolchain split across store paths.** A nix `rustc` whose path ends
    `-x86_64-unknown-linux-gnu` ships no host `rust-std`, so every crate fails
    `E0463: can't find crate for std` even though `rustc --version` works. The matching `rust-std`
    is a separate unlinked store path. `cargo fmt` and `cargo clippy` are absent from both.

11. **Repo venv missing a declared dependency.** `import git` (GitPython) fails in the dimos venv,
    so 19 of 98 blueprint validity tests fail on a clean `main` with nothing local changed. Looks
    like your regression until you run the same suite on an untouched checkout.

12. **The Unitree app IP is not the G1 Jetson.** On this G1, `10.0.0.214` answered ping but refused
    ssh; over Ethernet the control computer was `192.168.123.161`, the Mid360 was `.120`, and the
    Jetson with ssh was `.164`. The laptop used `192.168.123.100/24` and
    `unitree@192.168.123.164`. The Jetson's Wi-Fi was soft-blocked, so its saved `dimensional`
    profile only came up after `sudo rfkill unblock wifi` and `sudo nmcli connection up
    dimensional`; DHCP then assigned `10.0.0.95`.

13. **A timeout can make a healthy G1 run look failed during shutdown.** On `7b2a5b698`,
    `LD_PRELOAD=/lib/aarch64-linux-gnu/libGLdispatch.so.0:/usr/lib/aarch64-linux-gnu/libgomp.so.1
    dimos --rerun-open none --rerun-host 0.0.0.0 run unitree-g1-nav-3d --build-native` built and ran
    MLS, ray tracing, and PointLio; LowState, odometry, local maps, region bounds, and the Rerun
    server were live. Wrapping it in `timeout --signal=INT 360` stopped every module, then logged
    `RuntimeError: release unlocked lock` and exited 124.

14. **The G1 native build dirties a clean checkout.** On `7b2a5b698`, the standard
    `unitree-g1-nav-3d --build-native` path adds `dimos-repo` to the tracked ray-tracing
    `flake.lock` and creates an untracked MLS `flake.lock`; the builds pass, but later modules warn
    that the Git tree is dirty.

15. **Changing networks can leave Rerun connected but blank.** The Ethernet viewer disappeared
    when the cable was removed, and the server logged a blocked broadcast channel; a new Wi-Fi
    viewer connected to both ports but received only the gRPC handshake. Stop the viewer, restart
    Dimos, then reconnect both URLs through `10.0.0.95`; the fresh viewer streamed data and rendered
    the point cloud.

16. **Static `192.168.123.100` on both the dev box and the Orin.** With Jeff's Orin NX on the dev
    box's Ethernet, the IPv4 sweep found only the dev box itself. SSH over IPv6 link-local
    (`fe80::...%enp130s0`) works; write the `%` as `%%` in `ssh_config`.

17. **C++ natives die under the zenoh default.** On main @ `49f1f2152` `dimos run unitree-go2-nav-3d`
    deploys every module, then `pointlio_native` exits 1 with no stderr in the log:
    "DIMOS_TRANSPORT=zenoh is not supported by the C++ native SDK (LCM only)". Same for
    `mid360_native`. Pass `--transport lcm`; the rust natives are fine either way.

18. **Raw Mid-360 rows land in 1970 under `--record`.** The Mid360 native stamps points with lidar
    uptime and the tap copies the stamp onto the row, so `livox_lidar`/`livox_imu` cannot be aligned
    with the wall-clock streams. Keep them out with `--record-topics` and take `RECORD_PCAP=1` instead.
    With them in, the tap also drops ~6% ("writer queue full", fixed 1000-deep queue).

19. **Two ports, two cables, easy to cross.** On the Orin the Mid-360 is a 100 Mb link and the Go2 a
    1 Gb link; `cat /sys/class/net/<if>/speed` tells them apart before any IP debugging. Jeff's
    `~/dimos/.env` pins the lidar at .157; the unit on the dog is `192.168.1.171` (multicast
    224.1.1.5 gives it away without sudo).

20. **`KeyboardTeleop` needs X11.** Headless it dies in its thread ("x11 not available") and the run
    continues without teleop; drive with the Unitree remote or `ssh -X`. Also `Go2Mid360Recorder`
    throws "Cannot operate on a closed database" at shutdown; data was intact.

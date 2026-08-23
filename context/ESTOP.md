# E-stop module

A dimos module that latches an e-stop and stops the robot. Written in Rust. Any robot, any
blueprint, on by default.

- PRD: https://linear.app/dimensional/project/e-stop-module-dce7e0091e2e (Linear project,
  Engineering v2, Control initiative, PRD template, Status Draft 2026-08-23)
- Tech spec: https://github.com/dimensionalOS/dimos/issues/3621
- Local copies for editing: `ESTOP-PRD.md`, `ESTOP-TECHSPEC.md`. Linear and the issue are the
  published homes; keep them in step or delete the local copies.

- Branch: `aaryan/estop-rust`, off `upstream/main` @ `6fcc4e2d5`. Worktree
  `workspace/dimos/.claude/worktrees/estop-rust`.
- Lives at `dimos/control/estop/`, beside the `ControlCoordinator` it will feed.
- **The rust module has never run on a robot.** Every hardware number below was measured with the
  earlier python prototype. The rust module is verified only against the replayed fixture.
- Supersedes the earlier Python G1 prototype on `aaryan/g1-estop` (kept for its measurements, see
  History below).

## Architecture (2026-08-23, decided by Aaryan)

```
   imu:     Input<Imu>    ->  fall check    (tilt > max_tilt_deg)  \
                                                                    >-- ONE latch --> estop: Output<Bool>
   trigger: Input<Bool>   ->  manual button (a direct message)     /
```

- **A module, not a blueprint.** A blueprint is a stack of modules wired by `autoconnect`; the
  e-stop is one module inside it. That is why it can go in every blueprint.
- **Every blueprint, on by default**, with default options enabled. Setup stays trivial.
- **Rust**, so it is fast and fail proof.
- **IMU only** for fall detection. Torque is dropped entirely.
- **Each failure state is one check.** Fall is a check. The manual button is a check. A third is
  another check, added the same way.
- **The manual button is a direct message** to the module, so anything can trigger it.
- **The latch never clears itself.**

`tilt = acos(1 - 2*(qx^2 + qy^2))`, the angle between the body z axis and gravity. Yaw invariant.
Validated against the robot's own `rpy` to 4.8e-11.

Rust message types confirmed present: `lcm_msgs::sensor_msgs::Imu` (carries `orientation`,
`angular_velocity`, `linear_acceleration`) and `lcm_msgs::std_msgs::Bool`.

## Kill path

`ControlCoordinator.set_estop()` (`dimos/control/coordinator.py:710`, on main) is an `@rpc` that
takes `_task_lock` and fans out `getattr(task, "set_estop")` to every registered task. Highest
priority because it makes every task inert under one lock instead of racing a publisher. Its own
docstring: "Synchronous RPC (not a stream) so E-STOP can't be dropped under load."

Gap: only two arm tasks implement `set_estop`. No G1 task does, so on the G1 it is a no-op today.
Closing it is ~6 lines on `G1GrootWBCTask`: latch, then call the already existing `disarm()` at
`g1_groot_wbc_task.py:666` ("Called either from an operator Disarm button or from safety
watchdogs"). That watchdog was never built. This is it.

## Test data

`g1_fall_imu.csv`, 1401 rows, committed beside the test.

**The orientation is SIMULATED.** Only the tilt magnitude is measured: it is the real tilt-vs-time
of two deliberate G1 falls (peak 81.15 deg, 836 samples above 45 deg). That measured tilt is then
re-encoded as a synthetic orientation, a pure roll of the measured angle composed with a yaw ramp
at 0.7 rad/s. So pitch is identically zero and yaw is a perfect ramp, neither of which the robot
did. The encoding round-trips to the measured tilt within 9.4e-08 deg. It is a faithful input for
the tilt-and-latch path and a poor stand-in for real IMU orientation noise.

## Environment

`cargo` is not on PATH (DIOS trap 1). Use the nix store directly:

`nix build -L path:.` in the module's `rust/` dir is the sanctioned path, and it runs the tests
inside the sandbox.

For a fast `cargo test` loop, use the self-consistent nixpkgs pair. These two work:

```
export PATH=/nix/store/cavxgwfb7l7akyvvqvnl39d6nw0wckgh-cargo-1.97.1/bin:\
/nix/store/hjh2pcv59jhxwh6japwx1v437w4yrbp1-rustc-1.97.1/bin:$PATH
```

Do NOT use the `*-x86_64-unknown-linux-gnu` suffixed cargo/rustc store paths. That rustc ships no
host `rust-std`, so every crate dies with `E0463: can't find crate for std` unless a matching
`rust-std` store path is grafted in via `RUSTFLAGS=--sysroot=...`. `cargo fmt` and `cargo clippy`
are absent from both toolchains.

The minimal rust module template is `examples/native-modules/rust/src/pong.rs`, 53 lines.

## History: what the Python prototype measured (branch `aaryan/g1-estop`)

Hardware, 2026-08-22. These numbers are why the design looks like it does.

- **Falls:** two deliberate falls, 176,426 samples, 756 Hz mean. Trips at 45.1 deg both times,
  peak 81.2 deg. Upright baseline over the first 60 s of that recording: p50 5.92 deg (prep mode).
  Zero false trips across a 10 minute activated-standing baseline.
- **45 deg is a confirmation, not an early warning.** At the crossing the robot is already ~64%
  unloaded. `tilt > 30 deg` leads by 300 ms and `tilt > 20 deg` by 778 ms, measured in a 6 s window
  around the first trip.
- **A gyro gate is not usable, and this is why the fall check is tilt only.** Over the FULL
  recording `gyro > 2.0 rad/s` fires 115 samples starting at t=72.1 s, 46 s before the fall, while
  the robot is in prep. `gyro > 1.0 rad/s` fires 979 samples from t=49.5 s. Both would false trip.
  An earlier claim that `gyro > 2.0` never fired before the trip was measured only inside a 6 s
  window and is wrong over the whole recording.
- **Lifted / hung up:** knee torque separates cleanly (standing p50 13.71 Nm, hung 2.64 Nm, no
  overlap) but tilt peaked at only 25 deg while hung, so tilt cannot see it. Torque is dropped from
  the design anyway per Aaryan, so a lift is currently NOT detected. Stated, not hidden.
- **Prep mode reads ~1.1 Nm with all 12 leg motors at mode=1 (Enable)**, motors-off reads 0.18 Nm.
  So a bare low-torque rule would have flagged prep mode as a fault. Another reason torque is out.
- **The IMU publishes in every FSM state**, including prep and with motors disabled. That is why
  IMU-only works.
- **hg quaternion order is wxyz.** Read as xyzw it returns 178 deg on a healthy standing robot, an
  instant false trip.
- Branch sweep of 1,606 refs: nothing in dimos consumes any hardware fault field. Only `foot_force`
  gates behaviour, on one Go2 branch.

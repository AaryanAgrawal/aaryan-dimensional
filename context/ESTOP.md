# E-stop module

A dimos module that latches an e-stop and stops the robot. Written in Rust. Any robot, any
blueprint, on by default.

No Linear ticket yet. PRD goes on Linear as a project description (Engineering v2, PRD template).
Tech spec goes on GitHub.

- Branch: `aaryan/estop-rust`, off `upstream/main` @ `6fcc4e2d5`. Worktree
  `workspace/dimos/.claude/worktrees/estop-rust`.
- Lives at `dimos/control/estop/`, beside the `ControlCoordinator` it feeds.
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

`g1_fall_imu.csv`, 1401 rows, committed beside the test. A real measured G1 fall trajectory (two
deliberate falls, peak tilt 81.15 deg, 836 samples above 45 deg), re-encoded as quaternions that
round-trip to the measured tilt within 9.4e-08 deg, with yaw spun at 0.7 rad/s so it also exercises
yaw invariance. The rust test replays it.

## Environment

`cargo` is not on PATH (DIOS trap 1). Use the nix store directly:

```
export PATH=/nix/store/3iax01111k6mxx897z11vl9xa2plr7sw-cargo-1.97.0-x86_64-unknown-linux-gnu/bin:\
/nix/store/c4zd28myz1cm2adkf09wacxk40dpkrn5-rustc-1.97.0-x86_64-unknown-linux-gnu/bin:$PATH
```

The minimal rust module template is `examples/native-modules/rust/src/pong.rs`, 53 lines.

## History: what the Python prototype measured (branch `aaryan/g1-estop`)

Hardware, 2026-08-22. These numbers are why the design looks like it does.

- **Falls:** two deliberate falls, 176,427 samples at ~780 Hz. Trips at 45.1 deg both times, peak
  81.2 deg. Upright baseline 2.03 deg standing in walk mode, 5.94 deg in prep mode. Zero false
  trips across a 10 minute activated-standing baseline.
- **45 deg is a confirmation, not an early warning.** At the crossing the robot is already 65%
  unloaded. `tilt > 30 deg` leads by 300 ms, `tilt > 20 deg` by 778 ms, `gyro > 1.0 rad/s` by
  102 ms. `gyro > 2.0 rad/s` never fired before the trip.
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

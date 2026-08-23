# E-stop module

A rust module with two checks: a fall check on the IMU, and a manual trigger check. Either one
latches `estop=true`. Nothing subscribes to the output yet, so today it stops nothing.

## Why

Nothing in dimos watches for a fallen robot. A sweep of 1,606 branches found no code consuming any
hardware fault field. `ControlCoordinator.set_estop()` exists at `dimos/control/coordinator.py:710`
and fans out to every registered task, but only two arm tasks implement it. No G1 task does, so on
the G1 it is a no-op today. The robot can be on its side while every control loop keeps running.

Rust is an operator requirement. The module is one file, `rust/src/main.rs`, 195 lines including the
licence and the tests.

## Design

```
  imu: Imu ------> tilt vs gravity > max_tilt_deg --+
                                                    +--> latch --> estop: Bool = true
  trigger: Bool -> message data is true ------------+          re-asserted on every sample
```

Ports:

| port      | direction | type   |
| --------- | --------- | ------ |
| `imu`     | in        | `Imu`  |
| `trigger` | in        | `Bool` |
| `estop`   | out       | `Bool` |

Config: `max_tilt_deg`, default 45.0 deg, validated to the range 1.0 deg to 90.0 deg.

Tilt is the angle between the body z axis and gravity.

Latch rule: either check may set the latch, and nothing in the process clears it. Recovery is an
operator action out of band, by restarting the stack. Both checks share the one latch.

Location `dimos/control/estop/`: `rust/src/main.rs` (195 lines), `estop.py` (48), `test_estop.py`
(30), `plot_estop_demo.py` (277), `rust/Cargo.toml` (18), `rust/flake.nix` (42), `Cargo.lock`, and
the test fixture. Branch `aaryan/estop-rust`, cut from `upstream/main @ 6fcc4e2d5`, pushed to the
fork `AaryanAgrawal/dimos`. No PR yet.

## Checks

| check          | signal            | trips when                              | status                        |
| -------------- | ----------------- | --------------------------------------- | ----------------------------- |
| Fall           | `imu.orientation` | tilt > `max_tilt_deg`, default 45.0 deg | verified on a replay          |
| Manual trigger | `trigger`         | message data is true                    | no publisher yet              |

An unreadable orientation is part of the fall check, not a third check.

Any further e-stop event is another check: one input port and one handler that sets the same latch.
The latch, the publish, the re-assert and the logging are shared by every check.

The numbers in the rest of this section come from the earlier python prototype, not from the rust
module.

Fall detection is tilt only. Over the full hardware recording a gyro gate of > 2.0 rad/s fires 115
samples starting 46 s before the fall while the robot is in prep, and > 1.0 rad/s fires 979 samples.
Both would false trip. Torque separated a lifted robot cleanly, but prep mode reads about the same
torque as a fault would, so a torque rule would flag normal prep as a fault. Torque was dropped, and
a lifted robot is not detected by this design.

45 deg is a confirmation, not an early warning. At the crossing the robot is already about 64%
unloaded. Measured in a 6 s window around the first trip, tilt > 30 deg leads by 300 ms and
tilt > 20 deg leads by 778 ms.

## Failure handling

An unreadable orientation counts as fallen. A NaN, an all zero, or a non unit quaternion trips the
latch. A dead IMU stops the robot.

While latched the module re-asserts `estop=true` on every incoming sample. The transport is best
effort, so a single publish can be lost. Publish failures are logged.

The G1 IMU publishes in every FSM state, including prep and with motors disabled. That is why an
IMU only design works.

## Configuration

`max_tilt_deg` is the only option, default 45.0 deg. A blueprint states it only when a robot or a
test wants a different limit. The python wrapper is `estop.py`, 48 lines.

The `imu` port connects by name to a `/imu` publisher. On `unitree_g1_coordinator` the topic is
pinned to `/g1/imu`, so that blueprint needs a remap.

## What it does not do yet

- Wired into zero blueprints. Nothing subscribes to `estop`. Today it stops nothing. On by default
  in every blueprint is the goal, not the current state.
- Never run on a robot. It is verified only against a replayed recording.
- No lift detection. Torque separated a lifted robot cleanly and it was dropped, so a robot picked
  up off the ground reads as upright.
- Fall detection needs a publisher of `sensor_msgs` `Imu`. On main those are `G1WholeBodyConnection`
  (the G1 pelvis IMU), `Mid360` (the lidar IMU, on by default) and `RealSenseCamera` (off by
  default). 2 of the 14 G1 blueprints have an Imu source today.
- `unitree_g1_coordinator` pins the imu topic to `/g1/imu`, not `/imu`, so a port named `imu` needs
  a remap there.
- The kronknav stack `unitree_g1_nav_3d` publishes no Imu at all. Its IMU stays inside the Livox SDK
  feeding Point-LIO and never reaches the dimos graph.
- Nothing publishes `trigger`, so the manual button has no sender.
- No G1 task implements `set_estop`. `G1GrootWBCTask.disarm()` exists at `g1_groot_wbc_task.py:666`
  and holds the current pose, and `ControlCoordinator.set_activated` already fans out to it.

## Verification

Rust module: 6 tests pass. `nix build -L path:.` is green end to end and produces
`result/bin/estop`, 18.6 MB. The `cargoHash` is pinned at
`sha256-G2HU2MLWpYU83yTe5Dt3jGFA6pGe4q3PXUdKrqaAQg4=`.

Mutation tested. Deleting the validity guard fails 2 tests. Making the latch clearable fails 2,
including the recorded replay. The tests are not vacuous.

Replay, over the committed fixture `g1_fall_imu.csv`, 1401 rows: one trip at t=8.37 s at 45.90 deg,
peak 81.15 deg. The latch holds across a recovery down to 9.67 deg that would have un-tripped an
unlatched check, and across a second fall.

What the fixture is: only the tilt magnitude is measured, the real tilt against time of two
deliberate G1 falls. The orientation is SIMULATED. That measured tilt is re-encoded as a synthetic
pure roll composed with a 0.7 rad/s yaw ramp, so pitch is identically zero and yaw is a perfect
ramp, neither of which the robot did. It round-trips to the measured tilt within 9.4e-08 deg.

The numbers below are from the earlier PYTHON PROTOTYPE. The rust module has never run on hardware.

- Two deliberate falls, 176,426 samples, 756 Hz mean. Trips at 45.1 deg both times, peak 81.2 deg.
- Zero false trips across a 10 minute activated standing baseline.
- Upright baseline over the first 60 s of the fall recording: median 5.92 deg, in prep mode.

## Work to land it

1. Implement `set_estop` on `G1GrootWBCTask`, backed by the existing `disarm()`, so
   `ControlCoordinator.set_estop()` reaches the G1.
2. Add the consumer that subscribes to the `estop` stream and calls
   `ControlCoordinator.set_estop(True)`.
3. Add the module to `unitree_g1_coordinator` with a remap to `/g1/imu`, and run it on a G1 against
   a fresh deliberate fall. Record the trip.
4. Publish `trigger` from an operator surface so the manual button has a sender.
5. Give the kronknav stack an Imu publisher, or state that fall detection is off there.
6. Add the module to the remaining blueprints as each gains an Imu source.

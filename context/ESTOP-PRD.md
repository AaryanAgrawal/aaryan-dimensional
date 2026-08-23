**Status:** Draft, 2026-08-23

## 1. Problem

### What is the problem we are solving?

A G1 can fall over and dimos keeps commanding it. The controller keeps sending targets and the task keeps running, because no module in the graph looks at whether the robot is still upright.

There is also no stop signal to send. `ControlCoordinator.set_estop()` exists at `dimos/control/coordinator.py:710` and fans out to every registered task, but only two arm tasks implement it. No G1 task implements it, so on the G1 it is a no-op today. A sweep of 1,606 branches found nothing in dimos consuming any hardware fault field either.

So two things are missing. The stack has no way to notice the robot has fallen, and an operator has no software way to stop it. The only stop today is the physical Unitree remote.

### Why now?

The G1 is the platform for the current control work, and falls happen during that work. A python prototype recorded two deliberate falls, 176,426 IMU samples at 756 Hz mean. Tilt crossed 45 deg on the way down both times and peaked at 81.2 deg, with zero false trips across a 10 minute activated standing baseline. The same prototype showed the IMU publishes in every FSM state, including prep and with motors disabled, so an IMU only check works even when the robot is not activated.

That prototype also ruled out the two cheaper signals, gyro and torque, with measured false trip counts (section 2). Tilt is what is left, and nothing in dimos reads it.

### Existing alternatives

| Alternative | What works | Remaining gap |
| -- | -- | -- |
| Unitree remote | Stops the robot at the hardware level | Needs a human holding it, and tells dimos nothing |
| `ControlCoordinator.set_estop()` | The fan out to every registered task is already written | Only two arm tasks implement it, no G1 task does, and nothing calls it |
| `G1GrootWBCTask.disarm()` (`g1_groot_wbc_task.py:666`) | Holds current pose, already wired to `ControlCoordinator.set_activated` | No e-stop producer reaches it |
| A fall check inside each task | Each task can read its own state | A separate check and threshold per task, and no shared latch |

---

## 2. Solution

### Customer messaging

**The robot stops itself when it tilts too far, and an operator can stop it with one message.** Once stopped it stays stopped until the process restarts. Today the module publishes that stop signal and nothing acts on it yet.

### Solution

One rust module at `dimos/control/estop/`. Three ports:

- `imu: Input<Imu>`, the orientation stream.
- `trigger: Input<Bool>`, the manual stop message.
- `estop: Output<Bool>`, the latched stop signal.

One config field, `max_tilt_deg`, default 45.0 deg, validated to the range 1 to 90.

Two checks share one latch. Fall is the first check, the manual button is the second, and any further e-stop event is another check into the same latch. Nothing in the process clears the latch, so recovery is a restart.

An orientation the module cannot read, NaN, all zeros, or a non-unit quaternion, counts as FALLEN. A broken IMU stops the robot.

While latched, the module re-asserts `estop=true` on every incoming sample, because the transport is best effort and a single publish can be lost. Publish failures are logged.

The module is rust because the operator asked for the stop path to be rust.

### Our current state

The module exists on branch `aaryan/estop-rust`, cut from `upstream/main @ 6fcc4e2d5` and pushed to the fork `AaryanAgrawal/dimos`. It is not in a PR yet.

Files: `rust/src/main.rs` (195 lines including licence and tests), `estop.py` (48), `test_estop.py` (30), `plot_estop_demo.py` (277), `rust/Cargo.toml` (18), `rust/flake.nix` (42), plus `Cargo.lock` and the test fixture.

Six rust tests pass. `nix build -L path:.` is green end to end and produces `result/bin/estop`, 18.6 MB. The `cargoHash` is real: `sha256-G2HU2MLWpYU83yTe5Dt3jGFA6pGe4q3PXUdKrqaAQg4=`. Mutation testing says the tests bite: deleting the validity guard fails 2 tests, and making the latch clearable fails 2, including the recorded replay.

What is not done:

- The rust module has never run on a robot. It is verified against a replayed recording and its own unit tests.
- It is wired into zero blueprints and nothing subscribes to its `estop` output. Today it stops nothing.
- Nothing publishes the `trigger` topic, so the manual button has no sender.
- 2 of the 14 G1 blueprints have an Imu source today. See the Imu prerequisite appendix.
- "Added to every blueprint, on by default" is the goal of this PRD, not the state of the branch.

### Options rejected

- **A gyro gate.** Measured on the python prototype recording: `gyro > 2.0 rad/s` fires 115 samples starting 46 s before the fall while the robot is still in prep, and `gyro > 1.0 rad/s` fires 979 samples. Both false trip. This is why the fall check is tilt only.
- **Torque.** On the python prototype it separated a lifted robot cleanly, but prep mode reads about the same torque as a fault would, so a torque rule flags normal prep as a fault. Dropped, and the consequence is that a lifted robot is not detected by this design.
- **A lower tilt threshold as an early warning.** Measured on the python prototype in a 6 s window around the first trip, `tilt > 30 deg` leads by 300 ms and `tilt > 20 deg` by 778 ms. Only 45 deg has a measured false trip count, zero over the 10 minute standing baseline, so the default stays 45 deg. At the 45 deg crossing the robot is already about 64% unloaded, so this is a confirmation rather than a prediction.
- **An unlatched check.** The recorded fall recovers to 9.67 deg between the two falls, which would un-trip an unlatched check while the robot is still in trouble.
- **Python.** The prototype behind every hardware number here is python and kept up at 756 Hz mean. Rust is an operator requirement for this module, not a measured need.

### Not in this PRD

- Who sends the `trigger` message. A UI button, a joystick, or an RPC is separate work.
- Lift detection.
- Any change to the Unitree FSM or the physical remote.
- Automatic recovery or a reset path.

---

## 3. User stories

As an operator I can add the e-stop module to a blueprint with no options set, because I want the default protection without reading a config guide.

As an operator I can send one message and have the robot stop, because I want a stop that does not need me standing next to the remote.

As a researcher I can raise `max_tilt_deg` for a robot that works at high tilt, because I want the check tuned to my platform rather than turned off.

As an integrator I can subscribe to one `estop` bool, because I want a single signal to react to instead of a fault field per driver.

---

## 4. Success metrics

| Outcome | Target | How measured |
| -- | -- | -- |
| The rust module trips on a real fall | Both deliberate G1 falls trip | Run the rust module live on the G1 during two deliberate falls, read the `estop` publish timestamps against logged tilt |
| No false trips in normal operation | Zero `estop=true` across a 10 minute activated standing baseline, and zero during prep | Live run on the G1, count publishes |
| The latch holds | `estop` stays true for the rest of the process after the first trip, including through the recovery to 9.67 deg | The committed replay test in CI, plus the hardware run above |
| Something stops | The G1 WBC task disarms and holds pose on both hardware trips | Hardware run, task logs plus observed pose hold |
| Coverage | The module is in every G1 blueprint, and each G1 blueprint either has an Imu source or is recorded as having no fall detection. 2 of 14 have an Imu source today | Count blueprints in the repo, checked by a test |

---

## 5. Technical implementation sketch

```
  Imu (sensor_msgs)                trigger (Bool)
        |                                |
        v                                v
  +-------------+                 +-------------+
  | tilt check  |                 | manual stop |
  | unreadable  |                 |             |
  | quat = FALL |                 |             |
  +-------------+                 +-------------+
        |                                |
        |          +----------+          |
        +--------> |  LATCH   | <--------+
                   |  (bool)  |
                   +----------+
                        |
                        | re-asserted on every Imu sample
                        v
                   estop (Bool)
```

Tilt comes from the orientation quaternion in the Imu message. If that quaternion is NaN, all zeros, or not unit length, the sample counts as FALLEN.

Each check writes into the latch and never clears it. Adding a third e-stop event later means one more input and one more write, with no change to the two that exist.

The module builds with nix. `nix build -L path:.` produces `result/bin/estop` at 18.6 MB, with a pinned `cargoHash`.

Rollout, in order:

1. Land the module and its tests behind a PR, wired into no blueprint.
2. Give the G1 a `set_estop()` that calls the existing `G1GrootWBCTask.disarm()`, so `ControlCoordinator.set_estop()` stops being a no-op on the G1.
3. Run it on the robot, in a deliberate fall, and record the result.
4. Close the Imu source gap in the G1 blueprints, or record per blueprint that fall detection is off there.
5. Add it to blueprints, on by default.

---

## 6. Link of full technical implementation

https://github.com/dimensionalOS/dimos/issues/3621

---

## 7. Optional appendices

### Limitations

- **The rust module has never run on a robot.** Every hardware number in this document comes from the earlier python prototype. The rust module is verified against a replayed recording and its own unit tests.
- **A lifted robot is not detected.** Torque separated a lifted robot, and torque was dropped because prep mode reads about the same torque as a fault. A robot held off the ground and upright looks normal to this design.
- **45 deg is a confirmation, not an early warning.** At the crossing the robot is already about 64% unloaded. The module stops the stack from making things worse, it does not catch the robot.
- **Recovery means restart.** Nothing in the process clears the latch.
- **The manual button has no sender yet.** The input port exists and nothing publishes to it.
- **Nothing consumes `estop` yet.** Until step 2 of the rollout lands, the signal is published and ignored.

### The Imu publisher prerequisite

Fall detection needs something publishing a `sensor_msgs` Imu into the dimos graph. On main the publishers are `G1WholeBodyConnection` (the G1 pelvis IMU), `Mid360` (the lidar's own IMU, on by default), and `RealSenseCamera` (off by default).

Two gaps block "every blueprint":

- `unitree_g1_coordinator` pins the imu topic to `/g1/imu`, not `/imu`, so a module with a port named `imu` does not connect there without a remap.
- The kronknav stack, `unitree_g1_nav_3d`, publishes no Imu at all. The IMU stays inside the Livox SDK feeding Point-LIO and never reaches the dimos graph.

Counted, 2 of the 14 G1 blueprints have an Imu source today. Closing that gap is rollout step 4, not an assumption.

### Test fixture

`g1_fall_imu.csv`, 1401 rows, committed beside the test.

The **orientation in this fixture is SIMULATED**. Only the tilt magnitude is measured, the real tilt against time of the two deliberate G1 falls. That measured tilt is re-encoded as a synthetic pure roll composed with a 0.7 rad/s yaw ramp, so pitch is identically zero and yaw is a perfect ramp, neither of which the robot did. It round-trips to the measured tilt within 9.4e-08 deg.

Replay result: one trip at t=8.37 s at 45.90 deg, peak 81.15 deg. The latch holds across a recovery down to 9.67 deg that would have un-tripped an unlatched check, and across a second fall.

### Hardware measurements, all from the python prototype

- Two deliberate falls, 176,426 samples, 756 Hz mean. Trips at 45.1 deg both times, peak 81.2 deg.
- Zero false trips across a 10 minute activated standing baseline.
- Upright baseline over the first 60 s of the fall recording: median 5.92 deg, in prep mode.
- `tilt > 30 deg` leads the 45 deg crossing by 300 ms, `tilt > 20 deg` by 778 ms, measured in a 6 s window around the first trip.
- `gyro > 2.0 rad/s` fires 115 samples starting 46 s before the fall, while the robot is in prep. `gyro > 1.0 rad/s` fires 979 samples.
- The IMU publishes in every FSM state, including prep and with motors disabled. That is why an IMU only design works.

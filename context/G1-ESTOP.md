# G1 e-stop — fall / lowstate-loss detection

No Linear ticket yet. Wired into kronknav (DIM-1503) because that stack has a MovementManager and
no ControlCoordinator.

- Branch: `aaryan/g1-estop`, cut from `andrew/feat/g1-kronk-nav` @ `a87c3b93e`, pushed to the fork
  `AaryanAgrawal/dimos`. **Not** on Andrew's branch and not in any PR.
- Related: DIM-1503 (kronknav), DIM-1494 (G1 nav test)
- Status: written, unit-tested, detector hardware-verified in isolation. **Never run inside a live
  kronknav stack.** That is the next step.

## What it is

```
rt/lowstate (DDS, 500 Hz) -> [silent? fallen?] -> estop: Out[Bool] -> MovementManager gate
```

`dimos/robot/unitree/g1/g1_estop.py` (149 lines) + a 4-line gate in `movement_manager.py`.
259 lines added, 0 removed, 6 files. The module decides; it does not drive.

Checks run highest-priority first, and the latch never clears in process:

1. `lowstate silent` — no LowState for `lowstate_timeout_sec` (default 0.5 s)
2. `fallen` — pelvis tilt > `max_tilt_deg` (default 45 deg)

## Why it reads DDS and not LCM

No LCM signal is common to both stacks: kronknav publishes no `Imu`, groot sim publishes no
`Odometry`. `rt/lowstate` is identical on both at 500 Hz. The pelvis IMU is gravity-referenced, so
it needs no mount correction — which is why the third copy of `diag(1,-1,-1)` was deleted rather
than moved. The LIO pose is the wrong signal regardless: scan matching degrades during the very
event being detected.

## Verified

Unit: `dimos/robot/unitree/g1/test_g1_estop.py` (5 tests) + 1 test in `test_movement_manager.py`.
Full sweep on the branch: 125 passed, 4 skipped. ruff + mypy clean.

Hardware, 2026-08-21, real robot, bus otherwise idle:
- 45 deg shipped threshold, 8 s standing: 351 publishes at 44 Hz, **zero false trips**.
- Forced 1 deg threshold: tripped on real data (`tilt_deg=1.8`), latched, asserted `estop=True` on
  373/373 later cycles — the latch holds and a late subscriber still sees the stop.

## Gotchas that cost time

- **hg `imu_state.quaternion` is wxyz.** Confirmed to 4.8e-11 against the same frame's `rpy`.
  Reading it as xyzw gives 178 deg on a healthy standing robot, i.e. an instant false trip.
- **It fails safe, which looks like broken nav.** If `rt/lowstate` is unreachable from the worker it
  latches in 0.5 s and blocks all movement. Correct behaviour, confusing symptom — check
  `network_interface` (default `eth0`) first.
- `ChannelFactoryInitialize` is process-global. Coexistence with `G1HighLevelDdsSdk` +
  `G1TfPublisher` is proven on kronknav; **unproven alongside `G1WholeBodyConnection`** on groot.

## Next actions

1. Run it inside a live kronknav stack and confirm a trip actually halts the robot. Nothing has
   exercised the detector -> MovementManager -> stop path end to end.
2. Add the groot tail: `set_estop` on `G1GrootWBCTask` latching and calling the **existing**
   `disarm()`. ~6 lines, no card change, since `coordinator.set_estop` duck-types.
3. Decide on a `motorstate` tripwire. Measured 0 on all 29 motors both idle **and while activated
   and balancing** (2026-08-22), so the baseline now exists. Nonzero is a fault code by definition.
4. Hung-up / "tweaking out" detection is still unsolved. Tilt does not catch a robot lifted off the
   ground. New on 2026-08-22: with the robot **activated**, knee `tau_est` reads 11-24 Nm
   (`knee_tau_mean` p50 13.1 over 2780 samples, `loaded.csv`). Every earlier capture read ~0 only
   because the motors were disabled, so torque **is** viable after all. Still need a `hung_up`
   capture with the robot hoisted to set a threshold. Do not guess one.

## How to work on it

```bash
# tests
.venv/bin/python -m pytest dimos/robot/unitree/g1/test_g1_estop.py \
  dimos/navigation/movement_manager/test_movement_manager.py -q

# drive the real watch loop against live rt/lowstate on the robot (passive, safe beside a stack)
#   /tmp/g1check/estop_drive.py on the G1 — instantiate, set _subscriber, run _watch_loop
```

Robot readings, not Point-LIO: `python /tmp/g1check/fsm.py` on the G1 prints `mode_machine`, tilt,
knee `tau_est` and any nonzero `motorstate` in one shot. `mode_machine=5` means activated and
balancing; `0` is ZERO_TORQUE.

## Architecture notes from the branch sweep (1,606 refs)

- **Nothing in dimos consumes any hardware fault field.** Motor `temperature`, motor `lost`,
  `bms_state.status`, `cell_vol`, `power_a`, `fan_frequency`, `wireless_remote` are all decoded and
  dropped. The only hardware value anywhere that gates behaviour is `foot_force`, on one Go2 branch.
- `ControlCoordinator.set_estop()` exists and fans out via `getattr(task, "set_estop")`, but only
  two arm tasks implement it — **no G1 task does, so on the G1 it is a no-op today.**
- `G1GrootWBCTask.disarm()` already exists, docstring: "Called either from an operator Disarm button
  or from safety watchdogs." The watchdog it was written for was never built. This is that watchdog.
- Unusable as fault signals: `ddq` (exactly 0.0 across 6259 frames), `lost` (a go2 field, absent on
  hg). `tau_est` was on this list until the activated measurement above.
- Deliberately not thresholded: motor `temperature` (33-45 C idle) and `vol` (51.0/51.5 V). No
  legged thermal or undervoltage limit exists anywhere in the repo, and inventing one from an idle
  sample would be a guess with a decimal point.
- `wireless_remote` is on the wire and decoded by nothing. The operator already holds that remote,
  so its stop button is arguably the highest-value unread field in the struct. Byte layout for hg is
  **unverified** — treat as a lead, not a plan.

# G1 e-stop - tech spec

One module watches `rt/lowstate` over DDS and latches an e-stop on the first check that trips. Two tails consume the latch: groot through `ControlCoordinator`, kronknav through `MovementManager`.

## Kill path

```
  rt/lowstate  (DDS)
       |
   g1_estop      checks in priority order, first match wins, latches      [built]
       |
       |  estop: Out[Bool]                                                [to build: the bridge]
       v
   ControlCoordinator.set_estop(True)   @rpc, dimos/control/coordinator.py:710, on main
       |
       |  takes _task_lock, getattr(task, "set_estop", None) on every task
       v
   G1GrootWBCTask.set_estop -> disarm()                                   [to build: ~6 lines]
       |
       v
   every task inert, tick loop stops commanding hardware within one tick
```

Highest priority path: the stop makes every task inert under one lock, so it lands whatever else is publishing. Synchronous by design, per the RPC's own docstring: "Synchronous RPC (not a stream) so E-STOP can't be dropped under load." The coordinator logs `E-STOP latched at coordinator`.

Gap: `set_estop` is implemented by two ARM tasks (`teleop_task.py:106`, `eef_twist_task.py`). No G1 task implements it, so on the G1 the RPC is a no-op today. Closing it is ~6 lines on `G1GrootWBCTask`: latch, then call the existing `disarm()` at `dimos/control/tasks/g1_groot_wbc_task/g1_groot_wbc_task.py:666` ("Stop emitting policy outputs; fall back to hold-current-pose. Called either from an operator Disarm button or from safety watchdogs."). `disarm()` has had no caller; this is it. `_registry.py` already lists the task's exposed methods and the coordinator duck-types via `getattr`, so no card change.

## kronknav tail

kronknav has no coordinator. `MovementManager` gates on `estop: In[Bool]`: publish one zero Twist, cancel the goal, ignore nav and teleop after. `G1HighLevelDdsSdk` also auto-stops on its 0.2 s `cmd_vel_timeout`. Strongest stop available there is `loco_client.Damp()` via `lie_down()` at `dds_sdk.py:281`.

The detector is the same on both stacks: it reads `rt/lowstate` over DDS, which both receive identically.

Zeroing `cmd_vel` is not a stop on groot: `cmd_vel` becomes the coordinator's `twist_command`, so a zero twist tells the policy to walk in place. A fallen robot needs `disarm()`.

## Checks

Priority order, first match wins, the latch holds. Any e-stop event is another row.

| check | signal | trip | status |
| --- | --- | --- | --- |
| lowstate silent | LowState arrival | no message for > 0.5 s | shipped |
| fallen | hg IMU fused quaternion, `tilt = acos(1 - 2*(x^2+y^2))` | tilt > 45 deg | shipped |
| button | operator | manual | to build |
| lifted | knee_tau, gated on walking or standing | knee_tau < 6 Nm | proposed |

Quaternion component order is wxyz: it agrees with the same frame's rpy to 4.8e-11, where xyzw reads 178 deg on a healthy standing robot.

45 deg trips against a 5.94 deg upright baseline in prep mode and 2.03 deg standing in walk mode, with zero false trips over a 10 minute activated-standing baseline (hardware, 2026-08-22, two deliberate falls, 176,427 samples at ~780 Hz, peak tilt 81.2 deg). It is a confirmation, not an early warning: at the crossing the robot is already 65% unloaded.

Tilt tops out at 25 deg while the robot hangs, so the lift check reads knee_tau instead (205k samples): lifted p95 3.08 Nm against standing p05 11.69 Nm, threshold 6 Nm at ~2x margin either side. Prep mode reads ~1.1 Nm with all 12 leg motors at mode=1 (Enable), so the torque check is gated on a walking or standing state.

The IMU publishes in every FSM state, including prep mode and with motors disabled.

## E-stop button

An operator-triggered manual trip beside the automatic detectors. It sets the same latch and takes the tail of the stack it runs on.

## Configuration

Per blueprint. The blueprint names which checks run and any threshold that differs from the module default. Shape:

    g1_estop:
      checks: [lowstate_silent, fallen, lifted]
      lifted: {knee_tau_nm: 8}

## Work items

1. `set_estop` on `G1GrootWBCTask`: latch, call `disarm()`.
2. Bridge the latched `estop: Out[Bool]` to `ControlCoordinator.set_estop` in the groot blueprint. One hop, still to design.
3. E-stop button into the same latch.
4. Per blueprint check selection and thresholds.
5. Lift check on knee_tau, gated on walking or standing.

Reset: the latch holds for the life of the process, so recovery is a module restart. `set_estop(estopped: bool)` takes False, so the coordinator side clears.

## Not doing

No thermal or undervoltage gate: temperature reads 33-45 C idle, `vol` reads 51.0 / 51.5 V, and no legged limit for either exists in the repo. `ddq` (0.0 across 6259 frames), `motor lost` (a go2 field) and `motor mode` (1/Enable in prep and in walk) carry no usable signal on hg. A gyro > 2.0 rad/s gate never fired before the trip.

A branch sweep of 1,606 refs found nothing in dimos consuming a hardware fault field: `bms_state.status`, `cell_vol`, `power_a`, `fan_frequency`, `wireless_remote` are decoded and dropped. Only `foot_force` gates behaviour, on one Go2 branch.

---

`aaryan/g1-estop` off `andrew/feat/g1-kronk-nav`: `dimos/robot/unitree/g1/g1_estop.py`, 149 lines, 259 added / 0 removed across 6 files. DDS reader copied from `g1_tf_publisher.py:171-195`. 125 tests pass, ruff and mypy clean.

# E-stop module

- PRD: https://linear.app/dimensional/project/e-stop-module-dce7e0091e2e
- Tech spec: https://github.com/dimensionalOS/dimos/issues/3621
- Branch: `aaryan/estop-rust`

## Decisions

Condition 1 is manual stop and condition 2 is humanoid fall detection; either condition sets one latch, only a healthy manual reset clears it, and reset never starts the robot.

Each embodiment owns an E-stop defaults bundle that every root blueprint composes.

## Verification

The real Rust module replayed 1,401 samples over LCM at recorded speed, publishing its first `true` at 8.3712 s and staying latched through recovery and a second fall.

The tilt was measured on a G1, but the orientation is **SIMULATED** because the raw quaternion recording remains on the offline robot.

![Fall replay](estop-fall-replay.png)

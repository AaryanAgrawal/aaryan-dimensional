# E-stop module

Add a Rust latching e-stop. Any condition can be added to set it, and only a manual reset can clear it.

## Current proposed conditions

1. **Manual stop:** `trigger=true` latches the e-stop.
2. **Humanoid fall detection:** unreadable IMU orientation or tilt above the configured limit latches the e-stop.

Each condition owns one typed input and one small check; adding one means adding its file, input handler, and physical config.

```text
control/estop/
├── conditions/manual.rs
├── conditions/humanoid_fall.rs
└── rust/src/main.rs
```

## Manual reset

`reset=true` clears the latch only when every condition is healthy, and leaves the robot disarmed until a separate start command.

## Embodiment defaults

Each embodiment owns one EStop-default bundle, and every root blueprint for that embodiment composes it.

```python
g1_estop_defaults = EStop.blueprint(max_tilt_deg=45.0)
g1_root = autoconnect(g1_hardware, g1_estop_defaults)
```

Derived blueprints inherit the bundle from their root. `autoconnect` links `imu`, and `estop` must reach `ControlCoordinator.set_estop()`.

Not run on hardware yet.

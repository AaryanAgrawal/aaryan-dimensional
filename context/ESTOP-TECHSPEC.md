# E-stop module

Add a Rust e-stop with one latch; any condition can set it, and only a manual reset can clear it.

## Conditions

1. **Manual stop:** `trigger=true` latches the e-stop.
2. **Humanoid fall detection:** unreadable IMU orientation or tilt above the configured limit latches the e-stop.

Each condition owns one typed input and one small check.

```text
control/estop/
├── conditions/manual.rs
├── conditions/humanoid_fall.rs
└── rust/src/main.rs
```

## Manual reset

`reset=true` clears the latch only when every condition is healthy, and a separate start command arms the robot.

## Embodiment defaults

Each embodiment owns one E-stop defaults bundle, and every root blueprint for that embodiment composes it.

```python
g1_estop_defaults = EStop.blueprint(max_tilt_deg=45.0)
g1_root = autoconnect(g1_hardware, g1_estop_defaults)
```

Derived blueprints inherit the bundle from their root, while `autoconnect` links `imu` and `estop` reaches `ControlCoordinator.set_estop()`.

Not run on hardware yet.

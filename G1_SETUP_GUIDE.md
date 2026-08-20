# Unitree G1 Setup Guide (Fresh Unit to Running dimos)

A step by step guide to take a newly unboxed Unitree G1 from the box to running a
dimos blueprint. Every step lists the command, what to expect, and the common failure
and its fix. Written from a real fresh bring up, so the gotchas are the ones you will
actually hit.

## What you need

- The G1, powered on.
- The handheld controller (this is your emergency stop, keep it in hand once the robot is live).
- The Ethernet cable and the USB C cable that ship with the robot.
- A laptop running Linux with NetworkManager.
- Your office WiFi name and password.

## How the G1 network is laid out (read this first)

The G1 is not one computer. It is several small computers on an internal wired network
`192.168.123.0/24`, joined by an internal switch.

- Development computer (Jetson). Fixed address `192.168.123.164`. Runs Ubuntu 20.04.
SSH is open here. This is where you run dimos. Login user `unitree`, password `123`.
- Control computer. This is the box the Unitree mobile app talks to. It shows up on your
WiFi at a different address (for example `10.0.0.245`) and its internal address is
usually `192.168.123.161`. SSH is closed here. It is not your target.
- Mid360 lidar. Internal address `192.168.123.120`.

Key point: the IP the mobile app shows you is the control computer, not the computer you
SSH into. Always work against the Jetson at `192.168.123.164`.

Both external Ethernet jacks on the robot reach the same internal switch, so either jack
gets you to the Jetson.

## Step 1. Wired SSH access

Plug the Ethernet cable from the robot into your laptop.

Find your laptop wired interface name:

```bash
ip -br link show
```

Look for an entry like `enp2s0` or `enp130s0` (not `wlan` and not `docker`). Use that name
below in place of `WIRED_IFACE`.

Give your laptop a static address on the robot internal network. A persistent
NetworkManager profile is better than a one shot `ip addr add`, because it survives
reboots and unplugging:

```bash
sudo nmcli connection add type ethernet ifname WIRED_IFACE con-name g1-wired \
     ipv4.method manual ipv4.addresses 192.168.123.100/24
sudo nmcli connection up g1-wired
```

Why `192.168.123.100`: the robot is `.164`, and two devices can only talk directly when
they share the subnet. `.100` is a free address on `192.168.123.0/24`.

Confirm the address landed:

```bash
ip addr show WIRED_IFACE     # expect: inet 192.168.123.100/24
```

Prove you can reach the robot before trying SSH. This isolates a network problem from a
login problem:

```bash
ping -c3 192.168.123.164     # expect 0 percent packet loss
```

SSH in:

```bash
ssh -L 3030:localhost:3030 unitree@192.168.123.164
# password: 123
```

What to expect:

- First connection shows a host key fingerprint prompt. Type `yes`.
- The `-L 3030:localhost:3030` part opens a tunnel so the blueprint keyboard and viewer
controls on port 3030 of the robot are reachable at `localhost:3030` on your laptop.
Keep this flag.
- After login you land on a selector: `ros:foxy(1) noetic(2) ?`. Type `1`. This only loads
a ROS environment into the shell. It changes nothing on the robot and is asked every login.

You are now at `unitree@ubuntu:~$`.

## Step 2. Connect the G1 to WiFi

On a fresh unit the Jetson WiFi is not connected. Check:

```bash
hostname -I
```

If you only see `192.168.123.164` and a `172.x` docker address, WiFi is not joined yet.
Confirm the radio is up but idle and not blocked:

```bash
nmcli device status     # wlan0 should read 'disconnected' (managed, ready)
rfkill list             # both Soft blocked and Hard blocked should read: no
nmcli device wifi list | grep -i YOUR_WIFI_NAME     # confirm the network is visible
```

Do not use `nmcli device wifi connect`. On this robot it fails with
`Secrets were required, but not provided (7)` even when the password is correct. The
cause is a WPA2 and WPA3 mixed network combined with the older wpa_supplicant on
Ubuntu 20.04, which mishandles the WPA3 (SAE) handshake.

Instead build an explicit WPA2 profile, which forces the working handshake:

```bash
sudo nmcli connection delete YOUR_WIFI_NAME 2>/dev/null
sudo nmcli connection add type wifi ifname wlan0 con-name YOUR_WIFI_NAME \
     ssid "YOUR_WIFI_NAME" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "YOUR_WIFI_PASSWORD"
sudo nmcli connection up YOUR_WIFI_NAME
```

The `wifi-sec.key-mgmt wpa-psk` setting is the fix. It negotiates WPA2 only and skips the
WPA3 handshake that breaks. NetworkManager saves the profile, so the robot reconnects on
every boot.

Verify:

```bash
nmcli device status     # wlan0 should now read 'connected'
hostname -I             # a 10.0.0.x address now appears
ip addr show wlan0      # confirm inet 10.0.0.x/24
ping -c2 8.8.8.8        # should reply, meaning the robot now has internet
```

The new `10.0.0.x` is the Jetson own WiFi address, and it is DHCP so it can change on
reboot.

## Step 3. Untethered SSH

Prove WiFi SSH works before you unplug, so a failure cannot lock you out. From a new
laptop terminal, leaving the wired session running:

```bash
ssh -L 3030:localhost:3030 unitree@10.0.0.WIFI     # use the address from hostname -I
```

If you land at the `unitree@ubuntu` prompt, WiFi SSH is proven. You can now unplug the
Ethernet cable.

## Step 4. Install dimos

Run on the robot:

```bash
bash <(curl -fsSL https://pub-4767fdd15e6a41b6b2ce2558d71ec8d9.r2.dev/install.sh)
```

This runs the `dim` installer. Answer the prompts:

- Install dim to /home/unitree/.local/bin/dim: Yes.
- DimOS desktop web UI: your choice. Start now and on boot is fine.
- Open desktop now: No. The robot is headless, so a browser cannot open there.
- Jetson max performance: Yes for testing. It sets full CPU and GPU clocks. It uses more
power and heat, so keep the robot on the charger for long sessions. It is reversible.
- Apply network optimizations for LCM, and persist across reboots: Yes.
- How do you want to use DimOS: Developer (git clone and editable install).
- How should we install system packages: System packages (apt). Simpler than Nix on this box.
- Install destination: accept the default `/home/unitree/dimos`.
- Install dependencies now: Yes.
- Downgrade numpy to below 2.0 for Unitree SDK compatibility: Yes. The Unitree SDK requires it.

Notes on things that look alarming but are fine:

- After install, a conda traceback can appear on login. It is harmless. dimos uses its own
virtual environment at `~/dimos/.venv`, not conda.
- The installer may print that the Unitree SDK import failed while checking. This is an
ordering issue. It sets `CYCLONEDDS_HOME` after the check. It works in a fresh shell.

Verify:

```bash
echo "CYCLONEDDS_HOME=$CYCLONEDDS_HOME"     # should be set
cd ~/dimos && source .venv/bin/activate
python -c "import cyclonedds; print('cyclonedds OK')"
python -c "import unitree_sdk2py; print('unitree_sdk2py OK')"
dimos --help
```

## Step 5. Run a blueprint

Before running, plug in the USB C cable that ships with the robot. This is the head camera
cable. If it is not connected, the camera does not enumerate and the app camera feed stays
blank.

If a native module needs a source that is fetched over SSH from GitHub, the build fails on
a fresh robot with `Permission denied (publickey)`, because the robot has no GitHub SSH
key. The affected repositories are public, so rewrite GitHub SSH to HTTPS once:

```bash
git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
```

Start the walking and navigation blueprint, with the viewer bound to all interfaces so a
laptop can connect:

```bash
cd ~/dimos && source .venv/bin/activate
dimos --rerun-host 0.0.0.0 run unitree-g1
```

What to expect on first run:

- dimos builds native modules with Nix. This is a one time cost and later runs skip it.
- If you are on a branch that still uses the CMU navigation stack, it compiles PCL and VTK,
which are very large and can run the Jetson out of memory. The failure signature is
`g++: fatal error: Killed signal terminated program cc1plus`. Build one module at a time
with capped parallelism, for example inside the module folder run
`nix build .#default --no-write-lock-file --cores 4`, or add swap. The lighter blueprint
path avoids this by using ray tracing and A star navigation instead.

Safety, because this blueprint stands the robot up and can walk it. Read the safety section
below before it connects.

## Step 6. View the visualization

The dimos viewer is a native application called `dimos-viewer`, not a web page. The robot
is headless, so the viewer cannot open there. Run it on your laptop, which has a screen.

When the blueprint starts it prints a Connect a viewer block with the exact command per
interface. It looks like:

```bash
dimos-viewer --connect rerun+http://10.0.0.WIFI:9877/proxy --ws-url ws://10.0.0.WIFI:3030/ws
```

Run that on your laptop, using the robot WiFi address. A window opens showing the robot
model, the floor, and the lidar and costmap once the Mid360 is streaming.

Do not open port 80 on the robot in a browser. That is the Unitree firmware update page,
not dimos. Do not use Factory Reset there.

## Safety before the robot moves

The `unitree-g1` blueprint connects the high level SDK, which stands the robot up, and a
movement manager, which can walk it.

- Put the robot on a gantry or otherwise supported for first stand. This is the highest
fall risk moment.
- Keep the controller in hand. Damping is your emergency stop.
- Clear the area of people and obstacles.
- The SDK may not have movement authority until you hand it over on the controller. The
robot logs the sequence, for example L1 and A, then L1 and Up. Decide before you press it.

Sitting the robot down properly is a controlled state, not damping. Damping makes a
free standing robot collapse. Use the controller sit or squat function from the manual, or
the dimos SIT state, and always over support.

## Troubleshooting

| Symptom                                                       | Cause                                           | Fix                                                                               |
| ------------------------------------------------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------- |
| `hostname -I` shows no `10.0.0.x`                             | Jetson WiFi not joined                          | Step 2 explicit WPA2 profile                                                      |
| `nmcli device wifi connect` gives `Secrets were required (7)` | WPA3 handshake fails on old wpa_supplicant      | Use the explicit `wifi-sec.key-mgmt wpa-psk` profile                              |
| App shows an IP but SSH refused there                         | That IP is the control computer, not the Jetson | SSH to `192.168.123.164` or the Jetson WiFi address                               |
| Native build ends in `Killed ... cc1plus`                     | Out of memory compiling PCL                     | Cap `--cores`, add swap, or use the ray tracing blueprint                         |
| Native build `Permission denied (publickey)`                  | Public repo fetched over SSH, robot has no key  | `git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"` |
| App camera feed blank                                         | Head camera USB C cable not plugged in          | Connect the USB C cable, confirm with `ls /dev/video*`                            |
| Viewer page in browser says WebSocket error                   | The viewer is a native app, not a web page      | Run `dimos-viewer` on the laptop                                                  |
| Conda traceback on login after install                        | conda and ROS shell conflict                    | Harmless, dimos uses its own venv                                                 |
| SSH gives `Permission denied (publickey)`, no password prompt | This unit has SSH password auth disabled (a non default, pre configured bot). Confirm with `ssh -v ... \| grep "authentications that can continue"` showing only `publickey` | No network fix. Get a local console: the USB-C port is Alt Mode DP, so use a USB-C to HDMI adapter plus a USB keyboard, log in `unitree`/`123`, then add your laptop key to `~/.ssh/authorized_keys` or re-enable `PasswordAuthentication yes`. Or have whoever set up the bot authorize your key |
| `import torch: cannot allocate memory in static TLS block`    | The `main` `unitree-g1` blueprint pulls the perception/memory stack which imports torch; aarch64 static TLS exhaustion | Use PR #3057 (`unitree-g1` there is ray tracing, no torch). Fallback on main: `export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libgomp.so.1` |
| `dimos` gives `ModuleNotFoundError: No module named 'dimos.cli.dimos'` | You checked out a branch that moved the CLI entry point; the installed launcher is stale | `uv pip install -e . --no-deps` to regenerate the console scripts, then run again |
| Blueprint says `nix: command not found` right after install   | On a bot with no preinstalled Nix, the installer just added Nix, not on PATH in this shell | Open a fresh SSH session (or log out and back in) before running the blueprint |

## Optional. Stable remote access with Tailscale

The Jetson WiFi address is DHCP and changes. Installing Tailscale on the Jetson gives it a
permanent address that works across networks, so you stop chasing the WiFi IP. Set it up
once the robot has internet.

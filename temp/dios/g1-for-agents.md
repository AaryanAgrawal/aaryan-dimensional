# Running dimos on the G1 — instructions for an agent

You are working on a Unitree G1 humanoid at **10.0.0.188**. It is already set up: dimos is
installed, the robot is on wifi, SSH works. You do not need to install anything.

**When you hit an error, append it to "Errors seen" at the bottom of this file** — the full message,
the command that produced it, and what you tried. That is the point of this document. Everything in
"Known errors" below was found the same way.

Do not skip "Before the robot moves". It is a 35 kg humanoid.

## 1. Turn the robot on

**Press the power button once, then press and hold it.** One short press, then a long press — a
single press alone does nothing. Do this on the battery, then on the robot if it has its own button.

Give it a couple of minutes to boot. It is up when it answers:

```bash
ping -c3 10.0.0.188
```

Nothing below works until that replies.

## 2. Connect

```bash
ssh unitree@10.0.0.188      # password: 123
```

Jetson Orin NX, Ubuntu 20.04, aarch64, glibc 2.31. `~/dimos` is the checkout, `~/dimos/.venv` its
virtualenv. The robot's wired address on its own internal network is `192.168.123.164`; `10.0.0.188`
is its wifi address and is **DHCP, so it can change** — if it stops answering, ask Aaryan for the
new one.

## 3. Run a blueprint

```bash
cd ~/dimos && source .venv/bin/activate
export LD_PRELOAD=/lib/aarch64-linux-gnu/libGLdispatch.so.0:/usr/lib/aarch64-linux-gnu/libgomp.so.1
dimos --robot-ip 192.168.123.161 --rerun-open none --rerun-host 0.0.0.0 run unitree-g1
```

All three parts matter, and each one corresponds to a real failure below:

- `LD_PRELOAD` — without it the perception stack cannot import at all.
- `--robot-ip 192.168.123.161` — without it dimos dials a host literally named `none`.
- `--rerun-open none` — without it dimos opens a GUI on this headless robot and crashes.

If it asks `Apply these changes now? [y/N]` about multicast, answer **y**. It will ask on every boot.

`dimos list` shows every blueprint. `dimos status`, `dimos log`, `dimos stop` from a second SSH
session.

## 4. View it (on your laptop, not the robot)

The robot is headless. The viewer runs on your machine:

```bash
dimos-viewer --connect rerun+http://10.0.0.188:9877/proxy --ws-url ws://10.0.0.188:3030/ws
```

The run prints this exact line for each interface when it starts — prefer the printed one. Keyboard
teleop and click-to-navigate are built into that window.

## 5. Before the robot moves

The `unitree-g1` blueprint connects the high-level SDK, which **stands the robot up**, and a
movement manager that can walk it.

- Robot on a gantry or otherwise supported. First stand is the highest fall risk.
- Physical controller in hand. **Damping is the emergency stop.**
- Clear the area of people and obstacles.
- The SDK may not have movement authority until it is handed over on the controller — the robot logs
  the sequence, e.g. `L1+A` then `L1+Up`. Decide before pressing it.
- Sitting down is a controlled state, not damping — damping makes a standing robot collapse. Use the
  controller's sit/squat or the dimos SIT state, always over support.
- **This G1 is shared. Tell Aaryan before you make it move.**

## 6. Known errors

| What you see | Why | Do this |
| --- | --- | --- |
| `Apply these changes now? [y/N]` about multicast | LCM needs multicast on loopback; the `ip link`/`ip route` half does not survive a reboot | Answer `y` |
| `cannot allocate memory in static TLS block` (naming `libGLdispatch.so.0` or `libgomp.so.1`) | aarch64 static TLS surplus is exhausted; glibc 2.31 has no tunable to raise it, that arrived in 2.32 | Export the `LD_PRELOAD` line in step 3. **Both** libraries — preloading one only moves the error to the other |
| `TypeError: UnitreeWebRTCConnection.__init__() got an unexpected keyword argument 'aes_128_key'` | dimos main passes `aes_128_key` to the `unitree-webrtc-connect` driver; no released driver (2.1.2 is newest) accepts it. The class named is the driver's, aliased `LegionConnection` | Already patched on this robot. If it returns after a `git pull`, in `dimos/robot/unitree/connection.py` pass the kwarg only when set: `_key = {"aes_128_key": aes_128_key} if aes_128_key else {}` then `LegionConnection(..., **_key)` |
| `HTTPConnectionPool(host='none', port=8081)` and `Could not get SDP from the peer. Check if the Go2 is switched on` | No `--robot-ip`, so the default `None` was stringified to `"none"`. The Go2 wording is the driver's, ignore it | Pass `--robot-ip 192.168.123.161` |
| `libEGL DRI3 failed` then `wgpu error: Out of Memory` | dimos opened the native viewer on the robot, which has no display | Pass `--rerun-open none` and run the viewer on your laptop |
| `RuntimeError: Failed to open camera 0` | **Unresolved.** `/dev/video0`–`video5` exist and the user is in the `video` group, so the usual "USB-C cable unplugged" answer does not fit | Does not stop the run. Note it and continue; add findings below |
| `No direct transform found between 'world' and 'base_link'`, once a second | The robot is not connected yet — a symptom, not the cause | Look above it for the real error |
| `nix: command not found` right after install | Nix was added but not to this shell's PATH | Open a fresh SSH session |
| `g++: fatal error: Killed signal terminated program cc1plus` | Out of memory compiling PCL | `nix build .#default --no-write-lock-file --cores 4`, or add swap |
| Rerun viewer/SDK version mismatch warning | Viewer is `0.32.0-alpha.1`, SDK is `0.32.0` | Harmless, ignore |
| SSH `Permission denied (publickey)` with no password prompt | Password auth is disabled on some units | Ask Aaryan to add your key |

## 7. Errors seen

Append new findings here. One entry per error. Keep the full message — a paraphrase is not
reproducible.

```
### <date> — <what you were doing>
Command:
Error (verbatim):
Tried:
Outcome:
```

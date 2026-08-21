# One-click G1 bring-up — what it takes

What stands between `./g1-bringup.sh` and a genuine one-click install, measured on a real fresh
G1 Plus (Orin NX, JetPack 5.1.1) on 2026-08-07. Every claim below was executed, not assumed.

## Where it stands

```
box → running DimOS
 │
 ├── 1  wifi credentials      AUTOMATIC   read from the operator laptop's own NM profile
 ├── 2  wired interface       AUTOMATIC   first ethernet device
 ├── 3  cable                 PHYSICAL    ← irreducible today, see below
 ├── 4  laptop static ip      SUDO        ← one prompt
 ├── 5  reach the jetson      AUTOMATIC
 ├── 6  key access            PASSWORD    ← one prompt, removable
 ├── 7  robot joins wifi      AUTOMATIC   explicit WPA2 profile
 ├── 8  untethered ssh        AUTOMATIC
 ├── 9  identify the robot    AUTOMATIC   model from the vendor install dir
 ├── 10 tailscale             AUTH KEY    ← one approval, removable
 ├── 11 install dimos         AUTOMATIC   dim setup is non-interactive with no TTY
 └── 12 verify + record       AUTOMATIC
```

Three prompts stand between here and one click. Two of them are removable today.

## What you need

### 1. `sshpass` on the operator laptop — removes the robot password prompt

The script already uses it when present and falls back to interactive `ssh-copy-id` when not.
Installing it is the whole change.

    sudo apt install sshpass

The factory password is `123`, confirmed on this unit. `--pass` overrides it, because it is not
guaranteed across units — a wrong password and an unknown user return an identical SSH error, so
the script reports which auth methods the server actually offers rather than guessing.

### 2. A Tailscale auth key — removes the join approval

Create one reusable, pre-authorized, tagged key in the tailnet admin console, then:

    export TS_AUTHKEY=tskey-auth-...
    ./g1-bringup.sh

Without it the run still completes; the robot installs Tailscale and prints one URL to approve by
hand. Tags matter for a fleet: `tag:robot` keys are not tied to a person's account, so the robot
does not drop off the tailnet when whoever ran bring-up leaves.

Tailscale runs BEFORE the DimOS install on purpose. The wifi address is a DHCP lease (8 h, renewed
at 4 h) and the install takes minutes — a tailnet address cannot move underneath it.

### 3. Passwordless `nmcli` — removes the sudo prompt

Pick one. Both are once-per-laptop, not once-per-robot:

    # a. pre-provision the profile, so no run ever creates it
    sudo nmcli connection add type ethernet ifname enp130s0 con-name g1-wired \
         ipv4.method manual ipv4.addresses 192.168.123.100/24

    # b. or let the operator group activate connections without a password
    #    /etc/sudoers.d/g1-bringup:
    #    %dimos ALL=(root) NOPASSWD: /usr/bin/nmcli connection up g1-wired

### 4. The cable — irreducible on this hardware

    $ ls /sys/class/net
    docker0 dummy0 eth0 lo wlan0        # no usb0, no l4tbr0

USB device-mode networking is not enabled on this unit, so there is no way to reach a fresh
Jetson except the wire. The phone app configures the CONTROL computer (`.213`, port 9991, SSH
closed), never the Jetson — so pairing over the app cannot substitute.

Two ways to delete it later, neither done here:

- enable `l4t-usb-device-mode` on the Jetson, making USB-C carry a network. Orin NX supports it;
  this unit ships with it off. Turning it on is itself a bring-up step, so it only pays off from
  the second robot onward.
- a DHCP reservation for the Jetson's wired MAC, if the office ever bridges `192.168.123.0/24`.

## After that

    export TS_AUTHKEY=tskey-auth-...
    ./g1-bringup.sh          # then plug in the cable

Start it first: phase 3 waits up to 5 minutes for carrier, so the cable is the trigger rather
than something you race.

## Still open

- **Every fresh G1 is named `ubuntu`.** Nine of them collide instantly in mDNS. The Tailscale
  hostname works around it (`g1plus-pc4-f6f074`, model + MAC suffix), but the OS hostname itself
  is still unset. A rename belongs in bring-up.
- **Blueprint choice is not automatic.** `detect_robot` knows the model; nothing maps model to
  blueprint yet.
- **`main`'s `unitree-g1` blueprint fails on aarch64** with `import torch: cannot allocate memory
  in static TLS block`. Krishna's guide pins PR #3057 (ray tracing, no torch) or
  `LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libgomp.so.1`. Until that lands on main, a one-click run
  installs a stack whose headline blueprint does not start.
- **Standing the robot up stays manual, by choice.** First stand is the highest fall-risk moment;
  it wants a gantry and a controller in hand, not a script.

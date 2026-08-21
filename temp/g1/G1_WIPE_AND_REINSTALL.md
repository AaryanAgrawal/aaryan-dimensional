# Wiping a G1 and reinstalling — two procedures, two very different risks

Written 2026-08-10 for the G1 measured in `facts/g1-measured.env.txt`: Jetson Orin NX on Unitree's
custom `g1plus_pc4` carrier, L4T R35.3.1, Ubuntu 20.04, aarch64, glibc 2.31.

Every claim below is tagged. **VERIFIED** = read in this repo or in its measured facts.
**UNVERIFIED** = from the web or inferred; a URL follows where one exists. When Procedure B says
"not found", that is the finding — nobody should reflash this robot on a guess.

---

## Safety first: never touch the Unitree firmware page

The repo's own G1_SETUP_GUIDE.md warns, verbatim: *"Do not open port 80 on the robot in a browser.
That is the Unitree firmware update page, not dimos. Do not use Factory Reset there."* (VERIFIED —
repo guide; `recipes/g1/recipe.toml` is written from it.)

Why this matters — the G1 is **more than one computer** (VERIFIED, `recipes/g1/recipe.toml` and
`recipes/unitree/base.toml` notes):

| Address | What it is | What runs there |
|---|---|---|
| `192.168.123.164` | The Jetson (development computer). **This is the only machine dios touches.** | dimos, the recipe's installs, ssh |
| `192.168.123.161` | Unitree's control computer. No ssh. | robot firmware, the WebRTC endpoint dimos dials |
| `192.168.123.120` | The mid360 lidar on the internal switch | — |

"Factory Reset" on the firmware page acts on Unitree's **robot firmware**, not on anything dios or
dimos installed — so it cannot give you a clean slate for recipe testing, and it can put the robot's
control stack into a state only Unitree can recover (UNVERIFIED inference; the page and its reset
are Unitree's, undocumented publicly for the G1). Wiping the dimos install never requires it.
Everything in Procedure A happens over ssh to `192.168.123.164` and stays inside the Jetson.

Also never delete these on the Jetson — they are Unitree's, and the recipe's own match probes score
against them (VERIFIED, `recipes/g1/recipe.toml` `[match]`):

- `~/g1plus_pc4_unitree_install` (the `~/*_unitree_install` glob probe)
- `~/unitree_sdk2-main` (vendor-shipped; the `remote-file` probe — **not** the same thing as
  `~/unitree_sdk2_python`, which dios installs)
- the vendor packages `master_service_pc4`, `unitree_patch_pc4`, `video_hub_pc4` (VERIFIED,
  `facts/g1-measured.env.txt`)

---

## Procedure A — clean slate for recipe testing (does NOT touch the vendor OS)

This is the one you want. It removes exactly what dios/dimos put on the Jetson, so
`dios infect --with unitree-g1` can be tested as if against a fresh robot.

### What got written

Two lists live with the code, so read them there rather than here:

- **The recipe's declared surface** — `[entitlements].writes` in `recipes/g1/recipe.toml`:
  `~/dimos`, `~/cyclonedds`, `~/unitree_sdk2_python`, `~/.bashrc`, `/etc/systemd/system`.
- **What `dios uninstall` removes** — next section.

The setup pipeline also writes beyond both: the self-install and its `# DIMOS-ADDED` PATH blocks,
uv with its caches and managed Pythons, `/etc/sysctl.d/99-dimos.conf` plus the enabled
`/etc/systemd/system/dimos-multicast.service` boot unit (`sysconfig.rs`; older builds wrote
`/etc/networkd-dispatcher/routable.d/50-dimos-multicast.sh` or appended to `/etc/rc.local`
instead), the `CYCLONEDDS_HOME` and `LD_PRELOAD` exports in `~/.bashrc` (`unitree_python.sh`), the
git `insteadOf` rewrite (`git_https.sh`), the wifi profile, your ssh key, Nix, and apt packages.
The script below is the one maintained inventory of all of it: it names every path it removes and
every one it leaves. (An earlier revision restated a per-path table from the sources; it desynced
against `sysconfig.rs` within a single changeset, so the script is now the only copy — check it
against `[entitlements].writes` and `dios uninstall` when either changes.)

### What `dios uninstall` does — and the gap

`dios uninstall` (VERIFIED, `src/pkg/commands/uninstall.rs`) removes **only**: `~/.dimos`,
`~/.local/bin/dios`, the desktop service and launcher, and on systemd the webserver + root `dios`
services (`/etc/systemd/system/dim.service`, `dim-webserver.service`). It deliberately does NOT
touch the DimOS checkout, and it knows nothing about: `~/dimos`, `~/cyclonedds`,
`~/unitree_sdk2_python`, uv and its Pythons, the git url rewrite, the `~/.bashrc` lines, the
`DIMOS-ADDED` PATH blocks, the sysctl/multicast persistence, the wifi profile, the ssh key, or Nix.
The script below runs it first, then closes that gap.

### Things the script deliberately leaves alone

- **apt packages stay.** Removing `libgl1`/`libegl1` risks pulling GL away from the vendor Tegra
  stack, and the recipe re-checks them idempotently anyway (VERIFIED, `deps.rs` — and the apt-stays
  decision is settled). A from-scratch test loses nothing by keeping them.
- **nvpmodel/jetson_clocks.** `nvpmodel -m 0` persists across reboots, `jetson_clocks` does not
  (UNVERIFIED — NVIDIA platform behavior). Harmless either way; setup skips the stage when already
  at max perf.
- **Nix** — optional, manual, below. Heavy to remove, and the Jetson path reinstalls it.
- **Your ssh key and the wifi profile** — opt-in prompts, because removing either can strand you
  (some units have password auth disabled — VERIFIED, `recipes/g1/recipe.toml` notes — and deleting
  the wifi profile mid-session drops a wlan0 ssh connection).

### The script

Run it **on the robot**, as `unitree`, over the **wired** link (`ssh unitree@192.168.123.164`) so a
wifi change cannot cut you off. Idempotent; prints its plan and requires typed confirmation.

```bash
#!/usr/bin/env bash
# Wipe everything dios/dimos put on this G1's Jetson; never touch Unitree's vendor stack.
set -euo pipefail

[ "$(id -un)" != root ] || { echo "run as unitree, not root" >&2; exit 1; }

DIRS=(~/dimos ~/cyclonedds ~/unitree_sdk2_python ~/.dimos ~/.local/share/uv ~/.cache/uv ~/.local/share/dim)
FILES=(~/.local/bin/dios ~/.local/bin/uv ~/.local/bin/uvx ~/.local/share/applications/dimos-desktop.desktop)
# The dispatcher script is what builds before dimos-multicast.service wrote; remove either form.
ROOT_FILES=(/etc/systemd/system/dim.service /etc/systemd/system/dim-webserver.service
            /etc/sysctl.d/99-dimos.conf /etc/systemd/system/dimos-multicast.service
            /etc/networkd-dispatcher/routable.d/50-dimos-multicast.sh)

echo "Will remove (what exists; the rest is skipped):"
for p in "${DIRS[@]}" "${FILES[@]}" "${ROOT_FILES[@]}" /opt/unitree_sdk2_python; do
  [ -e "$p" ] && echo "  $p"
done
echo "Will also strip: DIMOS-ADDED blocks from shell profiles, CYCLONEDDS_HOME/LD_PRELOAD"
echo "lines from ~/.bashrc, the git --global insteadOf rewrite, DimOS lines in /etc/rc.local."
echo "NOT touched: ~/g1plus_pc4_unitree_install, ~/unitree_sdk2-main, vendor services, apt packages."
read -r -p "Type WIPE to continue: " ok
[ "$ok" = WIPE ] || { echo "aborted"; exit 1; }

# dios's own uninstaller first, while the binary and its config still exist.
command -v dios >/dev/null 2>&1 && dios uninstall --non-interactive || true

# Belt and braces for the units dios uninstall removes best-effort — plus the multicast oneshot,
# which dios uninstall does not know about.
sudo systemctl disable --now dios dim dim-webserver dimos-multicast 2>/dev/null || true
systemctl --user disable --now dim-desktop 2>/dev/null || true
rm -f ~/.config/systemd/user/dim-desktop.service
sudo rm -f "${ROOT_FILES[@]}"
sudo systemctl daemon-reload

for d in "${DIRS[@]}"; do rm -rf "$d"; done
rm -f "${FILES[@]}"
sudo rm -rf /opt/unitree_sdk2_python

# Guarded PATH blocks; the sed range is a no-op where the block is absent.
for f in ~/.profile ~/.bashrc ~/.bash_profile ~/.zshrc ~/.zprofile; do
  [ -f "$f" ] && sed -i '/# DIMOS-ADDED: start/,/# DIMOS-ADDED: end/d' "$f"
done
for f in /etc/profile /etc/zprofile /etc/bash.bashrc; do
  [ -f "$f" ] && sudo sed -i '/# DIMOS-ADDED: start/,/# DIMOS-ADDED: end/d' "$f"
done

sed -i -e '/^export CYCLONEDDS_HOME=/d' -e '/^export LD_PRELOAD=.*libGLdispatch\.so\.0/d' ~/.bashrc
git config --global --unset 'url.https://github.com/.insteadOf' 2>/dev/null || true

# Older builds appended here instead of installing the dimos-multicast.service unit.
[ -f /etc/rc.local ] && sudo sed -i '/# DimOS multicast/,+2d' /etc/rc.local

echo
read -r -p "Wifi profile to delete (nmcli name; DROPS a wlan0 session; empty keeps it): " ssid
[ -n "${ssid}" ] && sudo nmcli connection delete "$ssid" || true

echo
echo "Your key in ~/.ssh/authorized_keys was NOT removed: some units have password auth"
echo "disabled, and removing it there locks everyone out. Edit that file by hand if you must."
echo
echo "Done. Reboot now (sudo reboot) so the runtime sysctl/multicast state also resets —"
echo "only then is the next 'dios infect --with unitree-g1' a true from-scratch test."
```

Removing **Nix** too (optional — only if you want the recipe's Nix install path exercised from
zero; UNVERIFIED, from the Nix manual: https://nix.dev/manual/nix/latest/installation/uninstall):

```bash
sudo systemctl disable --now nix-daemon.socket nix-daemon.service 2>/dev/null || true
sudo rm -rf /nix /etc/nix /etc/profile.d/nix.sh ~/.nix-profile ~/.nix-defexpr ~/.nix-channels ~/.config/nix
for i in $(seq 1 32); do sudo userdel "nixbld$i" 2>/dev/null || true; done; sudo groupdel nixbld 2>/dev/null || true
for f in /etc/bashrc /etc/bash.bashrc /etc/zshrc /etc/profile; do
  [ -f "$f.backup-before-nix" ] && sudo mv "$f.backup-before-nix" "$f"
done
```

### Reinstalling

From the laptop, on the wired link: `dios infect --with unitree-g1` — bringup finds
`192.168.123.164`, `ssh.install-key` prompts for the factory password once, and the recipe drives
wifi, git-https, cyclonedds, helm, and unitree-python (VERIFIED, `recipes/g1/recipe.toml`). If the
laptop should also be reset: `sudo nmcli connection delete infect-wired` (VERIFIED,
`src/infect/verb/net.rs`).

---

## Procedure B — the real wipe: reflashing the Jetson

**Recommendation: do not do this without an image and instructions from Unitree.** Procedure A is
sufficient for recipe testing; Procedure B is for a Jetson that no longer boots, and even then the
first move is a support ticket, not a flash.

### What research found (and did not find)

- **No published Unitree G1 Jetson system image was found.** Searches of Unitree's docs, NVIDIA's
  forums, and community forums turned up G1 SDK documentation but no G1 image download, and no
  documented G1 recovery procedure. UNVERIFIED in the strong sense: absence of evidence — but that
  absence is the finding. Unitree's developer portal (https://support.unitree.com/home/en/G1_developer)
  is where one would appear.
- **Third parties warn against it explicitly.** Weston Robot's G1 guide: *"Do not attempt to flash
  the Orin NX module with any third-party images, as this could render the system inoperable"* —
  because the module sits on a custom Unitree carrier needing Unitree's BSP for drivers and device
  tree (UNVERIFIED-web: https://docs.westonrobot.com/tutorial/unitree/g1_dev_guide/).
- **NVIDIA will not help.** Asked about reflashing a Unitree Orin NX (a Go2 dock), NVIDIA staff
  answered: *"We would suggest consult with the board vendor for support. We don't use the board and
  cannot provide further suggestion"* (UNVERIFIED-web:
  https://forums.developer.nvidia.com/t/unable-to-re-flash-unitree-go2-expansion-dock-nvidia-orin-nx-which-has-jetpack5-1/351374).
- **SDK Manager is for NVIDIA devkits.** L4T R35.3.1 is JetPack 5.1.1 (UNVERIFIED-web:
  https://developer.nvidia.com/embedded/jetpack-sdk-511); flashing an Orin NX means recovery mode +
  the L4T flashing tools, and Orin NX boots from external storage with boot firmware in the
  module's QSPI, flashed against a **board config** (UNVERIFIED-web:
  https://docs.nvidia.com/jetson/archives/r35.4.1/DeveloperGuide/text/SD/FlashingSupport.html,
  https://docs.nvidia.com/jetson/archives/r35.3.1/ReleaseNotes/Jetson_Linux_Release_Notes_r35.3.1.pdf).
  The devkit board configs encode the devkit's pinmux and device tree. Do not be fooled by the G1
  reporting `model=NVIDIA Orin NX Developer Kit` (VERIFIED, `facts/g1-measured.env.txt`) — that is
  the device-tree model string Unitree's BSP inherited, not evidence a devkit image runs this
  carrier (inference).
- **Forced recovery requires physical access, location unknown for the G1.** On Orin NX carriers,
  recovery is a FC-REC pin shorted to GND (or a button) while powering on, then a USB-C to the
  host. For the Go2 dock the community found the pin after disassembly (UNVERIFIED-web:
  https://forum.mybotshop.de/t/unitree-go2-recovery-mode-entrance-with-jetpack-install/1060 — a Go2
  procedure; it does NOT transfer to the G1's `g1plus_pc4` board). Where the G1 exposes recovery,
  if at all without opening the torso, was not found. That is Go2 evidence, not G1 evidence.
- **Community precedent is Go2-only.** Go2 owners have restored from Clonezilla images of their own
  making, and mention Unitree images circulating with gaps ("missing Orin Nano images in Unitree's
  Google Drive folder") — same mybotshop thread. Nothing equivalent was found for the G1.

### What a reflash destroys

- **Unitree's vendor stack** on the Jetson: `master_service_pc4`, `unitree_patch_pc4`,
  `video_hub_pc4`, and `~/g1plus_pc4_unitree_install` (VERIFIED these exist,
  `facts/g1-measured.env.txt`). No public source for reinstalling them was found — losing them means
  a support ticket regardless.
- **The BSP for the custom carrier**: Unitree's device tree, pinmux, and any kernel patches. A
  devkit image may not even bring up USB/ethernet/cameras on `g1plus_pc4` (inference from the
  Weston Robot warning above).
- **Possibly calibration data**, if any lives on the Jetson rather than the control computer —
  whether it does was not found either way (honest unknown).

The robot's control firmware (the `192.168.123.161` computer) is a separate machine and survives a
Jetson reflash — but a Jetson that can't talk to it is still a robot that can't run dimos.

### If you are ever forced to

1. Open a ticket with Unitree first. Ask for: the `g1plus_pc4` system image for L4T R35.3.1, their
   flashing instructions, and the recovery-mode access point. If they say it is a service
   operation, believe them.
2. **Before any flash attempt, image the NVMe yourself** while the robot still boots —
   `tools/backup_restore/l4t_backup_restore.sh` from the matching R35.3.1 BSP over recovery mode,
   or Clonezilla against the drive (UNVERIFIED-web:
   https://www.forecr.io/blogs/bsp-development/how-to-clone-nvme-ssd-image-of-jetson-orin-nx-or-orin-nano-module;
   the Go2 community used exactly this to un-brick — mybotshop thread above). A restorable image of
   the working robot converts "bricked" back into "restored".
3. Never flash QSPI/bootloader components speculatively; a wrong boot firmware on the module is the
   step that turns "won't boot" into "won't enter recovery" (UNVERIFIED-web, community consensus in
   the threads above).

Bottom line: there is no verified, publicly documented path to reflash a G1. The wipe that exists,
works, and is reversible is Procedure A.

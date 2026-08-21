# Testing this on the G1

Ordered. Each step says the command, what passing looks like, and what to do when it does not.
Steps 0 to 2 need no robot power beyond a cable. Stop at the first failure: they are ordered so
that a failure early makes every later step meaningless.

Everything below assumes:

```bash
cd ~/aaryan-dimensional/workspace/dimos-bios
git checkout dios/9-integration            # runner + scan + unbrand, merged
nix develop --command cargo build          # target/debug/dios
```

The recipe is named `unitree-g1`. `g1` is its directory, and `--with g1` is refused; the error
lists the names that loaded.

---

## 0. Does a non-interactive ssh come back?

**This is the one that invalidates everything else.** The G1's login shell prints a
`ros:foxy(1) noetic(2)` selector. If that selector runs for a non-interactive shell it blocks on
`read`, and every robot-side step in every recipe is `ssh unitree@<robot> '<command>'`.

Nothing bounds that wait for a plain verb. The runner runs script steps under
`timeout <timeout_s>`, but that starts on the far side of the login shell. So a blocking login
shell is not a slow run, it is a hang.

```bash
timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=10 unitree@192.168.123.164 'echo hi'; echo "EXIT=$?"
```

`timeout 20` is there so a hang costs 20 seconds instead of your terminal.

**Passed:** prints `hi`, then `EXIT=0`, immediately.

**If `EXIT=124`** the selector is blocking and nothing else in this document will work. On the
robot, look at the top of `~/.bashrc` for the selector block. Ubuntu's stock `.bashrc` opens with

```sh
case $- in *i*) ;; *) return;; esac
```

and anything above that line runs for non-interactive ssh too. Either move the vendor's block
below that guard, or wrap it in the same `case`. Decide whether that edit belongs in the recipe as
a pre-helm step before anything else runs — if it does, it is the new first step of the G1 recipe
and everything else is post-`ssh`.

**If `EXIT=255` with `Permission denied (publickey)`**, key auth is not in place yet. That is
step 3's job, not a failure here; skip to step 3 and come back.

---

## 1. Read the plan, with no robot at all

```bash
./target/debug/dios infect --with unitree-g1 --dry-run
```

**Passed:** exit 0, and the run prints in order — `ssh-key`, `wifi`, `git-https`, `cyclonedds`,
`helm`, `unitree-python`, `config` — each with its `would run` commands, its `skip if` check and
the `judged by` probe that decides it. Params print as their own names (`ssid wifi_ssid`): a dry
run prompts for nothing. Nothing executes, and nothing is journalled.

`./target/debug/dios recipe show unitree-g1` prints the same plan with the `touches` lines. That
is the whole trust surface the recipe declares, and a step that exceeds it is refused before it
runs.

```bash
./target/debug/dios doctor --recipe all
```

**Passed:** exit 0. Findings print for all three recipes, all of them notes (`-`). No blockers:
`doctor --recipe` exits non-zero when there is one.

**If either fails**, it is a file problem, not a robot problem, and it is reproducible on your
laptop. `--json` on either command gives the same content for a tool to read.

---

## 1b. Scan: does dios see what you see?

```bash
./target/debug/dios infect scan
```

**Passed:** exit 0 always, robot or no robot. Each transport prints a line — with no robot every
one degrades to a reason (`no carrier`, `nothing advertising`), never an error. With the G1 on
the cable, the ethernet line ends `-> unitree-g1` and a `next: dios infect --with unitree-g1`
hint prints. `--json` carries the same report, MAC-keyed, for a tool.

**If the G1 is cabled but not proposed**, run with `--verbose`: it prints the probe plan derived
from the installed recipes before the results — what will be pinged, which sweeps run, and each
probe it skipped with the reason. That distinguishes "not probed" from "probed, not recognised";
for the latter, `dios recipe test unitree-g1` scores the recorded facts with the same scorer.

---

## 2. Reach the robot over the cable

Cable into the G1's ethernet jack first.

```bash
./target/debug/dios --dry-run infect bringup --with unitree-g1     # read it first
./target/debug/dios infect bringup --with unitree-g1
```

**Passed:** `robot reachable at 192.168.123.164`, exit 0. It waits for carrier, writes an
`infect-wired` NetworkManager profile at `192.168.123.100/24`, and waits for a reply.

**If it stops at carrier**, the cable is in the wrong jack. The recipe's own hint says so: the G1
has two ethernet jacks. Try the other one.

**If it stops at the reply**, carrier is up and the address is wrong or the robot is not up. Check
`nmcli connection show --active` for `infect-wired`, then `ping 192.168.123.164`.

---

## 3. Run to the package manager, and stop

Two ways from here. The runner drives the whole recipe in one command (step 4b) and there is no
"stop before helm" flag, so for a first contact where you want to inspect the robot between
steps, drive the pre-helm steps one verb at a time, in the order step 1 printed. Read each dry
run before dropping the `--dry-run`.

```bash
R=unitree@192.168.123.164

# 3a. key auth, so nothing later can sit waiting for a password
./target/debug/dios --dry-run verb run ssh.install-key --on laptop --robot $R
./target/debug/dios verb run ssh.install-key --on laptop --robot $R
```

**Passed:** `ssh -o BatchMode=yes $R true` succeeds afterwards. That is also the verb's own proof,
which is why the step declares `verify = { unproven = ... }`.

```bash
# 3b. wifi. The recipe marks this critical: everything after it needs the robot online.
# Two different secrets: the robot's own password, which sudo needs, and the wifi key.
export INFECT_ROBOT_PASSWORD='<the robot login password>'
read -rs WIFI_PSK                                     # typed, not in shell history
./target/debug/dios --dry-run verb run wifi.join --on robot --robot $R \
  --arg iface=wlan0 --arg ssid='<office ssid>' --arg psk="$WIFI_PSK"
```

The dry run prints the psk's position as `<stdin: secret>`: it goes to a 600 file on the robot and
is removed in the same plan, never onto a command line.

**Passed:** `nmcli -t -f GENERAL.STATE connection show <ssid>` reports connected, and
`dios verb run net.has-inet --on robot --robot $R` succeeds.

**If wifi fails, stop.** It is the one step the G1 recipe declares `critical = true`. Everything
after it clones and pip-installs from the internet.

Steps `git-https` and `cyclonedds` are script steps. `dios verb run` cannot run those — only the
runner does (it pushes the script and runs it under `timeout`) — so on this path run them by hand
from `recipes/unitree/steps/`, and note that `cyclonedds_build.sh` is the 1800s one.

**Stop here** to keep the robot at a known state before the package manager touches it.

---

## 4. The full install

The G1's Jetson is aarch64. The debug binary on your laptop is x86_64 and will not run there.

```bash
nix build .#linux-arm64          # result/bin/dios, static aarch64 musl
file result/bin/dios             # "ARM aarch64 ... statically linked"
```

That build was run on this branch and produces a 6.8 MB static binary. It has not been executed on
an aarch64 machine.

```bash
./target/debug/dios --dry-run verb run helm.deliver --on robot --robot $R \
  --arg binary=result/bin/dios --arg mode=dev --arg extras=unitree
```

Read it: it pushes the binary to `~/.local/bin/dios`, chmods it, runs
`dios setup --non-interactive --mode dev --extras unitree`, and proves the result with
`dios doctor --json` reporting no blocking findings.

Then drop `--dry-run`.

**Passed:** the verb succeeds, and on the robot `dios doctor --json` has no finding with
`"severity": "block"`.

**If setup fails partway**, it stopped inside the package manager, not inside the recipe. Get its
own output: ssh to the robot and re-run `dios setup` there, without `--non-interactive`, so a
failure offers the menu instead of continuing. `dios log` on the robot shows what already ran.

**If the smoke test fails**, `[helm].smoke_blueprint = "unitree-g1"` now reaches
`dios setup --smoke-blueprint`, but the run it gates sits behind an interactive confirm and a
display, so a headless robot still skips it. Run the blueprint by hand to prove the robot.

---

## 4b. Or: the runner, end to end

The whole recipe in one command. `helm_binary` names the aarch64 build — without it the runner
pushes the binary it is running from, which is your laptop's x86_64 one.

```bash
./target/debug/dios --dry-run infect --with unitree-g1     # read the whole run first
./target/debug/dios infect --with unitree-g1 --param helm_binary=result/bin/dios
```

It prompts for the wifi ssid and password (the password masked; `INFECT_PARAM_WIFI_SSID` and
`INFECT_PARAM_WIFI_PASSWORD` answer them unattended), then drives ssh-key, wifi, the scripts,
helm, unitree-python and config in order, journalling each outcome under
`~/.dimos/infect/journal/<mac>.json`. A step whose verify already passes reports `already done`.

**If a step fails interactively**, you get the same menu `dios setup` has: continue / fix in a
shell / help. `wifi` is critical, so its menu offers abort, not continue. A failed run exits 1
(`failed_stages` on stderr as JSON); re-running resumes from the journal instead of repeating
what finished.

---

## 5. Run it again

The claim every verb makes is that it checks first and applies only what is missing. This is the
step that tests the claim.

```bash
./target/debug/dios infect bringup --with unitree-g1
./target/debug/dios verb run ssh.install-key --on laptop --robot $R
./target/debug/dios verb run helm.deliver --on robot --robot $R \
  --arg binary=result/bin/dios --arg mode=dev --arg extras=unitree
```

**Passed:** each one reports it skipped, on the strength of its own `skip if` check, and changes
nothing. A dry run of each prints that check as the first line.

**If any of them re-does its work**, that is the bug worth writing down: name the verb and what it
re-did. An idempotent verb is the property the whole recipe model rests on, because a half-finished
run has to be resumable by running it again.

The same claim, one level up: re-run `dios infect --with unitree-g1 --param
helm_binary=result/bin/dios` after step 4b. **Passed:** every step reports `done on a previous
run` (the journal) or `already done` (its verify), and the robot is untouched.

---

## What you cannot test tomorrow

- **Matching.** `dios infect` without `--with` still refuses (its error now points at scan).
  Scan proposes a recipe but does not hand it to infect; you type the `--with` yourself.
- **Scan's bluetooth transport against a real Go2.** The `ble-name` probe (GO2_<serial>) is
  fixture-tested; `bluetoothctl` against a live advertising Go2 is not. Ethernet, wifi and the
  no-usb path were exercised on this laptop.
- **Exit code 2 from hardware.** `--agent` on a critical step failure exits 2 with the escalation
  block — the seam and the runner path are both under test in `tests/runner.rs` — but driving it
  against the real robot means making wifi fail on purpose; do that only if there is time.
- **`smoke_blueprint`.** Passed to `dios setup --smoke-blueprint` since dios/8, but the smoke run
  itself needs a display and an interactive yes, which the robot has neither of.
- **The zenoh payload.** The runner expects the go2web binary at `~/.cache/infect/go2web`;
  nothing fetches it yet (DIM-1406).

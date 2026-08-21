# Open questions

Things an agent cannot settle by reading code or running it. Each one names what is blocked, what
we already know, and what a decision would unblock. Everything an agent *could* work out is in
`todo.md` instead.

---

## 1. Which tailnet, and who owns the robots on it?

**Blocked:** the tailscale step ships `enabled = false` in `recipes/unitree/base.toml`. Until this
is answered no robot gets a stable remote identity, and remote support means someone on the LAN.

`workspace/tailscale-decision.md` settled the *mechanism* against tailscale 1.102.2 and the real
source: one tailnet-owned OAuth client (scope `auth_keys`, tag `tag:robot`), which the laptop
exchanges at bring-up for a single-use, pre-approved, non-ephemeral, 10-minute key. Tagging is what
makes the robot survive a person leaving — "applying a tag to a device removes any user-based
authentication", and it disables the 180-day node-key expiry that would otherwise silently drop a
warehouse robot.

What only Aaryan can answer:

- **Is there a servicerobotco.com tailnet, and is he Owner or Admin on it?** Everything assumes yes.
- **Did the robots already deployed join a personal account?** If so they are already the failure
  mode the doc describes and need re-authenticating as `tag:robot`. `scripts/g1-bringup.sh:359`
  falls back to printing a login URL when no key is given, which is exactly how that happens, and it
  never passes `--advertise-tags`, so even the keyed path produces a user-owned node today.
- **Where does the OAuth client secret live on an operator laptop?** It is the one long-lived
  credential in the whole design and it is not in this repo.
- **Is device approval enabled?** The tooling sets `preauthorized: true` either way; it only changes
  what a failure looks like.
- **Does a Go2 get a tailnet identity at all?** On the webrtc lane the robot never receives code.

Not blocked on the answer: the ACL policy block, the exact `tailscale up` invocation, and the
package availability for focal/arm64 are all written and verified in the decision doc.

---

## 2. go2web: how is it built, and where is it fetched from?

**Blocked:** the Go2 zenoh lane — deployment shape 3, the whole reason lanes exist.

`dimensionalOS/go2web` is private and has not been read. `[payload.go2web].source` in
`recipes/go2/recipe.toml` is a repo URL; `payload.deliver` takes a local file and a `sha256`. The
step between them does not exist and cannot be guessed:

- Is there a **published aarch64 artifact** (a release asset, a registry image), or does the
  operator build it?
- If it is built, **on what** — the laptop cross-compiling, or the robot?
- What **pins a version**? A recipe that says "latest" is not reproducible, and a robot that gets a
  different bridge than the one tested is the bug this whole tool exists to prevent.
- The `[payload]` table shape (`source` + `sha256` + `service`) is a **guess**. If go2web ships as a
  container or needs config beyond a unit file, the table is wrong. DIM-1406.

Also unproven: `publishes` for go2web is `ss -ltnH sport eq :7447`, which shows the zenoh endpoint
is listening — not that anything is on it. The real proof is a subscriber seeing `dimos/odom/*`, and
dimos ships no zenoh topic CLI (`lcmspy` and `agentspy` are LCM only).

---

## 3. Which extras does each Go2 lane actually need?

**Blocked:** both Go2 lanes install the wrong thing, in one direction or the other.

Both lanes currently declare `extras = ["unitree"]`, copied from the G1. Nobody checked it:

- The **webrtc lane** runs everything on the laptop and never touches the robot. Does it need
  `unitree` at all, or does the webrtc path live somewhere else in dimos?
- The **zenoh lane** puts perception on the robot via go2web and dimos on the laptop. Does the
  laptop side then need `perception`? Does it need `cuda`?
- `go2-zenoh-basic` and `go2-zenoh-nav`, which the zenoh lane names, **do not exist**. Grepped
  `dimos/robot/all_blueprints.py` in `workspace/dimos` on `feat/on-run-extras`: zero matches for
  "zenoh" anywhere in the file. `unitree-go2`, which the webrtc lane names, is real. The zenoh names
  come from the plan. Is there another branch, or do they need renaming?

An extras list is not a preference — a wrong one is a multi-GB install of the wrong wheels on a
Jetson, or a missing import at the first run.

---

## 4. How should `extends` merge a base into a child?

**Blocked:** nothing today — one-level merge is implemented and tested. This asks whether the rule
is the one we want before recipes outside this repo depend on it.

The rule as built: the base contributes what the child did not say, the child wins where both
speak, steps merge by id (same id replaces in place rather than appending), entitlements union,
probes concatenate, and a base that itself extends is refused, so a recipe is always two files.

The judgement calls inside that, none of which the plan mentions:

- **Replace-in-place vs append** for a step id that appears in both. Appending would run it twice,
  which seemed clearly wrong — but "clearly wrong to me" is not a decision anyone made.
- **Entitlement union.** A child inherits its base's permissions. That is convenient and it is also
  how a base quietly grants reach that a reader of the child never sees.
- **One level only.** Deeper chains are refused rather than supported. Cheap to relax later,
  impossible to tighten once someone ships a three-deep recipe.

The same merge rule is used for lanes, which is why it is worth agreeing on once.

---

## 5. Should `dimos run` have a default blueprint?

**Blocked:** the plan's stated measure of success — "`dimos run` with no arguments" — is not
reachable as written, so there is no definition of done for a bring-up.

`dimos run` takes `robot_types` as a **required positional**, and `GlobalConfig` is
`extra="ignore"`, so a `DIMOS_BLUEPRINT` key written into `.env` is silently dropped. `config.write`
therefore writes only what dimos actually reads (`DIMOS_TRANSPORT`, `ROBOT_IP`) and the blueprint
stays the operator's argument.

Either the goal is reworded, or dimos learns a default blueprint — which is a change to dimos, not
to infect, and belongs to whoever owns its CLI.

---

## 6. Does helm grow `--smoke-blueprint`, or do recipes stop claiming a smoke test?

**Answered in dios/8: helm grew the flag, and the flag is not knowledge.** `dios setup
--smoke-blueprint <name>` carries an opaque name the way `--extras` carries package names; the
choosing stays in the recipe, `verify.rs` hardcodes nothing, and without the flag there is no smoke
test at all. `Helm::verb_args` passes `[helm].smoke_blueprint` through, so the recipe's declaration
is now executed.

Still open inside it: the smoke run sits behind an interactive confirm and needs a display, so a
`--non-interactive` install on a headless robot never runs it — "this robot works" is still proven
by hand. The second option (infect runs the smoke as a post-helm step calling `dimos run
<blueprint>`) remains the way to make the proof unattended, and it is bigger than a flag.

---

## 7. Smaller ones, still needing a person

- **Ambiguity margin is 10 points, absolute.** Thresholds are per-recipe, so a relative rule would
  compare numbers on different scales — but 10 is a judgement, not a measurement. It decides when
  infect asks "which robot is this?" instead of proceeding.
- **The plan's Go2 port sweep carries `for_match = true`, unexplained.** Dropped, because every
  probe already contributes both its weight and its capture on the same hit. If it meant
  capture-without-scoring, the format needs the flag back.
- **A journal starts fresh when the recipe or lane changes**, silently overwriting the previous
  history on the next save. The alternative is keying the file by robot+recipe+lane, which
  contradicts "keyed by a stable robot identity".
- **Commit trailers disagree.** This repo's earlier commits sign `Co-Authored-By: Claude Opus 5`;
  the harness instruction says Opus 4.8, so later commits say 4.8. Pick one.

---

## 8. Does the G1's login selector hang a non-interactive ssh?

**Blocked:** whether every robot-side step in every recipe works at all on a G1. This is question 8
only because it is new; it is first in priority, and it is
[docs/TESTING_TOMORROW.md](docs/TESTING_TOMORROW.md) step 0.

Every robot-side op is `ssh -o BatchMode=yes -o ConnectTimeout=10 unitree@<robot> '<line>'`. The G1
prints a `ros:foxy(1) noetic(2)` selector at login. If that block runs for a non-interactive shell
it blocks on `read`, and `ConnectTimeout` does not apply — it covers the connect and the auth and
then stops. Nothing else bounds a remote command, so this is a hang, not a slow step.

`timeout 20 ssh -o BatchMode=yes unitree@192.168.123.164 'echo hi'` answers it in one command.

What a person has to decide if it does hang:

- **Whose file gets edited.** Guarding the vendor's block with `case $- in *i*) ;; *) return;; esac`
  is a one-line change to a robot we do not own the image of, and it is undone by a factory reset
  or a vendor update.
- **Whether that edit is a recipe step.** If it is, it is the G1's new first pre-helm step and
  everything else depends on it, which makes it `critical = true` and makes it run before
  `ssh.install-key` can prove anything.
- **Or whether the executor stops trusting the login shell**, and sends every remote command as
  `bash --noprofile --norc -c`. That is the general fix, it costs nothing on a well-behaved robot,
  and it means a recipe's script steps no longer inherit the operator's environment — which some of
  them may be relying on. `cyclonedds_build.sh` exports `CYCLONEDDS_HOME` and the G1's
  `unitree-python` step verifies in a `fresh_shell` precisely because of that.

Independently of the answer: a remote command should have a deadline. That part is in todo.md and
does not need a person.

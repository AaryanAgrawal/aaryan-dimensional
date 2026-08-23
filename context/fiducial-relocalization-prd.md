# [Fiducial Relocalization] PRD

|  |  |
| -- | -- |
| **Owner** | Aaryan |
| **Project** | Fiducial Relocalization |
| **Labels** | *Type @ & pick.* |
| **Status** | *Draft* |
| **Milestone** | *Required once Accepted* |

## 1. Problem

### What is the problem we are solving?

A robot that boots inside a mapped building does not know where it is. The only route back is an
FPFH+RANSAC global search over the pre-map. It matches geometry: it waits for roughly 50,000 points
of local map before it fires, costs 4.4-23 s of CPU per attempt on a Go2/Orin, and in a corridor or
bare room there is nothing to match and it never converges. Mid-run LIO drift in a featureless
space defeats the same mechanism.

Two design partners hit this:

* **Omakase**: "drift in 100m featureless hospital corridors (Mid-360 sees ~50m) and relocalization
  failure the moment the environment got dynamic (20 media people crowding the robot)."
* **Lita Hotel** already relocalizes off Aruco tags per hotel room, because the general solution
  was not dependable in production.

### Why now?

* Relocalization is the named failure in a live deployment, and the fix for a featureless corridor
  cannot depend on features.
* The pluggable-prior work landed candidate proposers feeding one shared judge, so a tag source is
  additive.
* kronknav is landing. Relocalization today is welded to the go2 nav stack, so this has to stand on
  its own now.

### Existing alternatives

* **FPFH+RANSAC global search** — no infrastructure, works where geometry is distinctive; seconds
  per attempt, and fails where drift is worst.
* **Drive the robot to a known start pose** — needs a human and a marked spot; does nothing mid-run.
* **Re-map the space** — throws away the map the robot was supposed to reuse.
* **Roll your own tags** — what Lita did; every operator rebuilds it.

## 2. Solution

### Customer messaging

Look at a tag, know where you are. Put a few AprilTags in a space you surveyed once, and the robot
recovers its position from a single sighting.

### Solution

A relocalization source that proposes a fix from a surveyed fiducial tag, judged by the same accept
gate as every other source.

* **Survey once.** Drive the space, export a marker map: tag id to pose in the map frame.
* **Fix on sight.** A surveyed tag in view proposes a fix in about a second, whatever the geometry.
* **One gate for every source.** Tag and search fixes pass the same check against the pre-map, and
  each published fix names its source. The tag is a shortcut to a candidate, never past the check.
* **Stands alone.** Its own module set, composable with any nav stack.

### Our current state

The prior is built, judged and unit-tested — aggregation cuts pose error 46% on clean synthetic
input. End to end it does not work yet: on the office recording it wins **0 of 29 fixes**, because
the surveyed tag poses are off (translation RMS ~0.6 m, orientation spread up to 88 deg) and the
judge correctly rejects them. Two suspects, not yet separated: per-unit Go2 camera calibration, and
the mirror-ambiguity gate dormant live because corner pixels are dropped on the wire.

**Marker pose quality, not wiring, decides whether this ships.**

### Options rejected

* **Trusting a tag sighting directly.** A single planar tag has a mirror-ambiguous pose; an
  unjudged fix can be metres off.
* **Tag-only localization.** Tags narrow the search; the map still judges the fix.

## 3. Usage scenarios

### Scenario 1 - Omakase (featureless hospital corridor)

* Tokyo startup deploying a wheeled humanoid into hospitals and elder care. Ran a fork of our nav
  stack in Dec 2025; needs no drift over a 30-minute run.
* Tags at corridor intervals and ward entrances. The robot drifts along the 100 m corridor; each
  tag it passes pulls it back onto the map. A tag high on a wall stays visible through a crowd.
* Hard case: a tag seen small, far and oblique. Refuse the fix; a wrong fix in a hospital corridor
  is worse than no fix.

### Scenario 2 - Lita Hotel (per-room localization, less ops)

* LA hotel operator running delivery and cleaning robots across floors. Already depends on Aruco
  tags per room and wants something *less* manual and ops-heavy.
* The tags they already hang, surveyed once into a marker map instead of hand-configured per room,
  consumed by the stack instead of their own glue.
* Hard case: this partner wants fewer tags. This has to reduce the setup work they already do, not
  add a second tagging regime.

## 4. Success metrics

* **The tag source wins fixes.** More than zero accepted `source=fiducial` fixes per recording
  across the benchmark suite. It is zero today.
* **Speed.** Under 2 s from tag visible to published fix, against 4.4-23 s per search attempt.
* **Survey quality.** Per-tag orientation spread under 25 deg in the marker map export; tags that
  miss the bar are reported.
* **No bad fixes.** Zero accepted fixes that are wrong against the referee tag.

## 5. Features

* Surveyed marker map — tag id to map pose, exported once per space.
* Tag-sighting relocalization source feeding the existing judge.
* Survey quality reporting — per-tag pose spread, so a bad map is visible before it is trusted.
* Source labelling on every published fix, in the log and the viewer.
* Standalone module set, composable with any nav stack.

## 6. Non-Goals

* Tag-only localization with no geometric check.
* Tag placement or printing tooling beyond the existing export.
* Deciding where an operator should hang tags.
* The G1. The kronknav stack has no camera, so Go2 is the platform until one is added.

## 7. Future enhancements

* IR tags — fiducials an infrared camera sees but the eye does not. Tags stop being visible
  clutter, so a hotel or hospital can hang as many as the robot needs without anyone seeing them.
  Prior art: Pudu already uses this approach, and Lita runs Pudu robots today.
* Multi-tag fixes: two tags in one view constrain the pose better than either alone.
* Survey folded into normal mapping runs instead of a separate pass.

A technical proposal follows once this is accepted.

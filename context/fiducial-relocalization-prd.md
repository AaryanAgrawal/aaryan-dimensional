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

A robot that boots inside a building it has already mapped does not know where it is, and the only
route back today is an FPFH+RANSAC global search over the pre-map. That search matches geometry, so
it needs the geometry to be distinctive: it waits for roughly 50,000 points of local map before it
will fire, costs 4.4-23 s of CPU per attempt on a Go2/Orin, and in a corridor or a bare room there is
nothing to match against and it never converges. The same weakness shows up mid-run — when LIO drift
accumulates in a featureless space, the mechanism that would correct it is the one that space defeats.

This is not hypothetical. Two design partners in the Navigation PRD hit exactly this:

* **Omakase** hit "drift in 100m featureless hospital corridors (Mid-360 sees ~50m) and
  relocalization failure the moment the environment got dynamic (20 media people crowding the robot)."
  Both halves are the same gap: no reliable geometry to relocalize against.
* **Lita Hotel** already relocalizes off Aruco tags per hotel room, because the general solution was
  not dependable enough to trust in production.

### Why now?

* Relocalization is the named failure in a live deployment, and the fix for a featureless corridor
  cannot itself depend on features.
* The pluggable-prior work already landed the hard part — candidate proposers feeding one shared
  judge — so a tag source is an additive change rather than a rewrite.
* kronknav is landing. Relocalization today is welded to the go2 nav stack and cannot follow it, so
  whatever we build has to stand on its own now rather than be untangled later.

### Existing alternatives

* **FPFH+RANSAC global search** — no infrastructure and works anywhere with distinctive geometry, but
  costs seconds per attempt and fails in the exact spaces where drift is worst.
* **Drive the robot to a known start pose** — exact, but needs a human and a marked spot, and does
  nothing for a drift that happens mid-run.
* **Re-map the space** — always works, and throws away the map the robot was supposed to reuse.
* **Roll your own tags** — what Lita did. It works, and every operator rebuilds it.

## 2. Solution

### Customer messaging

Look at a tag, know where you are. Put a few AprilTags on the walls of a space you have surveyed
once, and the robot recovers its position from a single sighting instead of waiting on a search that
may never succeed.

### Solution

A relocalization source that proposes a position fix from a surveyed fiducial tag, judged by the same
accept gate as every other source.

* **Survey once.** Drive the space and export a marker map — tag id to pose in the map frame.
* **Fix on sight.** A surveyed tag in view proposes a fix, in about a second, with no dependence on
  the surrounding geometry being interesting.
* **One gate for every source.** Tag fixes and search fixes pass the same check against the pre-map.
  Only fixes that score well are published, and each says which source produced it. The tag is a
  shortcut to a candidate, never a shortcut past the check.
* **Stands alone.** Its own module set, composable with any navigation stack, including one that has
  no navigation in it at all.

### Our current state

The prior is built, judged and unit-tested — aggregation cuts pose error 46% on clean synthetic
input. End to end it does not yet work: on the office recording it wins **0 of 29 fixes**, because
the surveyed tag poses are off (translation RMS ~0.6 m, orientation spread up to 88 deg) and the
judge correctly rejects them. Two suspects, not yet separated: per-unit Go2 camera calibration, and
the mirror-ambiguity gate being dormant live because corner pixels are dropped on the wire.

**Marker pose quality, not wiring, is what decides whether this ships.**

### Options rejected

* **Trusting a tag sighting directly.** A single planar tag has a mirror-ambiguous pose; an unjudged
  fix can be metres off in the wrong direction.
* **Tag-only localization.** The fix stays judged against lidar geometry. Tags narrow the search;
  they do not replace the map.

## 3. Usage scenarios

### Scenario 1 - Omakase (featureless hospital corridor)

* Tokyo-based startup deploying a wheeled humanoid into hospitals and elder-care facilities. Ran a
  fork of our nav stack in Dec 2025; concluded they need AMR-grade robustness — no drift over a
  30-minute run.
* How they use it: tags at corridor intervals and at ward entrances. The robot drifts along the
  100 m corridor as it does today, and each tag it passes pulls it back onto the map. The dynamic
  case that broke relocalization before — a crowd around the robot — matters less, because a tag high
  on a wall stays visible when the floor-level geometry is a wall of people.
* Hard case: a tag seen small, far and oblique. The fix must be refused rather than published badly;
  a wrong fix in a hospital corridor is worse than no fix.

### Scenario 2 - Lita Hotel (per-room localization, less ops)

* LA-based operator running delivery and cleaning robots across multiple floors of their own hotel.
  Already depends on Aruco tags per room, and explicitly wants something *less* manual and
  ops-heavy.
* How they use it: the same tags they already hang, but surveyed once into a marker map instead of
  hand-configured per room, and consumed by the stack rather than by their own glue.
* Hard case: this partner wants fewer tags, not more. Fiducial relocalization has to reduce the setup
  work they already do, not add a second tagging regime beside it.

## 4. Success metrics

* **The tag source wins fixes.** More than zero accepted fixes labelled `source=fiducial` per
  recording across the benchmark suite. It is zero today.
* **Speed.** Under 2 s from a tag becoming visible to a published fix, against 4.4-23 s per search
  attempt.
* **Survey quality.** Per-tag orientation spread under 25 deg in the marker map export. Tags that
  miss the bar are reported, not silently shipped.
* **No bad fixes.** Zero accepted fixes that are wrong when scored against the referee tag. A
  published bad fix is worse than a missed one.

## 5. Features

* Surveyed marker map — tag id to map pose, exported once per space.
* Tag-sighting relocalization source, proposing candidates into the existing judge.
* Survey quality reporting — per-tag pose spread, so a bad map is visible before it is trusted.
* Source labelling on every published fix, in the log and the viewer.
* Standalone module set, composable with any nav stack.

## 6. Non-Goals

* Tag-only localization with no geometric check.
* Tag placement and printing tooling beyond the existing export.
* Deciding where an operator should hang tags in their space.
* The G1. The kronknav stack has no camera, so Go2 is the demonstrable platform until one is added.

## 7. Future enhancements

* Get off tags entirely for this class of failure — a learned or appearance-based place-recognition
  source plugging into the same judge. This is what Lita is really asking for; tags are the bridge.
* Multi-tag fixes, where two tags in one view constrain the pose better than either alone.
* Survey without a separate pass, folding marker capture into normal mapping runs.

A technical proposal follows once this is accepted.

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

Right now the only way a lost robot gets its position back is an FPFH+RANSAC search against the
pre-map. It needs about 50,000 points of local map before it even fires, burns 4.4-23 s of CPU per
attempt on a Go2/Orin, and in a featureless corridor it never converges.

Two partners have already hit this:

* Omakase saw drift in 100m featureless hospital corridors, where the Mid-360 only sees about 50m.
  Relocalization then failed outright when 20 media people crowded the robot.
* Lita Hotel relocalizes off Aruco tags per room today, and wants less manual, ops-heavy work.

### Why now?

Relocalization is the named failure in a live deployment.

### Existing alternatives

* The RANSAC search. Seconds per attempt, and it fails in the places where drift is worst.
* Drive the robot to a known start pose. Needs a person, and does nothing once the robot is running.
* Roll your own tags, which is what Lita did.

## 2. Solution

### Customer messaging

Look at a tag, know where you are.

### Solution

Survey the space once into a marker map that holds a pose for each tag id. After that, a tag in
view proposes a fix. It goes through the same accept gate as every other source, and every
published fix records where it came from.

### Our current state

This does not work end to end yet. On the office recording it wins 0 of 29 fixes. The surveyed tag
poses are off, translation RMS around 0.6 m and orientation spread up to 88 deg, so the judge
rejects them and it is right to. We have two suspects and have not separated them: per-unit Go2
camera calibration, and the mirror-ambiguity gate, which sits dormant live because corner pixels get
dropped on the wire.

**Marker pose quality, not wiring, decides whether this ships.**

### Options rejected

* Trusting a tag sighting on its own. A planar tag pose is mirror-ambiguous, so an unjudged fix can
  land metres away.
* Tag-only localization. The map still has to judge the fix.

## 3. Usage scenarios

### Scenario 1 - Omakase (featureless hospital corridor)

Tags go up along the corridor and at ward entrances. The robot drifts as it walks, and each tag it
passes pulls it back onto the map. A tag high on a wall stays visible even when the floor is a wall
of people.

The hard case is a tag seen small, far away and at an angle. We want that fix refused.

### Scenario 2 - Lita Hotel (per-room localization, less ops)

They keep the tags they already hang. Instead of hand-configuring every room, they survey once and
the stack reads the map.

The hard case is that this partner wants fewer tags, not more. It has to cut the setup work they
already do rather than add a second tagging regime beside it.

## 4. Success metrics

* Accepted fixes labelled `source=fiducial`, more than zero per recording. It is zero today.
* Under 2 s from a tag becoming visible to a published fix.
* Per-tag orientation spread under 25 deg in the survey export.
* No bad fixes.

## 5. Features

* A surveyed marker map holding a pose per tag id.
* The tag source itself, feeding the judge we already have.
* Per-tag pose spread reported at survey time, and a source label on every published fix.

## 6. Non-Goals

* Tag-only localization.
* Tag placement tooling, or telling an operator where to hang them.
* The G1. kronknav has no camera, so Go2 is the platform for now.

## 7. Future enhancements

* IR tags. An infrared camera sees them and people do not, so they stop being visible clutter in a
  customer's space. Pudu already does this, and Lita runs Pudu robots.
* Multi-tag fixes.
* Folding the survey into normal mapping runs.

## Architecture

Blocked on broader nav stack.

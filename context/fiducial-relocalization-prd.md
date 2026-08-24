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

A lost robot's only route back is an FPFH+RANSAC search over the pre-map: roughly 50,000 points of
local map before it fires, 4.4-23 s of CPU per attempt on a Go2/Orin, and in a featureless corridor
it never converges.

* **Omakase**: drift in 100m featureless hospital corridors (Mid-360 sees ~50m); relocalization
  failed when 20 media people crowded the robot.
* **Lita Hotel**: already relocalizes off Aruco tags per room; wants less manual, ops-heavy work.

### Why now?

Relocalization is the named failure in a live deployment, and kronknav is landing without it.

### Existing alternatives

* FPFH+RANSAC search: seconds per attempt, fails where drift is worst.
* Drive the robot to a known start pose: needs a human; nothing mid-run.
* Roll your own tags: what Lita did.

## 2. Solution

### Customer messaging

Look at a tag, know where you are.

### Solution

Survey once into a marker map (tag id to map pose). A tag in view proposes a fix, judged by the
same accept gate as every other source; each published fix names its source.

### Our current state

It does not work end to end yet: 0 of 29 fixes on the office recording. The surveyed tag poses are
off (translation RMS ~0.6 m, orientation spread up to 88 deg) and the judge correctly rejects them.
Two unseparated suspects: per-unit Go2 camera calibration, and the mirror-ambiguity gate dormant
because corner pixels are dropped on the wire. **Marker pose quality, not wiring, decides whether
this ships.**

### Options rejected

* Trusting a tag sighting directly: a planar tag pose is mirror-ambiguous; an unjudged fix can be
  metres off.
* Tag-only localization: the map still judges the fix.

## 3. Usage scenarios

### Scenario 1 - Omakase (featureless hospital corridor)

Tags at corridor intervals pull the robot back onto the map; one high on a wall stays visible
through a crowd. Refuse a tag seen small, far and oblique.

### Scenario 2 - Lita Hotel (per-room localization, less ops)

The tags they already hang, surveyed once instead of hand-configured per room. Hard case: reduce
their setup work, not add a second tagging regime.

## 4. Success metrics

* More than zero accepted `source=fiducial` fixes per recording (zero today).
* Under 2 s from tag visible to published fix.
* Per-tag orientation spread under 25 deg in the survey export.
* Zero bad fixes.

## 5. Features

* Surveyed marker map: tag id to map pose.
* Tag-sighting source feeding the existing judge.
* Per-tag pose spread reported at survey; source label on every published fix.

## 6. Non-Goals

* Tag-only localization.
* Tag placement tooling, or deciding where tags hang.
* The G1: the kronknav stack has no camera, so Go2 is the platform for now.

## 7. Future enhancements

* IR tags: fiducials an infrared camera sees but the eye does not, so tags stop being visible
  clutter. Prior art: Pudu, and Lita runs Pudu robots today.
* Multi-tag fixes.
* Survey folded into normal mapping runs.

## Architecture

The team decides it, down to the back of the napkin.

One fact to start from: relocalization runs on go2's older 2D costmap blueprint alone.
`unitree_go2_nav_3d` and kronknav's `unitree_g1_nav_3d` are the same stack, and neither
relocalizes. Putting it on the 3D path is part of the decision.

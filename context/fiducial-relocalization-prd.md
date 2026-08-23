# Fiducial Relocalization PRD

| | |
|---|---|
| **Owner** | Aaryan |
| **Project** | [Fiducial Relocalization](https://linear.app/dimensional/project/fiducial-relocalization-7e1526f21b10) (Engineering v2) |
| **Status** | Draft |
| **Last updated** | 2026-08-22 |

## 1. Problem

A robot that boots inside a building it has already mapped does not know where it is. The only route
back today is an FPFH+RANSAC global search over the pre-map. That search needs about 50,000 points of
local geometry before it will fire, costs 4.4-23 s of CPU per attempt on a Go2/Orin, and it matches
geometry — so in a corridor or against a bare wall there is nothing distinctive to match and it does
not converge. The operator waits, drives the robot somewhere with more structure, or restarts the map.

The same gap shows up mid-run: when LIO drift accumulates in a feature-poor space, the mechanism that
would correct it is the mechanism that space defeats.

### Why now?

- The pluggable-prior work already landed the hard part: candidate proposers feed one shared judge.
  A tag source is now an additive change, not a rewrite.
- kronknav is landing. Relocalization is currently welded to go2 nav, so it cannot follow. Whatever
  we build has to stand on its own.

### Existing alternatives

| Alternative | What works | Remaining gap |
|---|---|---|
| FPFH+RANSAC global search | No infrastructure, works anywhere with distinctive geometry | Seconds per attempt, needs dense structure, fails in corridors and bare rooms |
| Drive to a known start pose | Exact | Requires a human and a marked spot; useless after a mid-run drift |
| Re-map the space | Always works | Throws away the map the robot was supposed to reuse |

## 2. Solution

### Customer messaging

**Look at a tag, know where you are.**

For teams running a robot in a space that has been surveyed once: put a few AprilTags on the walls,
and the robot recovers its position from a single tag sighting instead of waiting on a geometric
search that may never succeed.

### What we are building

1. **Survey once.** Drive the space and export a marker map — tag id to pose in the map frame.
2. **Run with the marker map.** When a surveyed tag comes into view, the robot proposes a position
   fix from it.
3. **One gate for every fix.** Tag fixes and search fixes go through the same accept check against
   the pre-map. Only fixes that score well are published, and each published fix says which source
   produced it.

The tag is a shortcut to a *candidate*, never a shortcut past the check.

It ships as its own module set, composable with any navigation stack — including one with no
navigation at all.

### Non-goals and rejected options

- **Not building:** tag-only localization. The fix is still judged against lidar geometry.
- **Not building:** tag placement or survey tooling beyond the existing export.
- **Rejected:** publishing a tag sighting directly. A single planar tag has a mirror-ambiguous pose;
  an unjudged fix can be metres off in the wrong direction.

## 3. Usage scenarios

### Scenario 1 — Operator cold-starts a robot in a mapped office

- **Context:** robot powered on mid-building, pre-map loaded, no pose.
- **Trigger:** a surveyed tag enters the camera view.
- **Expected path:** a published fix within seconds, without driving to find geometry.
- **Hard case:** the tag is seen small and at a steep angle. The fix should be refused, not published
  badly.

### Scenario 2 — Long run drifts in a feature-poor corridor

- **Context:** LIO drift has accumulated; the corridor has nothing for the geometric search.
- **Trigger:** the robot passes a surveyed tag.
- **Expected path:** drift corrected at the tag, source labelled fiducial.
- **Hard case:** the correction must not jump the robot's pose mid-motion.

## 4. Product requirements

| ID | Requirement | Priority | Proof |
|---|---|---|---|
| R1 | A robot with a surveyed marker map recovers its position from a tag sighting, with no geometric search | Must | Hardware run; accepted fix labelled `source=fiducial` |
| R2 | Every published fix carries a health score, and fixes below the bar are refused | Must | Refusal logged with score against threshold |
| R3 | The survey reports the pose quality of the marker map it produced | Must | Per-tag spread in the survey export |
| R4 | The capability runs as its own module set, composable with any nav stack | Must | Same modules run on two different nav stacks |
| R5 | An operator can tell which source produced each fix | Should | Source labelled in the log and the viewer |

## 5. Success metrics

| Outcome | Target | How measured |
|---|---:|---|
| Fixes won by the tag source | > 0 accepted, `source=fiducial` | Benchmark suite, per recording |
| Time from tag visible to published fix | < 2 s | Sighting timestamp to fix timestamp |
| Surveyed tag orientation spread | < 25 deg per tag | Marker survey export |
| Bad fixes published | 0 | Referee-tag error per accepted fix |

### Launch guardrails

- **Safety:** no fix publishes without passing the accept gate.
- **Reliability:** the geometric search keeps working with the tag source disabled.
- **Compatibility / operations:** a stack that does not opt in is unchanged.

---

## Open product questions

- **Marker pose quality is the live blocker, not wiring.** End to end on the office recording the tag
  source wins 0 of 29 fixes: surveyed tag poses are off by ~0.6 m translation RMS with orientation
  spread up to 88 deg, and the judge correctly rejects them. Two suspects, not yet separated —
  per-unit Go2 camera calibration, and the mirror-ambiguity gate being dormant live because corner
  pixels are dropped on the wire. R3 exists because of this: a survey that cannot report its own
  quality hides the failure.
- **The G1 kronknav stack has no camera.** Go2 is the demonstrable platform until one is added.

---

**Technical implementation:** [Fiducial Relocalization — Technical Architecture](fiducial-relocalization-architecture.md)

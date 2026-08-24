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

Robots need to recover their position after drift or restart so they can keep working without an
operator, even in repetitive or crowded spaces where geometry alone is ambiguous.

Two partners already need this:

* Omakase saw drift in 100m featureless hospital corridors, where the Mid-360 only sees about 50m.
  Relocalization then failed outright when 20 media people crowded the robot.
* Lita Hotel relocalizes off Aruco tags per room today, and wants less manual, ops-heavy work.

### Why now?

Relocalization is the named failure in a live deployments (above).

### Existing alternatives

* The RANSAC search. Lower confidence than fiducial and mre expensive to run. Also needs Lidar.

## 2. Solution

### Customer messaging

Want to deploy 10 robot dogs? Put up AruCo tags, ONE teleop premap run, and deploy as many with the same shared map.

### Solution

Survey the space once into a marker map that holds a pose for each tag id. After that, a tag in
view proposes a candidate for robot pose in said environment map. This goes through quality gates and is applied if passed. Fiducial relocal can apply within first second of restart if tag in sight.

### Our current state

Have a working demo. Need to re-architect, review and merge. Probably also switch to Rust.

### Options rejected

None

## 3. User stories

I am a user running a robot in a repetitive or crowded corridor, and I can use a surveyed tag to recover its position because I want it to continue without my help.

I am a user deploying a robot across many rooms, and I can survey tags once because I want the robot to recover without configuring every tag by hand.

---

## 4. Success metrics

| Outcome | Target | How measured |
| -- | -- | -- |
| Reliable recovery | Every clear sighting of a surveyed tag produces a correct fix | Held-out recordings and live runs |
| Fast recovery | A fix publishes within 2 s of the tag becoming visible | Sighting and fix timestamps |
| Safe recovery | No incorrect fix is published | Position error for every accepted fix |
| Reliable survey | Every saved tag passes its pose-quality checks | Marker survey report |

---

## 5. Technical implementation sketch

Blocked on broader nav stack.

---

## 6. Link of full technical implementation

---

## 7. Optional appendices

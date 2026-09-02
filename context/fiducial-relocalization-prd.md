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

Robots need to recover their position after drift or restart so they keep working without an
operator, even in repetitive or crowded spaces where geometry alone is ambiguous.

Two partners already need this:

* Omakase saw drift in 100m featureless hospital corridors, where the Mid-360 only sees about 50m,
  and relocalization then failed outright when 20 media people crowded the robot.
* Lita Hotel relocalizes off Aruco tags per room today and wants less manual work.

### Why now?

Relocalization is the named failure in a live deployments (above).

### Existing alternatives

* The RANSAC search has lower confidence than fiducial, is mre expensive to run, and needs Lidar.

## 2. Solution

### Customer messaging

Want to deploy 10 robot dogs? Put up AruCo tags, do ONE teleop premap run, and deploy all 10 on the same map.

### Solution

Survey the space once into a marker map with a pose for each tag id. After that, a tag in view
proposes a robot pose in that map, and it is applied once it passes the quality gates. With a tag in
sight, the fix can apply within first second of restart.

### Our current state

Have a working demo. Need to re-architect, review and merge. Probably also switch to Rust.

### Options rejected

None

## 3. User stories

I am a user running a robot in a repetitive or crowded corridor, and I can recover its position from a surveyed tag because I want it to keep going without my help.

I am a user deploying a robot across many rooms, and I can survey tags once because I want it to recover without configuring every tag by hand.

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

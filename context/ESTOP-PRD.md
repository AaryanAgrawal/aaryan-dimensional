# E-stop module

**Status:** Draft, 2026-08-24

## 1. Problem

### What is the problem we are solving?

A humanoid can fall while control tasks keep running, and an operator has no shared latching stop across its blueprints.

### Why now?

The G1 locomotion stack needs this safety path before it can run unattended.

### Existing alternatives

Operators can stop individual controls, but those stops are not shared, fall-triggered, or latched.

---

## 2. Solution

### Customer messaging

One stop that holds until you reset it.

### Solution

Add one latching module with manual stop and humanoid fall detection; only a healthy manual reset clears it, and reset never starts the robot.

### Our current state

The Rust detector runs on recorded fall data but is not wired into a full robot stack.

### Options rejected

Automatic reset, because the operator must inspect the robot before rearming it.

### Not in this PRD

Additional stop conditions and automatic restart.

---

## 3. User stories

I am a user who needs to stop the robot manually so I can make it safe immediately.

I am a user who needs the robot to stop when it falls so it cannot keep running unsafe control tasks.

I am a user who needs to reset the latch manually so I can inspect the robot before it moves again.

---

## 4. Success metrics

| Outcome | Target | How measured |
| -- | -- | -- |
| Manual stop | Every manual stop latches the E-stop | Integration and live robot tests |
| Fall stop | Every deliberate humanoid fall latches the E-stop | Live fall tests |
| Normal operation | No false stop while standing or walking normally | Standing and walking tests |
| Manual reset | A healthy manual reset clears the latch without starting motion | Integration test |

---

## 5. Technical implementation sketch

* Condition 1 is manual stop.
* Condition 2 is humanoid fall detection.
* Either condition sets one latch; only a healthy manual reset clears it.
* Each embodiment owns defaults that every root blueprint composes.

---

## 6. Link of full technical implementation

https://github.com/dimensionalOS/dimos/issues/3621

---

## 7. Optional appendices

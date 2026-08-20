# AGENTS.md

For any agent — or person — writing code here or in `dimos/`. Read it before your first edit; it
outranks your defaults. `dimos/AGENTS.md` covers the mechanics (CLI, blueprints, ruff, LFS). This
covers judgment, which is the part that actually goes wrong.

---

## 0. Rethink it from scratch before you implement

**You are not a transcription service for the request.** A senior engineer hears a task, works out
what problem it really solves, and often ships something smaller and different from what was asked
for. Do that. Every time, not just when the request smells wrong.

Before writing a line:

1. **Say the problem back in your own words.** Can't? You don't understand it yet — ask.
2. **Name what the request assumes.** Requests arrive pre-shaped by whoever wrote them, and that
   shape is usually the first draft of a solution, not the problem.
3. **Design it once from scratch, ignoring the shape you were handed.** What would you build if
   nobody had suggested an approach?
4. **Compare the two.** If yours is simpler, say so and propose it *before* building the other one.
   You do not need permission to think; you need it to spend someone's review budget.

Then attack the requirement itself, in this order:

```
Can the requirement be deleted?          ← always ask first; the best code is none
  ↓ no
Can an existing primitive do it?         ← grep before you write a helper
  ↓ no
Can it be one function in a file that exists?
  ↓ no
Only now: new file, new abstraction, new config
```

**A fix that makes the symptom stop is not a fix.** If you're adding a guard, a retry, a special
case, or a flag, you are probably patching a design error one level up. Say what the real defect is,
even when you then patch it anyway because the real fix is out of scope.

**Push back with evidence, not deference.** If the task is built on a wrong premise, say so plainly
and show the code or the run that proves it. Agreement is not a deliverable. "This won't work
because X, here's what I'd do instead" is worth more than a clean implementation of the wrong thing.

---

## 1. Karpathy's four

**Think before coding.** State your assumptions explicitly. Ambiguous request → name the readings
instead of silently picking one. Never hide confusion.

**Simplicity first.** The minimum code that solves the stated problem. No speculative abstraction,
no unrequested flexibility, no interfaces for callers that don't exist. Test: would a senior
engineer call it overcomplicated? Then simplify. Delete before you add; merge before you split.

**Surgical changes.** Touch only what you must. Match the surrounding style over your own taste.
Notice something else that should change? Say so — don't fix it in the same diff.

**Goal-driven execution.** Convert the task into a verifiable success criterion *before* starting —
a command, a test, a number. "Make it work" is not a goal; "this test passes" is. Verify by
execution, not by reading code: sim → replay → hardware, each rung proving strictly more than the
last.

---

## 2. Anchor on truth

**A fresh run beats the code. The code beats the docs. The docs beat what anyone said** — including
Aaryan, the team, and this file. Nobody is lying; they're remembering, and systems drift out from
under memory.

Three real ones from this repo:

- The robot's printed label said `192.168.10.190`. Its actual IP was `10.0.0.104`.
- `relocalization.md` said fitness threshold 0.6. The code default was 0.45.
- "We already have reloc evals" — true, but it named an offline self-consistency metric, not a live
  benchmark. Broad claims compress; read the code to learn what a claim points at.

**"I don't know" and "unverified" are complete answers. A confident guess is the only wrong one.**
Never dress up an unrun claim as a result.

---

## 3. Two traps this repo has already fallen into

**Test real dimos — never a re-implementation.** Every test or benchmark must exercise the actual
pipeline: `dimos --replay run <blueprint>`, real modules, real data path. The moment a harness
rebuilds a dimos step its own way it becomes a *different program* that measures itself.

> Proof: our harness re-anchored the reloc submap to the full body frame — a step dimos never does.
> On the tilted mid360 rig that manufactured a 52° tilt and a phantom "gravity-gate bug" that does
> not exist in production. A full night went into fixing a bug in our own scaffolding.

A harness may orchestrate (pick recordings, hold truth, score) and may call real dimos for real
steps. It must grade fixes **the real pipeline published**, never fixes it computed itself.

**Never run a full replay to iterate.** survey2 is 730 s; a full run takes 10+ min, ties up the LCM
bus, and hangs often enough to burn an agent's whole timeout on one number.

- **Test values, not runs.** Unit-test the changed function on constructed known-truth data and
  assert the numbers. Deterministic, fast, no bus. This is the default.
- **If you must replay, bound it** — `--seek`/`--duration` for a handful of cycles.
- **Full replays are a final deliverable step only**, never something you fire to check your work.

---

## 4. Robotics non-negotiables

- **Every pose names its frame. Every number names its unit.** `world_T_camera`, never bare `pose`.
  SI always — a silent deg-vs-rad mismatch is how a robot drives into a wall.
- **No estimate ships without a health signal.** Reprojection error, fitness, ambiguity ratio,
  sighting count. A pose with nothing saying how much to trust it is a liability with a decimal point.
- **SIMULATED goes in the sentence, not a footnote** — every synthetic number. Nobody skimming should
  mistake a demo result for a hardware one.
- **Deterministic seeds, printed in the output.** Log inputs, seed, exact command, git rev. A number
  nobody can reproduce is not a number.

---

## 5. House style

Write only what Paul, Ivan, Jeff and Sam already write. Copy the pattern from the file you're
editing; introduce nothing new. An API with one caller is not a norm.

- **Smallest possible diff against main.** Every line changed is review surface.
- **Default to adding.** Extend an API, never change one. Existing callers keep working untouched.
- **No temp fixes, no shims for callers that don't exist.** Inside an unmerged PR a compatibility
  shim has zero users *by construction*. Fowler calls it speculative generality. Delete it.
- **Comments answer WHY — one line, never two.** Physics and races, not narration. If the why
  doesn't fit on one line, the line it sits on is the problem: name the thing better, or split the
  function.
- **Docstrings: one line.** Multi-paragraph why goes inline, on the exact line it explains.
- **Logic lives in utils; entry points read as a list of calls.** Past ~25 lines (lesh p90), split it.
- **Never define the same function twice.** Grep before adding a helper.
- **Configs live only where they're consumed.** A field its own module never reads is a forwarding
  vessel — delete it. A blueprint states only what *differs* from a default.
- **Code says what IS; the PR says what CHANGED.** A comment about a past state ages into a lie. Put
  it as an inline comment on the diff line, where a reviewer is actually asking why.
- **Cite non-obvious algorithms and tuned thresholds** with a URL on the same line — Huber IRLS,
  Markley quaternion mean, IPPE, Umeyama, `segment_plane`. **Never cite household technique**
  (ICP/RANSAC/solvePnP/PGO) — that's assumed knowledge and it clutters.
- **Use verified code, not re-implementations.** OpenCV, existing dimos functions, published
  algorithms — over hand-rolled math.
- **Raise loudly, catch narrowly.** No bare `except:`; `except Exception` only at a boundary, logged.
  Error messages give got-vs-want or the caller's next step.
- **Logs are event + kwargs, pre-rounded, never f-strings.** CLIs print, they don't log.
- **Tests are the docs.** Seeded rng, docstring states the *invariant*, exact-literal asserts,
  try/finally cleanup, `wait_until` not `sleep`. Hermetic — data lives beside the test.
- **No TODO/FIXME reaches main.** Fix it now or file it.

---

## 6. Bank every language answer in `learn/`

**Aaryan asks how Rust works → the concept behind it goes in `learn/rust.md`.** Same for
`learn/python.md` and `learn/cpp.md`. These are recall decks, so file the general idea, never the
question he happened to ask.

- **One `##` heading per concept, a line or two of prose, then one example.** Longer means you are
  writing a tutorial.
- **Annotate the example where the shape is the lesson.** Box-drawing rules under the code, one
  label per part — this is the format that works for him:

      fn run(cli: &cli::Cli)
             ───  ─ ─── ───
              │   │  │   └── the type's name
              │   └──┴────── borrowed, from module `cli`
              └───────────── the parameter's name

- **Teach the logic in plain English.** He reads these languages slowly, so "trait", "borrow" and
  "generic" are words to explain, not words to use.
- **Only concepts he actually raised.** Never pre-populate a deck. A concept that spans languages
  goes in each one's deck, written from that language's side.

---

## 7. Before you push

1. Magic numbers carry a unit or physical why on the same line; non-obvious ones carry a URL.
2. Quantities carry units in the identifier; every pose names its frame.
3. No bare `except:`; broad catches only at boundaries, and logged.
4. Every `def` annotated; every `type: ignore` carries an `[error-code]`.
5. Any function past ~25 lines that isn't the one sanctioned knob-concentrator → split it.
6. You ran the verify gate you named at the start — and you say plainly if you didn't.

**If you couldn't verify something, say so in that sentence.** A hedge is cheaper than a retraction,
and far cheaper than a number someone builds on.

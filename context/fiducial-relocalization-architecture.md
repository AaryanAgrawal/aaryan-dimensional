# Fiducial Relocalization — Technical Architecture

**Product requirements:** [Fiducial Relocalization PRD](fiducial-relocalization-prd.md) ·
Linear: [project](https://linear.app/dimensional/project/fiducial-relocalization-7e1526f21b10) (Engineering v2),
[PRD doc](https://linear.app/dimensional/document/fiducial-relocalization-prd-237b121c02e4) (Engineering v1)

Reference build: `feat/relocalization-fiducial-prior` (PR #3162, draft). Nav stack it must not depend
on: `andrew/feat/g1-kronk-nav` (`unitree-g1-nav-3d`).

---

## 1. Base flow

What exists today, on the PR branch:

```
color_image ──► MarkerDetectionStreamModule
                  │  QualityWindow → DetectMarkers (OpenCV, world-framed pose)
                  ├──► detections            Out[Detection3DArray]  ──► MarkerTfModule
                  └──► aggregated_detections Out[Detection3DArray]        (tap: AggregateTagBursts)
                              │
                              ▼
lidar ──► VoxelGridMapper ──► global_map ──► RelocalizationModule
                                              │  FiducialPrior.observe_detections
                                              │    map_T_world = map_T_marker ∘ inv(world_T_marker)
                                              │  RansacPrior.propose  (polled, interval_s=2.0)
                                              │            ▼
                                              │    refine_candidates()   ← the one judge
                                              │    fitness ≥ threshold?
                                              ├──► tf: world → map
                                              ├──► merged_map  ──► CostMapper   ← go2 nav only
                                              └──► accepted_fixes (rerun, eval only)
```

The prior split is sound and stays: proposers generate candidates, one fine-ICP judge
(`refine_candidates` in `relocalize.py`) decides. Everything below is about where the boundaries sit.

## 2. What is wrong with it

### 2.1 Four welds to go2 nav

| # | Weld | Why it blocks kronknav |
|---|---|---|
| 1 | `unitree_go2_relocalization = autoconnect(unitree_go2, …)` and `unitree_go2` *is* VoxelGridMapper + CostMapper + ReplanningAStarPlanner + WavefrontFrontierExplorer + PatrollingModule + MovementManager | Reloc cannot be run without dragging in a planner it does not use |
| 2 | `merged_map: Out[PointCloud2]` exists solely to feed `CostMapper` | kronknav has no CostMapper — MLSPlannerNative plans over traced voxel surfaces directly |
| 3 | `FRAME_WORLD = "world"` / `FRAME_MAP = "map"` are module constants | kronknav plans in `odom` (`MLSPlannerNative.blueprint(world_frame="odom")`) |
| 4 | The G1 kronknav stack has no camera at all — its blueprint says so outright | Fiducial reloc on the G1 is a hardware prerequisite, not a wiring task |

The input side already ports cleanly: **both** `VoxelGridMapper` (go2) and `RayTracingVoxelMap`
(G1 kronknav) publish `global_map: Out[PointCloud2]`, which is exactly what reloc consumes. So
decoupling is mostly deletion.

### 2.2 The marker module boundary

Three separate defects, worth not conflating:

**(a) A relocalization concern lives in a perception module.** `AggregateTagBursts` — burst gating,
Huber mean, covariance, score — sits inside `MarkerDetectionStreamModule` as a `tap`, publishing a
second output `aggregated_detections` that only relocalization consumes. Perception publishes a
reloc-shaped product.

**(b) The detector is already a localizer.** `DetectMarkers` composes each marker pose into the
**world** frame from the camera-in-world TF — so what it publishes is `world_T_marker`, expressed in
the drifting frame relocalization exists to correct. The module cannot be reused by a stack with a
different world frame without config surgery.

**(c) Priors are pluggable in the solve and hardcoded in the wiring.** This is the structural one:

```
RelocalizationModule:
    global_map:            In[PointCloud2]        ← generic
    aggregated_detections: In[Detection3DArray]   ← fiducial-specific, on the generic module
```

`RelocPrior` abstracts `propose()`, but every event-driven prior needs a hand-declared port on the
generic module. A second event prior (visual place recognition, WiFi, GPS) means editing
`RelocalizationModule` again. That is not a plugin system.

## 3. Alternatives

### A — Status quo, extended: one port per prior

Keep priors in-process; declare an `In` port per event-driven prior on `RelocalizationModule`.

- **For:** zero new message types; lowest latency (the fiducial prior fires in-process on the burst
  edge, judged against the cached cloud); smallest diff.
- **Against:** the generic module accumulates prior-specific ports; every new prior edits shared code;
  perception keeps publishing a reloc-shaped output.

### B — Candidate bus: prior modules publish, reloc judges

Each prior becomes its own module publishing candidates on one shared topic. Reloc has one
prior-facing input.

```
detections ──► FiducialPriorModule ─┐
               aggregate → compose  │
                                    ├──► reloc_candidates ──► RelocalizationModule
global_map ──► RansacPriorModule ───┘    (fan-in, one topic)    refine_candidates + gate
     │                                                                   │
     └───────────────────────────────────────────────────────────────────┤
                                                                         ▼
                                                                  tf: world → map
```

- **For:** a new prior is a new module plus a topic, with zero edits to `RelocalizationModule`;
  aggregation leaves perception; priors become independently testable and independently deployable.
- **Against:** needs a `RelocCandidates` message type (see §5); adds a transport hop to the fiducial
  path, which is the latency-sensitive one; the judge still needs `global_map`, so reloc keeps a
  mapper dependency regardless.

### C — Fiducial prior module owns the camera end to end

`FiducialRelocalizationModule` takes `color_image` + `camera_info` and does detect → aggregate →
compose itself. `MarkerDetectionStreamModule` is untouched and unused by reloc.

- **For:** total independence; no reliance on a perception module's output shape.
- **Against:** a second OpenCV detection pass whenever both modules are in one stack — pure waste,
  and on the Orin it is not free.

## 4. Recommendation

**Target architecture is B. Sequence it so B is a pure addition, and do not build the bus until a
third prior exists.**

Reasoning: the bus earns its keep when the *second* event-driven prior lands. Today there is exactly
one, so shipping `RelocCandidates` plus two wrapper modules now is a caller that does not exist —
speculative generality by our own rule. What is worth doing immediately is the part that is wrong
regardless of how many priors there are: the nav welds, and the aggregation living in perception.

**Direct answer to "will MarkerDetectionStreamModule exist":** yes — it has non-reloc consumers
(`MarkerTfModule`, the `desk_marker_tf` blueprint) and it stays. What should stop existing is its
`aggregated_detections` output and the `AggregateTagBursts` tap. Relocalization subscribes to the raw
per-frame `detections`, which are already world-framed, so the move costs no second OpenCV pass and
no extra TF lookup. That deletes a reloc-shaped port from a perception module and is a small diff.

### Staged rollout

| Stage | What | Delivers | Cost |
|---|---|---|---|
| 1 | Cut the four nav welds | R4 — runs on any stack | Small, mostly deletion |
| 2 | Move aggregation out of perception into the fiducial prior | Fixes (a); (b) becomes config | Small, a move not a rewrite |
| 3 | Marker pose quality: per-unit calibration + corners on the wire | **R1 — the feature actually works** | The real work |
| 4 | Candidate bus, when a third prior lands | True pluggability | New message + N modules |

Stage 3 is the one that matters for whether this ships. Stages 1 and 2 are cheap and unblock
composition; stage 4 is deferred on purpose.

### Stage 1, concretely

```
- merged_map: Out[PointCloud2]              # delete: it exists only for go2's CostMapper
- FRAME_WORLD = "world"                     # delete: constants
- FRAME_MAP   = "map"
+ world_frame: str = "world"                # Config fields, so kronknav can say "odom"
+ map_frame:   str = "map"
```

and the blueprint stops being the nav stack:

```python
# before — reloc is defined as "the whole go2 nav stack, plus markers"
unitree_go2_relocalization = autoconnect(unitree_go2, MarkerDetectionStreamModule.blueprint(...), RelocalizationModule.blueprint())

# after — a fragment that composes onto anything publishing global_map
relocalization = autoconnect(
    MarkerDetectionStreamModule.blueprint(camera_info=GO2Connection.camera_info_static),
    RelocalizationModule.blueprint(),
)
unitree_go2_relocalization = autoconnect(unitree_go2, relocalization)
```

The map merge, if still wanted for go2, becomes its own small module that go2's blueprint adds and
kronknav does not. It is not relocalization's job.

## 5. Interfaces

### Today (stages 1–3)

| Port | Type | Direction | Source / sink |
|---|---|---|---|
| `global_map` | `PointCloud2` | In | `VoxelGridMapper` (go2) or `RayTracingVoxelMap` (G1) |
| `detections` | `Detection3DArray` | In | `MarkerDetectionStreamModule`, per frame, world-framed |
| `tf: world → map` | `Transform` | Out | Any consumer of the correction |
| `accepted_fixes` | `EntityMarkers` | Out | Rerun, under `eval` only |

### Stage 4 — the candidate message

Decision needed. `geometry_msgs.PoseArray` already exists and its own docstring names this use
("multiple candidate positions … particle filter samples"), but it carries no source label, and one
fan-in topic requires the source to be *in* the message. Three ways:

1. **New `RelocCandidates`** — `{ source: str, candidates: Pose[], evidence: float }`. Clean, honest,
   costs one message type and its codegen. **Recommended.**
2. **Reuse `PoseArray`, source in `header.frame_id`** — no new type, but `frame_id` names a frame and
   this is not one. A reviewer will object, correctly.
3. **Reuse `Detection3DArray`** — `id` carries the source, `results[].score` the evidence. Fits
   mechanically, but a relocalization candidate is not a detection and the name will mislead.

### Frames and units

Every candidate is `map_T_world`, 4×4, metres and radians. The judge consumes `map_T_world` and the
module publishes its inverse as the `world → map` TF — that inversion stays in one place
(`_publish_fix`), not in any prior.

## 6. Local state and ownership

- `RelocalizationModule` owns: the pre-map (loaded once at `start()`), the accept gate, the
  publish lock that orders concurrent solves, and the eval tally. It owns no prior state.
- `FiducialPrior` owns: the surveyed marker map, and pending fixes consumed on use — a re-offered fix
  scores worse because the world has drifted under it.
- `RansacPrior` is a pure source; the module owns its poll timer.
- The surveyed marker map is a file (`.json`, resolved via `resolve_named_path`), produced offline by
  `dimos map global --markers --export`. It is an input, never written at runtime.

No cloud boundary. Everything is on-robot.

## 7. Test plan

Per the house rule: unit-test values, never a full replay to iterate.

- **Unit, constructed known-truth.** Candidate composition — build `map_T_marker` and
  `world_T_marker` by construction, assert `map_T_world` to exact literals. Aggregation — seeded
  `np.random.default_rng` sightings around a known pose, assert the Huber mean converges. Frame
  config — assert the published TF names the configured frames, not `world`/`map`.
- **Integration, bounded.** A short `--seek`/`--duration` slice through real dimos, enough for a
  handful of reloc cycles: assert accepts and rejects appear with a source label. Never the whole
  recording.
- **Hardware.** Go2 with a surveyed marker map; the fix published with `source=fiducial` is the proof
  for R1. The G1 is out of scope until it has a camera.
- **Portability, for R4.** The same reloc fragment deployed on two stacks. This is the test that
  would have caught all four welds.

## 8. Decisions to approve

1. **Reloc publishes the `world → map` correction and nothing else** — `merged_map` is deleted and the
   go2 map merge becomes its own module, or is dropped. *(Blocks stage 1.)*
2. **Aggregation moves from `MarkerDetectionStreamModule` into the fiducial prior**, and
   `aggregated_detections` is deleted. *(Blocks stage 2.)*
3. **Defer the candidate bus until a third prior exists.** Approve the target shape now, build it then.
4. **Stage 3 is the priority** — the feature does not work until marker pose quality is fixed, and the
   two suspects (per-unit Go2 calibration; the dormant mirror gate, dormant because `corners_px` are
   dropped on the wire) have not been separated. Which one is chased first needs a call.

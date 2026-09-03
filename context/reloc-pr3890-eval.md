# PR #3890 lidar relocalization — measured evaluation

leshy's `feat/ivan/relocalize2` (PR dimensionalOS/dimos#3890). Our branch:
`aaryan/reloc3890-hyperparam-eval`, worktree `workspace/dimos/.claude/worktrees/reloc3890`.
Raw data + scripts: `workspace/lfs_scratch/reloc-eval-20260903/`.

Run 2026-09-03. Seed 0, o3d RANSAC seeded (the PR's own eval does not seed it).
Truth is identity (probe and premap share one LIO world frame). Hit = <=0.5 m and <=2.0 deg,
the eval's own tolerances. Premaps built with the documented `dimos map global --export` recipe.

## What the PR removed

The old `relocalization/relocalize.py` (deleted, 234 lines) verified a pool of ~34 candidates
through four filters. All four are gone; the accept path is now one scalar at
`lidar/relocalize.py:259`, `result.fitness < fitness_threshold`.

| removed | what it did |
|---|---|
| gravity gate `GRAVITY_TILT_MAX_DEG = 10.0` | dropped candidates tilting >10 deg off world up |
| centroid-aware 180 deg yaw flip | gave the opposite heading an explicit chance to compete |
| wall-only scoring (`_wall_subset`, `\|nz\|<0.7`) | scored on walls, since floors fit at any yaw |
| top-10 rerank + Tukey ICP | RANSAC's own fitness lies at coarse scale |

Search budget also collapsed: `SCALE_PLAN` 3 scales x restarts = 17 RANSAC runs -> `ransac_restarts=1`.

## Q1 — is `min_local_points = 2000` right?

Sweep of scans/probe against outcome, 8 probes per dataset, gate 0.6, full-cloud.

| dataset | 1 scan | 3 | 5 | 10 | 15 |
|---|---|---|---|---|---|
| SF-legacy  (hits/8) | 4 | 4 | 4 | 4 | 4 |
| tonight    (hits/8) | 7 | 7 | 7 | 7 | 7 |
| CHINA      (hits/8) | 0 | 0 | 1 | 2 | 1 |

**Point count is not the binding constraint.** SF and tonight hit every in-map probe at ONE scan
(~3.4-3.9k points, ~726-1164 coarse). More points only tightens median error (SF 0.164 -> 0.120 m).
China never works regardless: 35,726 points at 15 scans still yields 1 hit.

A real 1-scan accumulation gives ~900 coarse points because a mid360 sweep spans the full 30 m
range. An earlier compact-blob estimate of ~91 coarse points was unrepresentative; the 2000 floor
is not the problem it looked like.

## Q2 — does a tilt gate stop bad candidates?

Outcomes as hit/false/refused, gate 0.6, all scan counts pooled (56 probes/dataset).

| max_tilt | CHINA | SF-legacy | tonight |
|---|---|---|---|
| 1 deg  | 6/**2**/48 | 27/**0**/29 | 49/0/7 |
| 2 deg  | 6/3/47 | 27/0/29 | 49/0/7 |
| 3 deg  | 6/3/47 | 27/0/29 | 49/0/7 |
| 5 deg  | 6/4/46 | 27/0/29 | 49/0/7 |
| 10 deg | 6/4/46 | 27/0/29 | 49/0/7 |
| off    | 6/4/46 | 27/**1**/28 | 49/0/7 |

**Yes, and it costs nothing.** At 1 deg it removes 2 of China's 4 false fixes and SF's only one,
with **zero hits lost on any dataset**. The gate must be TIGHT: the old 10 deg value removes
nothing on China. Recommend `max_tilt_deg` ~1-2 deg, not 10.

Best measured combination: tilt gate 1 deg + full-cloud gate 0.6 = **82 hits / 2 false fixes**
across all three datasets.

## Q3 — wall-only vs full-cloud scoring

| dataset | gate | full (hit/false) | wall (hit/false) |
|---|---|---|---|
| CHINA | 0.30 | 6/22 | 6/**9** |
| CHINA | 0.45 | 6/11 | 6/**6** |
| CHINA | 0.60 | 6/4  | 2/1 |
| SF    | 0.30 | 27/4 | 27/**1** |
| tonight | 0.30 | 49/7 | 49/**5** |
| tonight | 0.45 | 49/4 | 49/**2** |

At a matched threshold, wall-only scoring **strictly reduces false fixes at identical hit counts**
on every dataset. But wall fitness is systematically lower, so it cannot be dropped into a 0.6
gate — at 0.6 it over-refuses China (6 hits -> 2). It needs its threshold retuned.

The tilt gate reaches the same false-fix count as wall@0.6 (2) while keeping 4 more hits, for a
3-line change instead of a rescoring plus retune. **Tilt gate is the better buy.**

## Axis B — search budget

5 scans, varying `voxel_coarse` x `ransac_restarts`.

| dataset | voxel | restarts | hits/8 | false | median s |
|---|---|---|---|---|---|
| CHINA | 0.40 | 1 | 2 | 1 | 3.6 |
| CHINA | 0.40 | **3** | **4** | **0** | 11.1 |
| CHINA | 0.59 | 1 | 0 | 1 | 1.6 |
| CHINA | 0.59 | **3** | **3** | 1 | 4.5 |
| SF | 0.40 | 3 | 5 | 0 | 5.5 |
| SF | 0.59 | 1 | 4 | 0 | 0.7 |

**Restarts are what rescue China.** `ransac_restarts=1` (the PR's value) gives 0 hits at the preset
voxel; 3 restarts gives 3-4, for 3-11 s instead of 1.6 s. The PR cut effective restarts from 17 to
1 and that is where China's hit rate went.

## Why China fails specifically

Not unseen ground — probes are covered; the premap holds those places.

- Wall fraction 41% (SF 57%), so **59% of every China fitness score comes from yaw-blind surfaces**.
  Consistent with the 44 deg pitch + 90 deg yaw mount putting the dense sweep on floor and ceiling.
- China's fitness at the TRUE pose is 0.23-0.63, median 0.42. **The 0.6 cutoff refuses correct
  answers outright.** SF's true poses sit at 0.76-0.91. The threshold does not transfer.
- Full-cloud scoring ranked the 180 deg flip ABOVE truth on 2 of 6 China probes (measured against
  an earlier seek-700 premap; the seek-950 premap is what Q1-Q3 above use).

`PRESETS` is keyed by SENSOR (`{"mid360": MID360}`) but SF and China are the same sensor. The axis
that fails to transfer is the ENVIRONMENT. Adding a per-rig preset cannot fix China.

## main vs PR head-to-head

Identical probes and premaps; main's `relocalize.py` imported unmodified from upstream/main.

| dataset | MAIN (wall + gravity + flips, 17 RANSAC) | PR #3890 |
|---|---|---|
| SF, 8 probes | 4 hits, **0 false**, 31-122 s/probe | 3 hits, **1 false**, ~1 s/probe |
| CHINA, 6 of 8 | 0 hits, 0 false, **175-564 s/probe** | 0 hits, 1 false, ~2 s/probe |

Main refuses on China rather than guessing. On SF main beat the PR by 96 m on one probe. The PR is
50-300x faster and less safe. Neither solves China.

## Bugs found in the PR

1. **`tune.py:339` corrupts every modern recording.** `accumulate` uses only the pose position and
   never rotates the cloud, valid only for world-frame `fastlio_lidar`. Recordings from
   `unitree-go2-mid360-record` today are `pointlio_lidar` in `mid360_link`. No frame check, so the
   study runs and prints a table off a garbage map. `dimos map global` already registers via tf
   (`_detect_world`), so the premap half works and only the probe half breaks.
   Fix verified against known truth: tf-registered and world-registered clouds agree to
   median AND p90 nearest-neighbour distance of 0.000 m.
2. **`min_frames` / `max_frames` are dead config in production.** Required fields on
   `RelocalizeConfig`, consumed only by `tune.py:501-523`. The live module has no retry ladder.
3. **`tilt_deg` computed and discarded.** `tune.py:463`/`537` store it; it is in no column, no
   summary, no objective — while being the signal that would justify or refute the deleted gate.
4. **Unseeded RANSAC.** Results are not reproducible; `verify`'s own docstring admits it.
5. **Trial 229 of `go2-sf-area1` has no artifact** — `optuna.db` is gitignored. Only the 15 winning
   numbers survive, and the file's rule is "do not nudge an existing one".

## Optuna study — 40 trials x 8 probes per dataset, SPACE v14

Search space now includes `max_tilt_deg` (1-180 log, so "no gate" stays reachable) and the
`min_frames`/`max_frames` window. Correctness-first read of each Pareto front:

| study | hit | false | err_m | lat_s | max_tilt | frames | voxel_coarse | restarts | threshold | orient |
|---|---|---|---|---|---|---|---|---|---|---|
| go2-sf-area1 | **1.00** | **0.00** | 0.092 | 4.96 | 4.7 | 4-19 | 1.10 | 3 | 0.72 | False |
| go2-china-office | **1.00** | **0.00** | 0.185 | 1.77 | **1.1** | 8-16 | **1.48** | 2 | 0.51 | False |
| go2-sf-office | **1.00** | **0.00** | 0.191 | 0.30 | 1.7 | 2-5 | 0.50 | 1 | 0.68 | False |
| go2-sf-area1-pointlio | 0.50 | 0.50 | 0.227 | 1.68 | 7.7 | 10-16 | 0.92 | 3 | 0.06 | False |

**China is solvable.** 100% hit, zero false fixes, 0.185 m. The MID360 preset is simply mistuned
for it, not defeated by it. Everything above about China's ambiguity describes the preset's
behaviour, not a hard limit of the algorithm.

Four patterns hold across every winning trial:

1. **`orient_normals=False` on all four winners.** The preset ships `True`.
2. **Optuna independently picked a TIGHT tilt gate** on all three solvable datasets — 4.7 / 1.1 /
   1.7 deg — when 180 (no gate) was equally reachable in the space. Independent confirmation of Q2.
3. **`voxel_coarse` wants to be far coarser than the 0.59 preset**: 1.10, 1.48, 0.50. China's
   winner is 2.5x the preset.
4. **No threshold transfers**: 0.72, 0.51, 0.68 across three datasets on ONE sensor.

Caveat: 40 trials over 8 probes, scored on the same probes they tuned on. These are upper bounds,
not holdout numbers. `verify --half-step` is the next step.

## Open question — the pointlio control

`go2-sf-area1-pointlio` is the SAME walk as `go2-sf-area1` in today's recording shape, and it
scores far worse at matched configs (trial 0: 0.8 hit / 0.125 false legacy vs 0.5 / 0.5 pointlio).

Registration is not obviously broken: `accumulate`'s tf path agrees with the baked-pose quaternion
path to 0.045 m median / 0.120 m max nearest-neighbour. But the tf path yields HALF the points
(7,795 vs 15,584 at 10 frames from 100 s), and `_detect_world` resolves to `odom`, not `world`.
Unresolved. Until it is, treat pointlio-registered results as suspect and prefer the baked pose
quaternion when an observation carries one.

## Recommendations

1. `max_tilt_deg` ~1-2 deg in the accept path. Free, removes false fixes, costs no hits, and the
   optimiser picks a tight gate on its own when offered "no gate". Best buy.
2. `ransac_restarts` 2-3, not 1. This is what China's hit rate actually depends on.
3. Revisit `orient_normals=True` — every winning trial across four studies chose False.
4. `voxel_coarse` 0.59 is too fine for indoor: China's winner is 1.48.
5. Do not ship `relocalize_once=True` with a single-scalar gate until 1 and 2 land.
6. Fix `accumulate`'s frame handling before anyone tunes a new rig with this tool.
7. Key presets by environment, not sensor — or state plainly that a preset is per recording.

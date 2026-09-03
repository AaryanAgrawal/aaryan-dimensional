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

## Recommendations

1. `max_tilt_deg` ~1-2 deg in the accept path. Free, removes false fixes, costs no hits. Best buy.
2. `ransac_restarts` 3, not 1. This is what China's hit rate actually depends on.
3. Do not ship `relocalize_once=True` with a single-scalar gate until 1 and 2 land.
4. Fix `accumulate`'s frame handling before anyone tunes a new rig with this tool.
5. Key presets by environment, not sensor — or state plainly that a preset is per recording.

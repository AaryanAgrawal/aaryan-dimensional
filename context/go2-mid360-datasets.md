# Go2 + Mid-360 datasets — recording, alignment, and the two recreations

Ask (leshy, Discord #navigation-private, 2026-09-02): record a Go2 + Mid-360 dataset with
`dimos --record`, recreate `recording_go2_mid360_2026-05-29_4-45pm-PST_corrected` (SF office) and
`china_office.db` in that structure with correct tf, keep the originals as raw, name the new ones
(`go2_mid360_sf_office_outdoors`, `go2_mid360_china_office`), and validate with `raytrace_rrd` and
`plan_rrd`. Andrew's tf requirement: `world -> odom -> mid360_link -> base_link`. Only these two
datasets; the rest below are reference only. No Linear ticket yet.

Workflow reports on the dev box: `workspace/go2-mid360-record-runbook-2026-09-02.md` (recording),
`workspace/datasets-sourcing-2026-09-02.md` (not written: the subagent limit hit; the 18 finished
agents' results are in the workflow journal `wf_021c7f61-4cd`). Scripts:
`workspace/recreate/append_tf.py`, `workspace/recreate/validate_tf.py`, and the measurement scripts in
the job tmp dir (`measure_alignment.py`, `synccheck.py`).

## Where the files are (dev box)

| dataset | path | size |
|---|---|---|
| SF corrected | `workspace/lfs_scratch/recording_go2_mid360_2026-05-29_4-45pm-PST_corrected.db` | 3.3 GB |
| SF uncorrected | `workspace/dimos/data/recording_go2_mid360_2026-05-29_4-45pm-PST.db` | 3.3 GB |
| China, pristine (23 streams) | `workspace/dimos-reloc/data/china_office.db` | 10.2 GB |
| China, contaminated (phantom empty `lidar`) | `workspace/dimos/data/china_office.db` | do not use |
| Athens | `workspace/lfs_scratch/mid360_athens_stairs.db` | 239 MB |
| today's reference (15:09 run) | `workspace/lfs_scratch/go2_mid360_today_2026-09-02.db` | 56 MB |

LFS download works anonymously: `git -c 'lfs.https://lfs.dimensionalos.com/dimensionalOS/dimos.access=none'
lfs pull --include=data/.lfs/<name>.tar.gz`, then `get_data('<name>.db')` (bare names need the `.db`).
Reading a stream name that does not exist CREATES an empty stream; that is how the phantom streams
appeared.

## What is in them (verified 2026-09-02)

- **SF corrected**: 5 streams, no tf, no raw Mid-360. `lidar` is the Go2 L1's own voxel map (frame
  `world`), `fastlio_lidar` is world-registered LIO output, `fastlio_odometry` (child `body`), `odom`
  (Go2, PoseStamped), `color_image`. Two unrelated frames both named `world` (Go2 vs FAST-LIO, 10 m
  residual under a rigid fit). "corrected" = `dimos map pose-fill` on the two cloud streams, nothing
  else.
- **China**: 23 streams; 10 real (livox_lidar, livox_imu, go2_lidar, go2_odom, pointlio_lidar,
  pointlio_odometry, color_image, tf, april_tags, april_tags_raw), 13 junk (`gt_*` second LIO run, 11
  `pointlio_odometry__*` sweeps). tf has six edges `world -> map -> odom -> mid360_link -> base_link ->
  front_camera -> camera_optical`; `world -> map` was appended after the fact and `map -> odom`
  identity is false (Go2 world and LIO odom differ by up to 27 m). Statics republish at 3.9 Hz, so
  `plan_rrd`'s base_link lookup (0.1 s tolerance) resolves 74% of frames.
- **Athens**: 3 streams, tf has ONE edge (`odom -> mid360_link`). Not a full-tf reference.

## Mount alignment, measured two ways (LIO first poses; floor-plane fit on sensor-frame clouds)

| dataset | date | tilt | axis | floor fit | static tf in db | body level? |
|---|---|---|---|---|---|---|
| SF corrected | May 29 | 45.1° | pitch | n/a (world clouds) | none | n/a |
| China | Jun 12 | 47.8° | roll (lidar yawed 90°) | 47.5° roll | 44° + 90° yaw | 3.9° off |
| Athens | Jul 8 | 46.4° | roll | 46.9° roll | none | n/a |
| Jul-16 (Jeff, Jetson) | Jul 16 | 55° | pitch | 54.6° pitch | no lidar->body link | n/a |
| sf_office_stairs (D455 rig) | Aug 4 | 25.1° | pitch | invalid | 25° | 0.4° |
| today's rig | Sep 2 | 61.1° | pitch | 60.7° pitch | main SF preset 60° | 2.3° |

Two bracket families: SF dog fore-aft (angle drifted 45° -> 55° -> 25° -> 61°), travel rig (China,
Athens) sideways at ~46-48° with the lidar yawed 90°. Main's `ATHENS` preset has the right axis and
the wrong magnitude (60° vs 46°). SF recreation needs a synthesized chain at 45° pitch, not 60°.

## How the raw Mid-360 is recorded

Payload stamps from the Mid360 native are lidar uptime, always. China's rows carry wall-clock store
timestamps (arrival) with uptime payloads (constant offset 1,781,258,737 s), so they align by store
ts. Today's `--record` rows copy the payload stamp (tap.py:115 `getattr(msg, "ts") or time.time()`),
so livox rows sit in 1970 and cannot be aligned. Fix in the native (stamp host time in the Livox
callback) or, smaller, make the tap fall back to wall clock for non-epoch stamps. Until then record
raw Mid-360 as pcap (`RECORD_PCAP=1`) and keep it out of `--record` with `--record-topics`.

## Recording command that ran clean on the dog (2026-09-02, stationary)

See `tickets/DIM-1583.md` "Run on the Go2" for the exact line. Essentials: `--transport lcm` (C++
natives are LCM-only), `--record sqlite --record-topics 'pointlio_*,tf,go2_*,color_image,camera_info'`,
`--disable go2-mid360-recorder`, `--pointlio.frame-id odom`, `--go2connection.odom-frame-id go2_odom`,
`--go2mid360statictf.publish-hz 20`, lidar IP flags. Result: 7 streams, zero drops, tf 42 Hz with
`odom -> mid360_link` + three statics, base_link level. With raw livox included the tap drops 5.9%.

## Recreation plan (agents' plans, refuter corrections applied)

- SF -> `go2_mid360_sf_office_outdoors.db`: `dimos map rename` fastlio_lidar->pointlio_lidar,
  fastlio_odometry->pointlio_odometry, lidar->go2_lidar, odom->go2_odom; un-register pointlio_lidar
  into `mid360_link` with its baked poses (verified: min range 0.5 m after inversion); synthesize tf
  with `append_tf.py` (dynamic `odom -> mid360_link` from odometry at every message, statics at
  >= 10 Hz: 5 Hz sits exactly on the 0.1 s tolerance), mount at 45° pitch; drop color_image (no
  camera_info, lossy re-encode). SF cannot be made 1-to-1 with a 19-stream `--record` db; 14 streams
  have no source.
- China -> `go2_mid360_china_office.db`: keep-list copy (`dimos map pose-fill --streams ...` or
  `dimos map rename --drop ...`) of pointlio_lidar, pointlio_odometry, go2_lidar, go2_odom,
  color_image, livox_lidar, livox_imu, tf; junk to `china_office_extras.db`; re-stamp statics at
  >= 10 Hz; optionally correct the mount to 47.8° roll. Its tf already resolves base_link.
- Acceptance: `raytrace_rrd` and `plan_rrd --lidar-stream pointlio_lidar` on each result.
- Decisions still open (leshy / Andrew): tf root `odom` vs `world`; keep Go2 L1 streams; livox clock
  fix; the record blueprint pins PointLio `frame_id="world"` and GO2Connection `odom_frame_id="world"`
  (name collision) - one-line upstream fixes.

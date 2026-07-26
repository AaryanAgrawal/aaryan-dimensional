#!/usr/bin/env python3
"""Deterministic relocalization benchmark over prepared sections. SUPERSEDED.

Retired for new grading by replay_bench.py + score_replay.py (BENCHMARK_METHOD.md):
this scores relocalize() directly on prep.py's body-frame submaps, and that
re-anchor is a step dimos never does. Kept for its archived SILVER numbers, which
analyze.py and regime_map.py still read out of out/results.

Scores relocalize() on every section prep.py produced, with the published fitness
captured per attempt. Determinism recipe is #2137's, replicated exactly: OMP
single-thread BEFORE open3d import, per-frame seeds = frame_idx, sorted order, fork
workers. Two #2137 defects are deliberately NOT replicated:
  - no frame is excluded, ever ("hard" frames are the interesting ones);
  - the denominator is ALL sections — crashed or over-budget attempts count
    as failures, so a slow-but-lucky config can't inflate its success rate.

The prior-pool arms (ransac+lastpose, ransac+fiducial, fiducial+judge) are gone with
the API they drove: dimos dispatches ONE prior at a time now (relocalize_with_prior)
and refine_candidates returns (T, fitness) with no winning index, so a per-candidate
source label cannot be recovered without re-implementing the judge. Grade priors
through replay_bench.py instead — it reads the winner off the real module's own log.

Run: cd dimos && uv run python ../trial/harness/run_bench.py hk_village3
"""

from __future__ import annotations

import os

os.environ.setdefault("OMP_NUM_THREADS", "1")  # BEFORE open3d import (determinism)

import argparse
import json
import pickle
import random
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
import open3d as o3d
from scipy.spatial.transform import Rotation

HARNESS = Path(__file__).parent
OUT_DIR = HARNESS / "out" / "results"

SUCCESS_T_M = 1.0  # #2137-comparable success bar
SUCCESS_R_DEG = 15.0
FITNESS_GATE = 0.45  # the bar every archived run in out/results was graded at; today's
                     # module gates per prior (PriorConfigBase.fitness_threshold 0.6,
                     # acquire_fitness_threshold 0.7) -- pinned so the archive stays comparable

# Fork-inherited worker state (set in main before pool creation).
_PREMAP_PTS: np.ndarray | None = None
_SECTIONS: list | None = None

_worker_premap = None  # per-process o3d cloud cache


def _premap_cloud() -> o3d.geometry.PointCloud:
    global _worker_premap
    if _worker_premap is None:
        pc = o3d.geometry.PointCloud()
        pc.points = o3d.utility.Vector3dVector(_PREMAP_PTS.astype(np.float64))
        _worker_premap = pc
    return _worker_premap


def _to_cloud(pts: np.ndarray) -> o3d.geometry.PointCloud:
    pc = o3d.geometry.PointCloud()
    pc.points = o3d.utility.Vector3dVector(pts.astype(np.float64))
    return pc


def _errors(T: np.ndarray, T_true: np.ndarray) -> tuple[float, float]:
    err_t = float(np.linalg.norm(T[:3, 3] - T_true[:3, 3]))
    err_r = float(
        Rotation.from_matrix(T[:3, :3] @ T_true[:3, :3].T).magnitude() * 180.0 / np.pi
    )
    return err_t, err_r


def _seed(frame_idx: int) -> None:
    o3d.utility.random.seed(frame_idx)
    np.random.seed(frame_idx)
    random.seed(frame_idx)


def _eval_one(i: int) -> dict:
    """Worker: one section, one attempt. Returns a flat, JSON-able dict."""
    from dimos.mapping.relocalization.relocalize import relocalize

    s = _SECTIONS[i]
    _seed(s.frame_idx)
    gm, lm = _premap_cloud(), _to_cloud(s.body_pts)

    t0 = time.perf_counter()
    try:
        T, fitness = relocalize(gm, lm)
    except Exception as e:  # full accounting: crashes are results, not gaps
        return {"frame_idx": s.frame_idx, "status": "crashed", "error": repr(e),
                "dt": time.perf_counter() - t0}
    dt = time.perf_counter() - t0

    err_t, err_r = _errors(np.asarray(T), s.T_true)
    return {
        "frame_idx": s.frame_idx, "status": "ok", "err_t": err_t, "err_r": err_r,
        "fitness": float(fitness), "source": "ransac", "dt": dt,
        "n_pts": int(len(s.body_pts)), "reached_gate": bool(s.reached_gate),
        "success": bool(err_t < SUCCESS_T_M and err_r < SUCCESS_R_DEG),
        "accepted_at_gate": bool(fitness >= FITNESS_GATE),
        "T_est": np.asarray(T).tolist(),  # scoring needs the pose itself
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("recording")
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) - 2))
    a = ap.parse_args()

    global _PREMAP_PTS, _SECTIONS
    with open(HARNESS / "out" / "prepared" / f"{a.recording}.pkl", "rb") as f:
        prep_d = pickle.load(f)
    from types import SimpleNamespace
    prep = SimpleNamespace(**prep_d)
    _PREMAP_PTS = prep.premap_pts
    _SECTIONS = sorted((SimpleNamespace(**s) for s in prep.sections),
                       key=lambda s: s.frame_idx)

    print(f"bench: {a.recording} config=ransac sections={len(_SECTIONS)} "
          f"premap={len(_PREMAP_PTS)} pts workers={a.workers} "
          f"dimos={prep.git_rev_dimos} trial={prep.git_rev_trial} "
          f"seeds=frame_idx OMP=1", flush=True)

    t0 = time.perf_counter()
    with ProcessPoolExecutor(max_workers=a.workers) as pool:
        results = list(pool.map(_eval_one, range(len(_SECTIONS))))

    # Actual CODE rev executed (may differ from prep.git_rev_dimos, which is the
    # DATA rev baked into the pkl at prep time). Under --project the running
    # relocalize.py can be a different clone/branch than the sections were built on.
    import dimos.mapping.relocalization.relocalize as _relmod
    try:
        code_rev = subprocess.run(
            ["git", "-C", str(Path(_relmod.__file__).parent), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, OSError):
        code_rev = "unknown"

    wall = time.perf_counter() - t0
    ok = [r for r in results if r["status"] == "ok"]
    n_all = len(results)
    n_succ = sum(r.get("success", False) for r in ok)
    summary = {
        "recording": a.recording, "config": "ransac",
        "n_sections": n_all, "n_ok": len(ok),
        "n_crashed": sum(r["status"] == "crashed" for r in results),
        # FULL denominator: failures of any kind stay in.
        "success_rate_all": n_succ / n_all if n_all else float("nan"),
        "median_err_t_ok": float(np.median([r["err_t"] for r in ok])) if ok else None,
        "median_dt": float(np.median([r["dt"] for r in results])),
        "wall_seconds": wall,
        "truth": "PGO silver (~6 cm run-to-run floor, see WORKSPACE §7)",
        "rung": "replay (real recorded sensor data, offline)",
        "git_rev_dimos": prep.git_rev_dimos, "git_rev_dimos_code": code_rev,
        "git_rev_trial": prep.git_rev_trial,
        "command": " ".join(sys.argv), "seeds": "per-frame frame_idx; OMP_NUM_THREADS=1",
        "unix": time.time(),
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{a.recording}.ransac.json"
    with open(out, "w") as f:
        json.dump({"summary": summary, "results": results}, f, indent=1)
    print(json.dumps(summary, indent=2))
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

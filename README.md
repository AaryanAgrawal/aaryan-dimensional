# aaryan-dimensional

Aaryan's working repo for Dimensional — where all context for the work lives. It began as the
Forward Deployed Engineer trial, whose marker-localization benchmark instruments are in `trial/`.

```
aaryan-dimensional/         (this repo, root)
├── CLAUDE.md               how to work in this repo
├── WORKSPACE.md            state, plan, history — the living doc
├── linear-migration/       Engineering v1 → v2 handoff, snapshot, and review-site source
├── trial/harness/          the offline relocalization benchmark (premap-scored replay)
├── trial/results/figures/  tracked comparison figures (everything else in results/ is generated)
├── site/                   /dimensional trial-page source (canonical copy; deploys via portfolio)
├── office_markers.yaml     placeholder marker map — dimos' go2 blueprint resolves this bare name
└── dimos/                  ← cloned inside here, gitignored, its own git repo
```

Start with `CLAUDE.md` for how to work. Then `WORKSPACE.md` for state and plan — on a new
machine, begin at its §0 Cold start.

For the Engineering v2 Linear migration, start with
[`linear-migration/HANDOFF.md`](linear-migration/HANDOFF.md).

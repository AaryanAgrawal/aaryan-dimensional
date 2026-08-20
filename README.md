# aaryan-dimensional

Aaryan's working repo for Dimensional — where the context for the work lives. It began as the
Forward Deployed Engineer trial, which converted to a full-time role on 2026-08-07.

This repo tracks durable context only. The repos being worked on are cloned under `workspace/`,
which is gitignored in full along with every agent scratch dir and run output.

```
aaryan-dimensional/           (this repo, root)
├── CLAUDE.md                 how to work in this repo
├── AGENTS.md                 judgment rules for coding agents
├── WORKSPACE.md              state, plan, history — the living doc
├── G1_SETUP_GUIDE.md         Unitree G1: fresh unit to running dimos
├── G1_WIPE_AND_REINSTALL.md  Unitree G1: two wipe procedures, two very different risks
├── scripts/                  robot bringup and one-click setup
├── templates/                the Dimensional PRD template
├── dios/                     dios design docs + the script that renders them
├── learn/                    Q/A decks for spaced repetition, one per language
├── linear-migration/         Engineering v1 → v2 handoff, snapshot, review-site source
├── site/                     /dimensional page source (canonical copy; deploys via portfolio)
└── workspace/                ← clones (dimos, dios) and all scratch; gitignored
```

Start with `CLAUDE.md` for how to work. Then `WORKSPACE.md` for state and plan — on a new
machine, begin at its §0 Cold start, and §1 for where everything lives.

For the Engineering v2 Linear migration, start with
[`linear-migration/HANDOFF.md`](linear-migration/HANDOFF.md).

# Engineering v1 → Engineering v2 Linear migration

Last verified: **2026-08-17**

Workspace: **Dimensional**

Target team: **Engineering v2** (`END`, `b955509d-b31d-4c69-9ca7-66fe12035e5e`)

This is the cross-machine handoff. Read it before making another Linear change. The exact
initiative and project identifiers are in `LINEAR_SNAPSHOT.json`.

## Cold start on another machine

```bash
git clone https://github.com/AaryanAgrawal/aaryan-dimensional.git
cd aaryan-dimensional/linear-migration/site-source
npm ci
npm test
```

The Linear credential is deliberately not in this repository. Set `LINEAR_API_KEY` locally before
using the Linear API. The personal key pasted in the original chat should be rotated rather than
copied into Git.

## Operating model decided

```text
Initiative + evolving Brief
  └── Project + PRD in the Project description
        └── Milestone + target date + objective definition of done
              └── Issue + assignable execution task
```

- An **Initiative** is a durable product/capability direction. It is not expected to finish. It has
  one owner and an evolving Brief.
- A **Project** is one bounded user outcome. Its PRD lives directly in the Linear Project
  description. It ends when the outcome works or the Project is cancelled.
- A **Milestone** is a dated, testable checkpoint inside a Project.
- An **Issue** is an execution task inside a Milestone.
- Engineering work should always answer: which Project/PRD does this advance?
- Linear sub-initiatives are not part of this design. They require the Enterprise plan, and the
  eight-area flat structure is simpler.

### Project naming and continued development

- The Project name must reveal the specific system or user boundary. Broad categories such as
  `Runtime & Transport` and `Software OTA & Release` are not Project names.
- Same user outcome: keep the Project and add dated Milestones such as Internal Alpha, Robot
  Validation, Beta, and GA.
- New user outcome: create a new outcome-named Project. Prefer `Multi-Floor Navigation` over
  `2D Navigation v2`.
- Shipping batch: use a Linear Release.
- Use `v1`/`v2` only when the version itself is a compatibility, hardware-revision, or customer
  contract.

## Live Engineering v2 state

Eight active Initiatives are in place. All have no owner and no description. Assigning Initiative
owners is intentionally still open; no names were guessed.

| Initiative | State | Current migration Projects |
|---|---|---|
| Agents & Memory | Active | 3 `[Example]` Projects |
| Control | Active | 2 `[Example]` Projects |
| Hardware | Active | 3 `[Example]` Projects |
| Infrastructure | Active | `DIOS` only |
| Manipulation | Active | 4 `[Example]` Projects |
| Navigation | Active | 3 `[Example]` Projects |
| Perception | Active | 2 `[Example]` Projects |
| Web | Active | 2 `[Example]` Projects |

The 19 `[Example]` Projects are placeholders for review, not approved roadmap commitments. They
have Backlog status, no lead, no description/PRD, no Milestones, and no Issues.

`DIOS` is the one real Project. It is under Infrastructure, in Backlog, with the existing
`DIOS: DimOS BIOS` PRD copied into the Project description. The source document was:
https://linear.app/dimensional/document/dios-dimos-bios-prd-a28b2066e646

### Example Projects by Initiative

**Navigation**

- `[Example] Unattended 2D Navigation`
- `[Example] Stereo Visual Odometry Module`
- `[Example] Quadruped 3D Navigation`

**Manipulation**

- `[Example] Reliable Pick-and-Place`
- `[Example] Mobile Manipulation`
- `[Example] Manipulation Teleoperation & Dataset Capture`
- `[Example] ACT Manipulation Policy Deployment`

**Control**

- `[Example] Whole-Body Control Runtime`
- `[Example] RL Locomotion Policy Integration`

**Perception**

- `[Example] 3D Scene Reconstruction & Object Registration`
- `[Example] Multi-Camera Calibration`

**Agents & Memory**

- `[Example] Long-Horizon Agent Runtime`
- `[Example] Long-Horizon Agent Evaluation Suite`
- `[Example] Robot Spatial Memory`

**Hardware**

- `[Example] M20 Pro Integration`
- `[Example] Unitree Go2 Platform Integration`
- `[Example] Galaxea A1Z Platform Integration`

**Web**

- `[Example] Robot Operations Dashboard`
- `[Example] Robot Web Application SDK`

Infrastructure intentionally has no example Projects beyond the real `DIOS` Project.

### Pre-existing Engineering v2 Projects

These four Projects were already in Engineering v2 and were not created, moved, renamed, or
deleted during the migration work:

- `Basic Dashboard` — Backlog, linked to Web
- `Simulation` — Backlog, linked to Manipulation and Web
- `Hardware Integration` — Backlog, not linked to an Initiative
- `2D Navigation MVP` — Completed, linked to Navigation

They need a deliberate keep/merge/retire decision later. Do not silently treat them as part of the
new proposal.

### Initiative cleanup already performed

- Renamed: `Navigation Framework`, `Manipulation Framework`, `Control Framework`, `Perception
  Framework`, `Agent Framework`, and `Web Framework` to the shorter Initiative names above.
- Kept and reused: `Infrastructure` and `Hardware`.
- Set to Canceled: `Memory Framework` and `OEM Enablement` (not deleted).
- Left untouched: `Hackathon`, because it is unrelated to the Engineering v2 migration.
- Merged the intended memory direction into `Agents & Memory`.
- Did not change any Initiative descriptions.

## Engineering v1 source audit

The review artifact was built from the original Engineering team, including all Project counts,
Milestones, descriptions, and active unprojected Issue titles.

- 701 Issues total
- 384 active and 317 historical
- 442 attached to Projects
- 259 without a Project
- 207 active Issues without a Project

| Engineering v1 Project | Total Issues | Active Issues |
|---|---:|---:|
| Manipulation Framework | 212 | 59 |
| Control Framework | 58 | 22 |
| Agent Framework | 37 | 19 |
| Infrastructure | 22 | 6 |
| Hardware Integration | 22 | 14 |
| Launches | 21 | 11 |
| Web Framework | 18 | 14 |
| Perception Framework | 17 | 11 |
| Navigation Framework | 15 | 9 |
| Memory Framework | 11 | 10 |
| Nav — VSLAM V1 | 8 | 1 |
| Hardware Initiatives | 1 | 1 |
| OEM System | 0 | 0 |

The 207 active unprojected Issues were classified from titles as: Infrastructure 43, Navigation
39, needs manual review 32, Simulation 20, Hardware 20, Manipulation 13, Control 13, OEM/deployment
10, Web 8, Agents 3, Memory 3, and Perception 3.

No Engineering v1 Project or Issue has been moved, renamed, deleted, or reassigned. The source team
remains intact.

## Review artifact

Private live site:
https://dimensional-linear-migration.aaryanragrawal.chatgpt.site

The deployable application source in `site-source/` is based on Sites commit
`e348e782d10fab99e78abc5df22cf7601010050b`. The app/build/config files are preserved from that
commit; only `site-source/README.md` was rewritten to explain this cross-machine handoff, and the
Sites-local `.claude/qa.md` was intentionally excluded. Its deterministic checks passed when last
run:

- `npm run lint`
- `npx tsc --noEmit --incremental false`
- `npm test` (build plus 3/3 tests)

Important: the deployed artifact is a **proposal snapshot from before the Linear mutations**. It
still says `[tentative]`, proposes 23 Projects including four Infrastructure candidates, and says
`NO LINEAR CHANGES MADE`. The live Linear state now uses 19 `[Example]` placeholders plus the real
`DIOS` Project. Update the artifact before presenting it as current.

## Next actions

1. Assign one leader to each of the eight Initiatives.
2. Create a short engineer-facing Linear document explaining the operating model and what is
   expected from engineers. Screenshots can be added there later.
3. Review the 19 `[Example]` Projects with the relevant Initiative owner. For each approved
   outcome, remove `[Example]`, assign a Project lead, and write the PRD in the Project description.
4. Create Milestones only after the Project/PRD is approved in a meeting; then route active Issues
   underneath them without requiring the entire team to attend.
5. Resolve the four pre-existing Engineering v2 Projects explicitly.
6. Route the 207 active unprojected Engineering v1 Issues. Do not invent a Miscellaneous Project.
7. Update and republish the review artifact so its labels and Infrastructure section match Linear.

## Safety boundary

Only Engineering v2 structure was changed. No Engineering v1 work was changed. No Project or Issue
was deleted. Canceled Initiatives remain recoverable. Keep future mutations scoped to Engineering
v2 unless Aaryan explicitly expands the scope.

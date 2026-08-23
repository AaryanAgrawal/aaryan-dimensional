# aaryan-dimensional

Aaryan's working repo for Dimensional — where all context for the work lives. It began as the
Forward Deployed Engineer trial, whose marker-localization benchmark instruments are in `trial/`.

```
aaryan-dimensional/         (this repo, root)
├── CLAUDE.md               how to work in this repo
├── WORKSPACE.md            state, plan, history — the living doc
├── trial/harness/          the offline relocalization benchmark (premap-scored replay)
├── trial/results/figures/  tracked comparison figures (everything else in results/ is generated)
├── site/                   /dimensional trial-page source (canonical copy; deploys via portfolio)
├── office_markers.yaml     placeholder marker map — dimos' go2 blueprint resolves this bare name
└── dimos/                  ← cloned inside here, gitignored, its own git repo
```

Start with `CLAUDE.md` for how to work. Then `WORKSPACE.md` for state and plan — on a new
machine, begin at its §0 Cold start.

## Workstation setup

Run the same setup on macOS or Ubuntu:

```bash
./setup.sh
./setup.sh --check
```

The first command installs the terminal layer and the supported upstream Claude Code, Codex,
OpenCode, Hermes, and Diffity tools. The second command is read-only: it reports dependencies,
versions, auth checkpoints, Claude hooks/status line, shared skills, and the installed Dimensional
harness. Authentication stays separate for each tool; the script never copies credentials between
them.

Hermes's bundled Playwright browser is skipped because the harness routes browser work through
Chrome MCP or Kernel. This avoids a second Chromium install and keeps browser identity in the
selected provider instead of silently changing it.

Start normal laptop work with:

```bash
dimensional-ai code       # persistent primary lead in OpenCode
dimensional-ai lead-ops   # independent accountability and recovery lead
dimensional-ai team       # inspect both leads and pending messages
dimensional-ai hermes     # longer coordination, sessions, forks, and task board
dimensional-ai doctor     # verify the whole local integration
```

`dimensional-ai code` is the default surface. Hermes is the outer coordinator and durable task
surface; OpenCode is the interactive coding UI; Claude Code and Codex remain selectable runtimes
and review counterparts. Detailed commands and boundaries live in
`../AI Harness/dimensional-harness/docs/WORKFLOW_SWITCH.md`.

The information is intentionally split by ownership:

| Information | Location |
|---|---|
| Engineering truth | Git in the working repository and Dimensional Linear |
| Repository instructions and current work | `AGENTS.md`, `CLAUDE.md`, `WORKSPACE.md` |
| Durable specifications | `openspec/` in the working repository |
| Shared Claude hooks, status line, rules, and skills | `~/.claude/` |
| Portable agent skills used by Codex and OpenCode | `~/.agents/skills/` |
| Hermes conversations, projects, schedules, and task state | `~/.hermes/profiles/dimensional/` |
| OpenCode conversations and isolated credentials | `~/.hermes/profiles/dimensional/opencode/data/opencode/` |
| Rebuildable cited context index | `~/.hermes/profiles/dimensional/harness/context.db` |
| Persistent team aliases, messages, recovery lineage, and Claude handles | `~/.hermes/profiles/dimensional/harness/harness.db` |
| Harness source and install logic | `../AI Harness/dimensional-harness/` |

The context database is a derived search index, not a source of truth. Personal and SRCo harnesses
must use different profiles, databases, credentials, projects, and context indexes.

`dimensional-ai doctor` is the authoritative integration check. It verifies Hermes, OpenCode,
Claude/dtach, MCPs, the two-lead team, watchdog, workspace boundary, context index, and local server
without publishing or spending.

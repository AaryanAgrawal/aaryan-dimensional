# context

Work intent: what we are doing, on which branch, and why.

- `tickets/DIM-XXXX.md` — one file per Linear ticket: the Linear link, related tickets, the dimos
  branch and PR under test, our own work branch, then state and what blocks it. Written so the next
  person resumes the ticket cold from that file alone. Convention in `CLAUDE.md` § Ticket files.
- `G1-ESTOP.md` — the G1 fall / lowstate-loss e-stop: branch, what is verified, what is not,
  and the next actions. Not yet ticketed.
- `fiducial-relocalization-prd.md` + `fiducial-relocalization-architecture.md` — the paired product
  and technical docs, mirrored into Linear (project in Engineering v2, PRD doc in Engineering v1).
  Edit these, then push the change to both Linear copies; the markdown is the source of truth.
- `DIOS-ENV-TRAPS.md` — environment and toolchain failures hit on real hardware, for DIOS to
  replicate and check for. Append only.

How to work is `CLAUDE.md`; state, plan and history is `WORKSPACE.md`.

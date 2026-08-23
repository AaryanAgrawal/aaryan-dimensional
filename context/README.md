# context

Work intent: what we are doing, on which branch, and why.

- `tickets/DIM-XXXX.md` — one file per Linear ticket: the Linear link, related tickets, the dimos
  branch and PR under test, our own work branch, then state and what blocks it. Written so the next
  person resumes the ticket cold from that file alone. Convention in `CLAUDE.md` § Ticket files.
- `G1-ESTOP.md` — the G1 fall / lowstate-loss e-stop: branch, what is verified, what is not,
  and the next actions. Not yet ticketed.
- `G1-ESTOP-PRD.md` / `G1-ESTOP-TECHSPEC.md` — the e-stop PRD (with the fall demo graph)
  and the tech spec for the kill path via `ControlCoordinator`.
- `DIOS-ENV-TRAPS.md` — environment and toolchain failures hit on real hardware, for DIOS to
  replicate and check for. Append only.

How to work is `CLAUDE.md`; state, plan and history is `WORKSPACE.md`.

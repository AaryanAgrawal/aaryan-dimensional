# DIOS v1 review — dispositions

Every reviewer comment on the v1 PRD and what v2 does about it. 29 reviewer comments: 22 on the
Linear document, 7 from Jeff on the Linear project. Aaryan's own 17 replies are not listed.

Sources: [PRD document](https://linear.app/dimensional/document/dios-dimos-bios-prd-a28b2066e646),
[DIOS project](https://linear.app/dimensional/project/dios-dimos-bios-6ca9b1a7b558),
[DIM-1415](https://linear.app/dimensional/issue/DIM-1415),
[DIM-1426](https://linear.app/dimensional/issue/DIM-1426).

Draft replies are for Aaryan to send in his own words. Nothing here has been posted.

## Accepted, v2 changed

| Who | Comment | v2 |
|---|---|---|
| Paul, Ivan | "How is an installer a BIOS?" and "strong agree, don't call this BIOS" | Name dropped. The product is the DimOS installer, the command is `dimos`. |
| Paul, Ivan | "people hate fancy terms for commands", on `seed` | `setup`. `seed` and `infect` are gone. |
| Stash | `infect` "sounds like malware" | Gone. |
| Paul | "Wouldn't it make more sense for it to be part of the dimos codebase?" | Yes, and that is the whole of v2. It also deletes the duplicate bash installer, which v1 did not notice existed. |
| Paul | "Why?", on closed source, asked twice | Apache-2.0 in the DimOS repository. |
| Paul, Ivan | Robot-by-name and reconnect-after-move "should be a different PRD", "we are working on this actively now" | Both user stories removed, and the PRD points at Zenoh autodiscovery. |
| Jeff | "this isn't a measurement" | Success metrics rewritten so every target is a test output. |
| Jeff | "declare it in the header following the pypi standard" | `info.yaml` dropped for the 21 extras already in `pyproject.toml`. Only system packages get a table. Closes DIM-1426. |
| Paul | "talk to at least Jeff to see what worked" | v2 adopts Jeff's binary as the implementation instead of designing a second one. |
| Paul | "You mean there's a PR for it (or code in some other repo)?" | `dimensionalOS/dios`, v0.3.97. Named in the PRD. |
| Jeff | "fluff, remove" | Removed. |
| Jeff | "what step? I don't know what tailscale has to do with dios" | Cut to one line under non-goals. |
| Paul | "What's the advantage of it being compiled?" | It runs before anything is installed, so it cannot depend on the machine's libc or Python. |
| Stash | "How is this installed? what's the install command?" | Curl command is the first thing in the solution. |
| Stash | "why not `dimos doctor`?" | It is `dimos doctor` now. |
| Jetson Wu | "Where is this guide?" | `G1_SETUP_GUIDE.md`, cited in the problem. Folding it in is the point. |
| Aaryan | "Issues need to be made" | Blocked on the PRD landing. |

## Accepted, shape changed

| Who | Comment | v2 |
|---|---|---|
| Paul | "I'd much rather have `dios update` automatically fix it and not have `dios doctor` at all" | `doctor` stays as the read-only report, and `setup` is idempotent and repairs, so nothing is diagnosed without being fixable. |
| Paul | "Are we trying to solve install for us or for anyone?" | Both, split explicitly. The supported matrix is what we guarantee, everything else prints steps rather than failing, and no system package is installed without asking. |
| Jeff | "Probably want per platform (g1, go2, spot) setup wizard (compiled to standalone tool)" | Per-platform setup paths in one binary. A binary per robot needs a release pipeline per robot first. |
| Jeff | "'resolves when?' matters a lot. Auto-pulled dependencies at blueprint time should be out of scope" | Resolution happens at setup from the selected extras, and nothing is pulled at blueprint time. |
| Jeff | "how? I think only a wizard can", on resolving the dependency set | Setup resolves it from `pyproject.toml` extras plus the system-package table. |

## Rejected

| Who | Comment | Why not |
|---|---|---|
| Paul | "I don't think setup scripts should be in compiled languages. They are often bash scripts which people can inspect" | Bash cannot produce one artifact that runs before Python exists on an unknown glibc, which is the Jetson case. The inspectability concern is answered differently: the installer is Apache-2.0 in the same repository and `--dry-run` prints every command before it runs. Paul noted he is in the minority and that Ivan also wants Rust. |

## Still open, needs the reviewer

- **Ivan.** Is scanning the LAN for a Go2 the way the Unitree app does part of the Zenoh
  autodiscovery work, or separate and simpler? v2 assumes separate and keeps only the install-time
  scan.
- **Jetson Wu.** "There's supposedly a doc for coding agent to follow to integrate a new robot, but
  I am not sure how robust it is." Which doc, and does it survive the move?
- **Stash.** DIM-1333 is reopened for hardware verification and he wants the installer run while the
  robots are out. That is the G1 bring-up metric, and it needs a date.

## Draft replies

Short, one or two sentences, for Aaryan to send.

**Paul, on closed source:** Dropping it. The installer moves into the dimos repo under Apache-2.0,
and the isolation I wanted comes from static linking and a separate artifact instead.

**Paul, on it being part of the dimos codebase:** Agreed, that is the change. v2 puts the installer
in the dimos repo and deletes `scripts/install.sh`, which I had not clocked was a second installer.

**Paul, on compiled:** It has to run before Python or a package manager exists, on Jetson images
whose glibc we do not control, so it is a static musl binary. Recording your disagreement in the
doc rather than burying it.

**Paul, on robot by name:** Cut both stories. Install-time scan stays, runtime identity goes to
Ivan's autodiscovery work.

**Paul, on doctor:** Keeping it as the read-only report, and making `setup` idempotent so anything
it finds is fixable by re-running.

**Ivan, on autodiscovery:** Is the LAN scan for a Go2, the way the Unitree app does it, part of what
you are building, or separate? v2 assumes separate and only uses it at install time.

**Jeff, on measurement:** Rewrote the metrics table so every row is a number a test produces.

**Jeff, on pypi standard:** Dropped `info.yaml`. Python deps come from the extras already in
`pyproject.toml`, and only system packages get a table.

**Stash, on the install command:** `curl -fsSL https://dimensionalos.com/install.sh | bash`, then
`dimos setup`.

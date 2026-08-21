# dios — PRD

Version of record for Linear DIM-1415. The shape of the tool is in
[ARCHITECTURE.md](../ARCHITECTURE.md); this says what we are building and how we know it works.

## Problem

Setting up DimOS is manual and different on every robot and board. The knowledge lives in setup
guides and in people's heads. Every new robot repeats the work.

## Solution

One static binary, two capabilities.

**Package manager.** Given a machine, install DimOS correctly for its platform.
**Provisioner.** Given a robot, identify it, reach it, install what it requires, leave it
configured to run.

Principles:

1. The package manager knows platforms; the provisioner knows robots. Neither crosses over.
2. The package manager works standalone.
3. Every step states what proves it succeeded. A proven step is skipped, so a re-run resumes.
4. Degrade rather than fail. An unsupported platform gets instructions.

## Recipes

A recipe is data: how to recognise one robot, reach it, and configure it. Anyone can author and
share one without modifying the tool. A recipe declares the permissions it needs, so an operator
can review it before trusting it.

This version adds the index: one static JSON file that maps a recipe name to a pinned git revision
and a hash. `dios recipe add unitree-g1` installs by name, and adding a board is a PR against the
index, never against dios. The index URL is configurable, which is also how a mirror or a company
index works. Shape and rules: ARCHITECTURE.md §13.

## Interface

As the binary stands (`dios --help`):

- `dios setup` — full install on this machine
- `dios doctor` — diagnostics; `--recipe <name>|all` checks recipe files with no robot present
- `dios update` · `service` · `restart` · `log` · `config` · `uninstall` — care and feeding
- `dios webserver` · `install` · `desktop` — management server and desktop packages
- `dios infect` — set up a robot; `--with <recipe>` skips the match step
- `dios infect scan` — find candidates on ethernet, usb, wifi and bluetooth
- `dios infect check` — per step, judged live: holds, would run, or done; applies nothing
- `dios infect bringup` — reach a fresh robot over the cable
- `dios recipe new|list|show|test|add|remove|search|update` — work with recipes, no robot needed
- `dios verb list|run` — one operation against one machine

New this version, from the index work: `recipe add <name>` (index-resolved, rev-pinned,
hash-checked), `recipe search`, `recipe update`, and `dios config set recipes.index <url>` for a
mirror or a company index. `recipe add <git-url>` stays as the escape hatch.

Modes: interactive, unattended (`--non-interactive`), agent (`--agent` never prompts; a critical
failure exits 2 with a JSON block saying what a human has to decide).

## Status

Two claims, kept separate.

**The install is verified.** On a real G1 (2026-08-10): one command, unattended, exit 0. A re-run
changed nothing.

**A blueprint run after that install is not yet proven.** Five failures followed the green exit,
none of them a dios bug: static TLS exhaustion on glibc 2.31, dimos calling a driver API no
published `unitree-webrtc-connect` has, the robot address written as the string `"none"`, a GUI
viewer opened on a headless robot, and a multicast prompt that could not persist. The install
claimed success anyway because the smoke test never ran on a headless machine. That is fixed: the
smoke test is now the provisioner's own final stage, run headless after post-helm and `[config]` —
any earlier proves a half-built machine. It has not run on hardware yet because the robot has been
offline. Full catalogue: ARCHITECTURE.md §12.

## Success criteria

- A fresh robot reaches running DimOS in one command, and the run proves it by running a blueprint.
- A re-run changes nothing.
- A new robot needs no change to the tool: a recipe and an index entry.

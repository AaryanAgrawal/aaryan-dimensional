# Integration notes — cross-branch items found while the build ran

Three items that are nobody's bug on their own branch and become real on merge. Found by the
authoring agent on a read-only look at the dirty tree, verified here.

---

## 1. `Step` cannot reject unknown fields, so recipe typos are silent

`src/infect/recipe/manifest.rs` — `Step` is the only struct in that file without
`#[serde(deny_unknown_fields)]`. Eight of its neighbours have it. `Step` cannot, because it uses
`#[serde(flatten)]` for the action and serde forbids the two together.

Consequence: **any misspelled step field parses silently.** `critcal = true` yields `false`. For a
field that means "stop the run if this fails", silently-false is the dangerous direction — a
load-bearing step fails, the run continues, the robot is half-provisioned, and the exit code says
it worked.

**Action:** `dios doctor --recipe` must check for unknown step keys, because serde structurally
cannot. It is the only place this can be caught. Add a test with a typo'd field asserting a
finding. This is the highest-value item in this file.

---

## 2. `critical` is undocumented

The modes branch added `Step.critical: bool` (`#[serde(default)]`, so false) plus
`Step::criticality()`. `recipes/g1/recipe.toml` sets it on two steps.

`docs/recipes.md`'s `[[step]]` table lists id / phase / on / enabled / verb+args / script+timeout_s
/ verify — and nothing else. So the field exists, is used by a shipped recipe, and no author reading
the guide would know to set it. Everything then defaults non-critical, which is the wrong default
for a step someone chose to make load-bearing.

**Action after merge:** add the row next to `enabled`, with the sentence the code's own doc comment
already makes — *failure stops the run, off by default, because only the recipe's author knows which
steps are load-bearing.* And stub it as one commented line in `src/infect/recipe/scaffold.rs`
beside `enabled`: a field an author never sees is a field an author never sets.

The authoring agent deliberately did not write this row. It could not run the field and documenting
semantics you have only read is the hypothesis-as-fact trap. Correct call.

---

## 3. The guide references a command from another branch

`docs/recipes.md` and `docs/recipes-checklist.md` tell authors to run
`dios doctor --recipe <name>`. That command exists only in the `dios/3-recipe-doctor` worktree.

**Action after merge:** run `dios recipe new <name>` then `dios doctor --recipe <name>` once, and
confirm clean. If the doctor flags a fresh scaffold — say, for having no probes — that is a
**scaffold fix, not a doctor fix**. A scaffold that fails its own validator on creation teaches the
wrong thing on day one.

---

## Working-tree hazard (resolved, but worth the rule)

Two agents wrote into `workspace/dimos-bios` at once. `dios/3-recipe-doctor` had its own worktree;
the modes agent did not, so it edited the same checkout while `dios/4-authoring` was checked out.
One `git commit -a` would have swept 1865 lines of modes work onto the wrong branch.

The uncommitted modes work is backed up at
`~/.claude/jobs/b7fe7ae4/tmp/modes-backup/` — `modes-tracked.patch` plus copies of
`src/util/{ask,mode,stage}.rs` and `tests/prompts.rs`. The tree was not disturbed.

**Rule going forward: one worktree per agent in this repo.** The two-repo split used to make this
impossible; merging into one traded a cross-repo contract boundary for a shared-checkout hazard.
The failure mode moved rather than disappearing.

---

## 4. The three-way merge: conflicts are mechanical, resolution is "keep both"

Trial-merged `dios/{2-modes,3-recipe-doctor,4-authoring}` onto `dios/1-merge` in a throwaway
worktree. Result:

```
dios/2-modes            clean
dios/3-recipe-doctor    CONFLICT  CHANGELOG.md · src/cli.rs
dios/4-authoring        CONFLICT  CHANGELOG.md
```

Neither is a semantic conflict. Both are two branches appending to the same list.

**`src/cli.rs`** — both edited the same help-text block. modes added the `--agent doctor` line;
recipe-doctor added two `--recipe` lines and re-padded the column alignment. Resolution: take
recipe-doctor's padding and keep all four lines:

```
dios doctor                        # full system check
dios doctor --json                 # one JSON line for another tool to read
dios doctor --recipe unitree-g1    # check one recipe, no robot needed
dios doctor --recipe all           # every recipe in --recipes
dios --agent doctor                # escalate blockers instead of reporting them
```

**`CHANGELOG.md`** — each branch wrote its own `## Unreleased — dios/N-name` section at the top.
Keep all three sections, or fold them into one `## Unreleased` with the three sub-headings. Do not
drop any.

After resolving, the doc cross-checks from items 2 and 3 above become runnable:
`dios recipe new x && dios doctor --recipe x` must be clean, and `docs/recipes.md` gains the
`critical` row.

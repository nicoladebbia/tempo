---
description: Fix one round from an /audit — decisions up front, a worktree (and lanes) with their own simulators, tests + sim check per fix, PRs.
---

# /round — fix one audit round

Arguments: `$ARGUMENTS` = `<area> <round>` (e.g. `training 2`). Find the plan in the area's latest audit memory (`<area>-audit-*.md`) and its report link. If there is no audit, say so and suggest `/audit <area>`.

## 1. Decisions first (one batch)

Read the round's items. Collect **every** product decision that changes the result (behaviour users see, data rules, what happens on edge cases) and ask them all in one AskUserQuestion batch, each with a recommended option. Also ask:

- **Delivery**: one PR for the round, or **part by part** (a PR per part, then STOP so Nicola can test on his iPhone).
- **Lanes**: parallel lanes (faster; only if the audit's lane split has no shared existing files) or one lane.

Things with an obvious default: decide them yourself and list them under "Defaults (not asked)" in memory and in the PR.

## 2. Set up

- Base branch `fix/<area>-round<n>` off a fresh `origin/main`, in a sibling worktree: `git worktree add -b fix/<area>-round<n> ~/dev/tempo-<area>-r<n> origin/main`.
- Lanes (if chosen): one branch per lane off the base branch, one worktree each (`~/dev/tempo-<area>-r<n>-<lane>`). Split by files: two lanes must never edit the same existing file. Shared models/services go to ONE lane.
- Every worktree builds and tests through `scripts/sim.sh` — that alone gives it its own simulator and DerivedData. Never `name=iPhone 17`.
- Write the round memory now (`<area>-round<n>-<date>.md`): branches, worktrees, decisions, defaults, parts/lanes. Update it as status changes.

## 3. Fix

Lanes run as parallel subagents (one message), each told: its worktree path (absolute — it must `cd` there for every command), its items, the decisions, the files it owns, and these rules. Work in item order. For **each** fix:

1. Write or update a test that fails before the fix.
2. Fix it. Keep changes minimal and in the surrounding style.
3. `scripts/sim.sh test` (narrow with `-only-testing:` while iterating, full TempoTests before the commit).
4. Check it in the app when it's visible there (`run-tempo` skill: `scripts/sim.sh qa`, AXe, screenshot).
5. Commit (Conventional Commits, e.g. `fix(training): best set is one real set`).

Out-of-scope bugs found on the way: don't fix; note them under "Follow-ups" in memory.

## 4. Merge and check

- Merge lanes into the base branch one at a time; resolve conflicts keeping both intents.
- In the base worktree: `xcodegen generate` if files were added, then full `scripts/sim.sh test`.
- **Shared-model check** (CLAUDE.md): enumerate the readers of every shared model/service the round touched; verify each. 2+ modules touched → `architecture-guard`.
- `code-reviewer` on the base branch diff vs `origin/main`; fix what it finds. Views changed → `design-system-police`.
- One end-to-end sim pass of the round's main flows.

## 5. Deliver

- Push and open the PR with `gh` (part by part: one PR per part, then STOP and wait for Nicola's on-device test before the next part). The PR lists: what changed, decisions, defaults, tests, sim-verified vs unverified, follow-ups.
- Remove lane worktrees once merged into the base branch: `scripts/sim.sh --dir <lane> clean && git worktree remove <lane>`. Keep the base worktree until the PR merges.
- Update the round memory: PR number, test counts, what's verified (sim) and what's not (device).

## 6. Final summary

Global format, plus the blast radius: "Changed X. Readers: […]. Verified: […]. Unverified: […]." "What you need to do": test on the iPhone (⌘R from the PR branch), then merge.

---
description: Read-only audit of one area (e.g. Training, Nutrition) — every function rated, bugs, root causes, fix rounds; publishes a report. Changes nothing.
---

# /audit — area audit

Area: `$ARGUMENTS` (e.g. `training`, `nutrition`, `dashboard`). If empty, ask which area.

This is **read-only**. Do not edit code, create branches or open PRs. The output is a report and a proposed order of fix rounds; Nicola picks a round and runs `/round`.

## 1. Pin the commit

`git fetch origin` and audit `origin/main` (note the short SHA in the report). If the current worktree is not on it, read files with `git show origin/main:<path>` or audit from a clean worktree.

## 2. Split into groups

Map the area's user-facing functions into 5–7 groups (e.g. Training: live workout · plan & program · progress & PRs · trainer import · Health & Watch · cardio). Each group must be readable by one agent.

## 3. Fan out (parallel, one message)

One agent per group (`general-purpose`, or `Explore` for pure lookup). Each agent gets the group's scope and returns, for **every** function in it:

- what the user can do, and where (screen → entry point, `file:line`)
- status: **works** / **partial** / **code-only** (exists but unreachable from the UI) / **broken**
- bugs with severity (high = wrong data shown/saved, data loss, crash; medium; low), each with `file:line` and a concrete failure scenario
- missing functions a picky user would expect, and short ideas

Tell agents: verify by reading the code path end to end (UI → view model → service → persistence); no speculation; check the readers of any shared model (see "Shared-model changes" in CLAUDE.md).

## 4. Verify and synthesize

- Re-check every **high** severity bug yourself (or with a verifier agent) before it goes in the report. Drop what doesn't hold.
- Find the **root causes** that explain many bugs at once (e.g. "no shared Today state", "Dashboard runs its own view model"). These drive the rounds.
- Tally: functions total, works / partial / code-only / broken, high-severity bugs.

## 5. Propose fix rounds

Order rounds so each makes the next safe — usually:

1. **Wrong data** (numbers, units, saves, deletes — what users would distrust)
2. **Single source of truth** (screens that disagree)
3. Behaviour / logic improvements
4. Navigation and discoverability
5. Coverage gaps
6. New features

For each round: goal in one line, the items it fixes, the files it touches, a suggested split into **lanes** (groups of items that don't edit the same existing files, so they can run in parallel worktrees), and the product decisions Nicola will need to make.

## 6. Publish and remember

- Publish the report as an Artifact (load `artifact-design` first): tally, root causes, per-group tables, rounds. Give Nicola the link.
- Save a project memory `<area>-audit-<date>.md`: commit audited, tally, root causes, the rounds, the report link, "not started — wait for Nicola to pick a round". Add it to `MEMORY.md`.

## 7. Final summary

Global format. "What you need to do": pick a round (`/round <area> <n>`).

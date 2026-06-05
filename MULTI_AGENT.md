# Running Multiple AI Agents in Parallel

How to run several agents (Claude Code or otherwise) on this repo at the same
time **without** them colliding. The hard rule that prevents every problem:

> **One agent = one git worktree = one branch = one PR. Never two agents in the
> same working directory.**

The thing that isolates agents is the **working directory**, not the branch.
Five agents sharing one directory will hijack each other's branch, tangle
stashes, and break each other's builds — even if they each have their own
branch. Five separate directories fixes all of it.

---

## What a PR is (plain words)

`main` is the official, real version of the app. You don't edit it directly.
A **Pull Request (PR)** is a "please add my changes to the official version"
request: it shows exactly what changed, lets you review + run tests, and
**nothing goes live until you click Merge**. Each agent opens its own PR; you
review and merge them one at a time.

---

## Setup — before launching any agent

From the repo root, start clean and create one worktree per agent:

```bash
cd ~/Projects/tempo
git checkout main && git pull

git worktree add ../tempo-agent1 -b feature/agent1-<thing>
git worktree add ../tempo-agent2 -b feature/agent2-<thing>
git worktree add ../tempo-agent3 -b feature/agent3-<thing>
git worktree add ../tempo-agent4 -b feature/agent4-<thing>
git worktree add ../tempo-agent5 -b feature/agent5-<thing>
```

You now have five real directories (`../tempo-agent1` … `../tempo-agent5`),
each with its **own HEAD**, all sharing one `.git`. Launch each agent **inside
its own directory**.

### The rule to give every agent

> "You work **only** in this directory. Never `git checkout` another branch.
> Never `cd` out of here. Commit here, push your branch, open your PR."

That single rule kills every collision: no branch-hijacking, no stash tangles,
no "another agent's broken file breaks my build."

---

## Assign lanes (minimize overlap up front)

The cheapest conflict is the one that never happens. Tempo's 5 modules map
almost perfectly onto 5 agents — give each agent a lane:

| Agent | Lane (module) | Primary directories |
|-------|---------------|---------------------|
| 1 | Dashboard (LifeOS) | `Views/Dashboard`, `ViewModels/Dashboard*` |
| 2 | Training (RepForge) | `Views/Training`, `Services/Training*` |
| 3 | Accountability (Lockdown) | `Views/Accountability`, accountability services |
| 4 | Recovery (RecoverIQ) | `Views/Recovery`, Whoop services |
| 5 | Nutrition / Arena | `Views/Nutrition`, `Services/Nutrition` |

**Shared files (models, services two agents both read) need ONE owner.** Don't
let two agents edit `UserSettings.swift` in parallel — designate one owner; the
other waits for that PR to merge, then rebases on top.

---

## While agents work

- Each agent commits in its own worktree and pushes its own branch:
  ```bash
  git -C ../tempo-agent1 add <specific files>   # NOT git add -A
  git -C ../tempo-agent1 commit -m "..."
  git -C ../tempo-agent1 push -u origin feature/agent1-<thing>
  ```
- Open a PR per branch (`gh pr create --base main --head feature/agent1-<thing>`).
- **Never `git add -A` / `git add .`** — it sweeps in files that aren't yours.
  Stage explicit paths only.

---

## Merging — one at a time, in sequence (CRITICAL)

Do **not** merge all five PRs at once. Merge one, sync main, then the next.

```bash
# 1. Merge the safest/smallest PR first
gh pr merge <PR#> --squash --delete-branch

# 2. Bring main up to date locally
git checkout main && git pull

# 3. If that PR added a file, regenerate the Xcode project from project.yml
cd Tempo && xcodegen generate && cd ..
git add Tempo/Tempo.xcodeproj/project.pbxproj
git commit -m "chore: regenerate project after merge"

# 4. Rebase the NEXT agent's branch on the new main BEFORE merging it
git -C ../tempo-agent2 rebase main
#    -> resolve any conflicts in that agent's worktree (isolated), then push:
git -C ../tempo-agent2 push --force-with-lease

# 5. Repeat from step 1 for the next PR
```

Merging sequentially + rebasing-before-merge surfaces conflicts in each
agent's **own** worktree (isolated), instead of as a five-way pileup in `main`.

---

## The pbxproj conflict (happens every multi-agent iOS run)

`Tempo.xcodeproj/project.pbxproj` is **generated** from `project.yml`. Every
agent that adds a file regenerates it, so every PR after the first conflicts
there.

**Never hand-resolve a pbxproj conflict.** Regenerate it:

```bash
cd Tempo && xcodegen generate && cd ..
git add Tempo/Tempo.xcodeproj/project.pbxproj
```

`project.yml` is the source of truth (globs the whole `Tempo/` tree, so new
files are picked up automatically). This is why XcodeGen is a big advantage for
parallel work — pbxproj conflicts become a one-command regen, not manual merge
hell.

---

## When conflicts happen anyway

Three cases, by how much they hurt:

1. **Same file, different spots** → git auto-merges at PR time. Free. (Most overlaps.)
2. **Same lines** → real conflict; resolve once, in the second PR to merge.
   Cheap if you merge sequentially.
3. **pbxproj** → never manual; regenerate (above).

---

## Cleanup — after an agent's PR merges

```bash
git worktree remove ../tempo-agent1
git branch -d feature/agent1-<thing>     # local branch (remote deleted by --delete-branch)
```

List active worktrees anytime:
```bash
git worktree list
```

---

## The 60-second checklist

1. `git checkout main && git pull`
2. `git worktree add ../tempo-agentN -b feature/...` per agent
3. Launch each agent in its own directory; tell it "stay here, never switch branches"
4. Assign one module-lane per agent; designate one owner per shared file
5. Each agent: explicit `git add <paths>` → commit → push → open PR
6. Merge PRs **one at a time**: merge → pull main → regen pbxproj → rebase next branch → repeat
7. `git worktree remove` each worktree as its PR lands

---

## What went wrong the time we didn't do this (2026-06-05)

Five agents shared **one** working tree. A parallel agent ran `git checkout`
mid-task and moved the shared HEAD out from under another agent (twice).
Stashes tangled, a broken file from one agent failed everyone's build, and a
test got committed referencing code that lived on a different branch. Recovery
required moving work into an isolated `git worktree` after the fact. Worktrees
from the start would have prevented all of it.

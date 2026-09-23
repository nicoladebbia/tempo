---
description: Run several Claude sessions on Tempo at once (one git worktree per module) and merge them back safely with scripts/parallel.sh.
---

# Parallel Claude Sessions — One Terminal Per Worktree

Nicola runs several `claude` sessions at once, each in its own terminal, working on Tempo simultaneously ("you do Recovery, you do Arena, you do Training"). **The hard rule that makes this safe: each terminal must be in a SEPARATE git worktree — never multiple sessions in the same directory.** Two `claude` sessions in the same `~/dev/tempo` are independent processes editing the same files on disk; the second write silently clobbers the first with no conflict. Git cannot fix that. Separate worktrees physically isolate the files. (Tool-agnostic version: `MULTI_AGENT.md`.)

**Layout (sibling worktrees, each its own branch off `main`):**
```
~/dev/tempo/            ← MAIN repo. Merge here. Do NOT run parallel sessions in this dir.
~/dev/tempo-recovery/   ← terminal 1, branch `recovery`
~/dev/tempo-arena/      ← terminal 2, branch `arena`
~/dev/tempo-training/   ← terminal 3, branch `training`
```

**The helper script is `scripts/parallel.sh`** (run from the main repo):
- `./scripts/parallel.sh new recovery arena training` — creates one worktree+branch per name, opens a Terminal tab in each.
- `./scripts/parallel.sh list` — show active worktrees and their branch state.
- `./scripts/parallel.sh merge` — merge every worktree branch back onto `main` one at a time, then remove the worktrees+branches.

**Scope rule — assign by MODULE.** The 5 modules (see CLAUDE.md) are the natural boundaries: one session per module. Two sessions editing the same existing `.swift` file is the only real merge-conflict source; module scoping prevents it. Adding NEW files is conflict-free — `project.yml` is glob-sourced (`path: Tempo`), so XcodeGen auto-discovers new files and no session touches the project file.

**Build model: build-once-after-merge.** Parallel sessions EDIT and commit on their branch; they do not need to build. The single authoritative `/build` happens on `main` after all branches merge. Swift 6 strict-concurrency breakage surfaces there, not per-session — that's the accepted tradeoff.

**Two traps the merge step must handle:**
1. **Same-file conflict** = two sessions edited the same existing file. `parallel.sh merge` stops at it; resolve by hand (both intents matter), `git add`, `git commit`. A nasty conflict means the scope split was wrong — note it for next time.
2. **Shared-model desync (see "Shared-model changes" in CLAUDE.md).** A clean merge with ZERO Git conflicts can still be wrong: if two sessions edited different files that both read the same `@Observable` service or SwiftData entity, it compiles, merges clean, and two screens show different numbers. After merge, run the enumerate-the-readers check on any shared model any session touched. **No Git conflict ≠ semantically safe.**

What worktrees do NOT fix: same-line edits still conflict at merge — but that's now an explicit, resolvable conflict instead of a silent overwrite. The fix for conflicts is better scope assignment, not Git config.

If arguments were given (`$ARGUMENTS`, e.g. `new recovery arena` / `list` / `merge`), run `./scripts/parallel.sh $ARGUMENTS` from the main repo and report the result; for `merge`, then do the shared-model reader check above.

# Archived Claude tooling

The original build-plan tooling. `docs/BUILD_PROGRESS.md` reached 124/124 steps, so these no longer load as commands, agents or hooks. Kept for reference.

- `build.md`, `build-step.md`, `build-status.md`: the `/build`, `/build-step` and `/build-status` commands.
- `build-reviewer.md`: the per-step doc-compliance reviewer agent.
- `stop-guard.sh`: a Stop hook that blocked stopping while a step was marked 🔨.

They were replaced by `/audit` and `/round` (`.claude/commands/`). To restore one, move it back to its folder. For the hook, also re-add it to `.claude/settings.json`.

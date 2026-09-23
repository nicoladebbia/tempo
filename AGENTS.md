# AGENTS.md

This is the standard instruction file for AI coding agents (Codex, Cursor, Gemini CLI, etc.).
The single source of truth for this project is **[CLAUDE.md](./CLAUDE.md)**. Read it first and follow it exactly.

Also available in this repo:
- `.claude/agents/`: specialized subagent definitions (reviewers, testers, builders)
- `.claude/rules/` and `.claude/commands/`, if present: extra rules and workflows

Working agreement (same as for Claude):
- Ask all clarifying questions up front if the request is ambiguous, then work without progress chatter.
- Verify before claiming done: run tests, typecheck and lint, run the app, and self-review the diff.
- Finish with a plain-language summary: what was done, what's still missing, and what the human needs to do.

#!/bin/bash
# Pre-Bash Guard — PreToolUse on Bash.
# 1. Blocks root/home wipes and disk formatting (exit 2 + stderr).
# 2. Checks git commit subjects follow Conventional Commits; a mismatch goes to
#    Claude as additionalContext (non-blocking).

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# Dangerous commands. `format` is anchored as a command word so swiftformat /
# clang-format are not caught; rm only when the target is / or ~ / $HOME itself.
if printf '%s' "$COMMAND" | /usr/bin/grep -qE 'rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*("?(/|~|\$HOME)/?\*?"?)([[:space:];&|]|$)|(^|[;&|])[[:space:]]*format[[:space:]]|mkfs'; then
    echo "BLOCKED: dangerous command (wipes / or ~, or formats a disk)." >&2
    exit 2
fi

# Commit-message convention: type(scope)?: subject
case "$COMMAND" in
    *git*commit*)
        HOOK_CMD="$COMMAND" python3 - <<'PY'
import json, os, re
cmd = os.environ.get("HOOK_CMD", "")
if not re.search(r"\bgit\b[^;&|]*\scommit\b", cmd):
    raise SystemExit(0)
m = re.search(r"""(?:-m|--message)[= ]\s*(["'])(.*?)\1""", cmd, re.S)
msg = m.group(2) if m else ""
h = re.match(r"""\$\(cat <<-?\s*["']?\w+["']?\s*\n(.*)""", msg, re.S)
if h:
    msg = h.group(1)
subject = next((l.strip() for l in msg.splitlines() if l.strip()), "")
if subject and not re.match(r"^(build|fix|feat|refactor|docs|test|chore|perf|style|ci|revert)(\([^)]+\))?!?: \S", subject):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
        "additionalContext": "Commit subject \"%s\" is not Conventional Commits (type(scope): subject, e.g. build(3.2): ..., fix: ...). Amend it if this commit goes through." % subject[:80]}}))
PY
        ;;
esac

exit 0

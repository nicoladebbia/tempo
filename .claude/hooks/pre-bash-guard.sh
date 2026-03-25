#!/bin/bash
# Pre-Bash Guard — Runs BEFORE any Bash command
# Validates git commit messages follow the convention
# Exit 0 = allow, Exit 2 = block

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# 1. Validate git commit messages follow convention: build(X.Y): description
if echo "$COMMAND" | grep -q "git commit"; then
    # Extract the commit message
    MSG=$(echo "$COMMAND" | grep -oP '(?<=-m ["\x27])[^"\x27]+' | head -1)

    if [[ -n "$MSG" ]]; then
        # Must start with: build(, fix(, feat(, refactor(, docs(, test(, chore(
        if ! echo "$MSG" | grep -qE '^(build|fix|feat|refactor|docs|test|chore)\('; then
            echo "Warning: Commit message should follow Conventional Commits format: 'build(X.Y): description'"
            echo "Got: '$MSG'"
            # Warn but don't block — Claude will see the warning
        fi
    fi
fi

# 2. Block dangerous commands that slipped through permissions
if echo "$COMMAND" | grep -qE 'rm\s+-rf\s+/|rm\s+-rf\s+~|format\s+|mkfs'; then
    echo "BLOCKED: Dangerous command detected" >&2
    exit 2
fi

# 3. Block npm install / pip install without review (dependency control)
if echo "$COMMAND" | grep -qE 'npm install|pip install|brew install'; then
    echo "Warning: Package installation detected. Verify against docs/DEPENDENCIES.md — only approved packages allowed."
fi

exit 0

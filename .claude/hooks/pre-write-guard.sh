#!/bin/bash
# Pre-Write Guard — PreToolUse on Write|Edit.
# exit 2 + stderr = block (Claude sees the reason). Folder-placement hints for NEW
# Swift files go to Claude as additionalContext. Otherwise silent.

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
PROJECT_DIR="${PROJECT_DIR%/}"
if [[ -z "$PROJECT_DIR" ]]; then
    echo "BLOCKED: cannot determine the project directory; refusing write to $FILE_PATH." >&2
    exit 2
fi

# 1. Block writes outside the project (worktrees included via CLAUDE_PROJECT_DIR).
#    Claude's own state (~/.claude) and temp/scratchpad dirs are allowed.
case "$FILE_PATH" in
    "$PROJECT_DIR"/*|"$HOME"/.claude/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) ;;
    *)
        echo "BLOCKED: $FILE_PATH is outside the Tempo project ($PROJECT_DIR)." >&2
        exit 2 ;;
esac

# 2. Read-only meta-audits. (The module/spec docs became AS-BUILT docs on 2026-05-19
#    and are editable; only these two stay protected.)
case "$FILE_PATH" in
    */docs/CROSS_DOC_AUDIT.md|*/docs/TECHNICAL_FEASIBILITY_AUDIT.md)
        echo "BLOCKED: $(basename "$FILE_PATH") is a read-only audit reference." >&2
        exit 2 ;;
esac

# 3. No secrets files in the repo.
BASE=$(basename "$FILE_PATH")
if [[ "$BASE" == .env || "$BASE" == *.env || "$BASE" == .env.* ]] && [[ "$BASE" != *.example && "$BASE" != *.sample && "$BASE" != *.template ]]; then
    echo "BLOCKED: do not create .env files in the repo; use .env.example as the template." >&2
    exit 2
fi

# 4. Folder placement hint — only when creating a NEW Swift file.
if [[ "$FILE_PATH" == *.swift && ! -e "$FILE_PATH" && "$FILE_PATH" != *Tests/* ]]; then
    NAME=$(basename "$FILE_PATH")
    HINT=""
    if [[ "$NAME" == *View.swift && "$FILE_PATH" != */Views/* && "$FILE_PATH" != *"/Preview Content/"* && "$FILE_PATH" != *Widget* ]]; then
        HINT="New view $NAME is outside a Views/ directory."
    elif [[ ("$NAME" == *Service.swift || "$NAME" == *Engine.swift) && "$FILE_PATH" != */Services/* ]]; then
        HINT="New service/engine $NAME is outside a Services/ directory."
    elif [[ ("$NAME" == *Model*.swift || "$NAME" == *Entity*.swift) && "$NAME" != *ViewModel* && "$FILE_PATH" != */Models/* && "$FILE_PATH" != */DTOs/* && "$FILE_PATH" != */Services/* ]]; then
        HINT="New model $NAME is outside a Models/ directory."
    fi
    if [[ -n "$HINT" ]]; then
        python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":sys.argv[1]}}))' "Folder convention: $HINT Move it unless there is a reason."
    fi
fi

exit 0

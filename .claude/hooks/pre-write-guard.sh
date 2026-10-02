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

# Is $1 inside a registered git worktree of this repo (e.g. a /round lane in
# ~/dev/tempo-<name>)? Uses `git worktree list`, so a random ~/dev/tempo-foo
# folder that isn't a worktree still counts as outside. ".." is resolved first.
in_repo_worktree() {
    local target wt
    target=$(python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$1" 2>/dev/null) || return 1
    while IFS= read -r wt; do
        [[ -n "$wt" && "$target" == "${wt%/}"/* ]] && return 0
    done < <(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    return 1
}

# 1. Block writes outside the project and its git worktrees.
#    Claude's own state (~/.claude) and temp/scratchpad dirs are allowed.
case "$FILE_PATH" in
    "$PROJECT_DIR"/*|"$HOME"/.claude/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) ;;
    *)
        if ! in_repo_worktree "$FILE_PATH"; then
            echo "BLOCKED: $FILE_PATH is outside the Tempo project ($PROJECT_DIR) and its worktrees." >&2
            exit 2
        fi ;;
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

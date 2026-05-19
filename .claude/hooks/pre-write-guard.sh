#!/bin/bash
# Pre-Write Guard — Runs BEFORE any file write
# Blocks writes that violate project conventions
# Exit 0 = allow, Exit 2 = block

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# 1. Block writes outside the project directory
PROJECT_DIR="/Users/nicoladebbia/Projects/tempo"
if [[ "$FILE_PATH" != "$PROJECT_DIR"* ]]; then
    echo "BLOCKED: Cannot write outside the Tempo project directory" >&2
    exit 2
fi

# 2. Block writes to the remaining read-only audit references.
# NOTE (2026-05-19): the module/spec docs (DESIGN_SYSTEM, DATA_MODELS_IOS,
# STATE_MACHINES, UX_COPY_BIBLE, the MODULE_* set, etc.) were reconciled into
# AS-BUILT documentation describing the actual codebase. They are no longer
# aspirational specs, so they are no longer write-protected. The two files
# below remain protected because they are meta-audits, not specs.
if [[ "$FILE_PATH" == */docs/CROSS_DOC_AUDIT.md ]] || \
   [[ "$FILE_PATH" == */docs/TECHNICAL_FEASIBILITY_AUDIT.md ]]; then
    echo "BLOCKED: Cannot modify audit reference docs. These are read-only references." >&2
    exit 2
fi

# 3. Enforce folder structure — Swift files must be in correct directories
if [[ "$FILE_PATH" == *.swift ]]; then
    FILENAME=$(basename "$FILE_PATH")

    # Models must be in Models/
    if [[ "$FILENAME" == *Model* ]] || [[ "$FILENAME" == *Entity* ]]; then
        if [[ "$FILE_PATH" != *"/Models/"* ]] && [[ "$FILE_PATH" != *"/DTOs/"* ]]; then
            echo "Warning: Model file '$FILENAME' should be in a Models/ directory"
        fi
    fi

    # Views must be in Views/
    if [[ "$FILENAME" == *View.swift ]]; then
        if [[ "$FILE_PATH" != *"/Views/"* ]] && [[ "$FILE_PATH" != *"/Preview Content/"* ]]; then
            echo "Warning: View file '$FILENAME' should be in a Views/ directory"
        fi
    fi

    # Services must be in Services/
    if [[ "$FILENAME" == *Service.swift ]] || [[ "$FILENAME" == *Engine.swift ]]; then
        if [[ "$FILE_PATH" != *"/Services/"* ]]; then
            echo "Warning: Service file '$FILENAME' should be in a Services/ directory"
        fi
    fi
fi

# 4. Block .env files from being created (secrets must not be in repo)
if [[ "$FILE_PATH" == *".env" ]] && [[ "$FILE_PATH" != *".env.example"* ]]; then
    echo "BLOCKED: Do not create .env files in the repo. Use .env.example as template." >&2
    exit 2
fi

exit 0

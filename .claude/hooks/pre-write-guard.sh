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

# 2. Block writes to protected files (docs should not be modified during build)
if [[ "$FILE_PATH" == */docs/DESIGN_SYSTEM.md ]] || \
   [[ "$FILE_PATH" == */docs/DATA_MODELS_IOS.md ]] || \
   [[ "$FILE_PATH" == */docs/STATE_MACHINES.md ]] || \
   [[ "$FILE_PATH" == */docs/CROSS_DOC_AUDIT.md ]] || \
   [[ "$FILE_PATH" == */docs/TECHNICAL_FEASIBILITY_AUDIT.md ]] || \
   [[ "$FILE_PATH" == */docs/UX_COPY_BIBLE.md ]]; then
    echo "BLOCKED: Cannot modify specification docs during build. These are read-only references." >&2
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

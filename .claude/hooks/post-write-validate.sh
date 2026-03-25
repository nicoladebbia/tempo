#!/bin/bash
# Post-Write Validation Hook
# Runs after every Write/Edit tool call to validate the change
# Exit 0 = proceed, Exit 2 = block and send feedback to Claude

# Get the file that was just written from the tool input
# The hook receives tool input via stdin as JSON
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Skip validation for non-Swift files and docs
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Only validate Swift files
if [[ "$FILE_PATH" != *.swift ]]; then
    exit 0
fi

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# 1. Check for basic Swift syntax issues
# Look for common mistakes: unclosed braces, missing imports
BRACE_OPEN=$(grep -c '{' "$FILE_PATH" 2>/dev/null || echo 0)
BRACE_CLOSE=$(grep -c '}' "$FILE_PATH" 2>/dev/null || echo 0)

if [[ "$BRACE_OPEN" != "$BRACE_CLOSE" ]]; then
    echo "⚠️ Brace mismatch in $FILE_PATH: $BRACE_OPEN opening vs $BRACE_CLOSE closing braces" >&2
    # Don't block, just warn — Claude will see this
    echo "Warning: Possible brace mismatch in $FILE_PATH ($BRACE_OPEN open, $BRACE_CLOSE close). Please verify."
    exit 0
fi

# 2. Check for forbidden patterns
# No hardcoded colors (must use design tokens)
if grep -qE '#[0-9A-Fa-f]{6}' "$FILE_PATH" 2>/dev/null; then
    # Check if it's in the design system file itself (allowed there)
    if [[ "$FILE_PATH" != *"DesignSystem"* && "$FILE_PATH" != *"Theme"* && "$FILE_PATH" != *"Color+"* ]]; then
        HARDCODED=$(grep -n '#[0-9A-Fa-f]{6}' "$FILE_PATH" | head -3)
        echo "⚠️ Hardcoded hex color found in $FILE_PATH. Use design tokens instead."
        echo "Lines: $HARDCODED"
        echo "Reference: docs/DESIGN_SYSTEM.md for canonical color tokens"
    fi
fi

# 3. Check for hardcoded strings (should use UX_COPY_BIBLE keys)
if grep -qE '"[A-Z][a-z].*[a-z]"' "$FILE_PATH" 2>/dev/null; then
    # Skip if it's in a string catalog or localization file
    if [[ "$FILE_PATH" != *"Localizable"* && "$FILE_PATH" != *"String+"* && "$FILE_PATH" != *".xcstrings"* ]]; then
        # Only warn for View files (where hardcoded strings are most problematic)
        if [[ "$FILE_PATH" == *"View"* ]]; then
            echo "Note: Check for hardcoded user-facing strings in $FILE_PATH. Reference: docs/UX_COPY_BIBLE.md"
        fi
    fi
fi

# 4. Check for TODO(human) markers that haven't been addressed
if grep -q 'TODO(human)' "$FILE_PATH" 2>/dev/null; then
    echo "📝 TODO(human) marker found in $FILE_PATH — this needs user input before proceeding."
fi

# All checks passed
exit 0

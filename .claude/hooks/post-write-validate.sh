#!/bin/bash
# Post-Write Validate — PostToolUse on Write|Edit of .swift files.
# Checks only the text Claude just wrote (Write content / Edit new_string), so
# pre-existing code never re-triggers. Findings go to Claude as additionalContext
# (JSON on stdout, exit 0). Silent when clean.

HOOK_INPUT=$(cat) python3 - <<'PY'
import json, os, re, sys
try:
    d = json.loads(os.environ.get("HOOK_INPUT") or "{}")
except ValueError:
    sys.exit(0)
ti = d.get("tool_input", {}) or {}
path = ti.get("file_path", "")
if not path.endswith(".swift"):
    sys.exit(0)
text = ti.get("content")
if text is None:
    text = ti.get("new_string", "")
name = path.rsplit("/", 1)[-1]
notes = []
exempt = any(k in path for k in ("DesignSystem", "Theme", "Color+", "Tests/", "Preview"))
if not exempt:
    hexes = sorted(set(re.findall(r"#[0-9A-Fa-f]{6}\b", text)))
    if hexes:
        notes.append("Hardcoded hex color(s) %s in %s: use design tokens / Assets.xcassets/Colors (docs/DESIGN_SYSTEM.md)." % (", ".join(hexes[:5]), name))
if "TODO(human)" in text:
    notes.append("TODO(human) marker in %s: needs Nicola's input before this is done." % name)
if notes:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "\n".join(notes)}}))
PY
exit 0

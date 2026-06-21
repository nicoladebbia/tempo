#!/bin/bash
# parallel.sh — run several Claude sessions on Tempo at once, each in its own
# git worktree, then merge them all back onto main. Worktrees are siblings of
# the main repo (~/Projects/tempo-<name>), each on its own branch <name>.
#
# WHY: two `claude` sessions in the SAME directory clobber each other's edits
# silently (last write wins, no conflict). Separate worktrees give each session
# its own physical copy of the files, so they cannot collide on disk. Conflicts
# only surface at merge time, where they are explicit and resolvable.
#
# Usage (run from the MAIN repo root):
#   ./scripts/parallel.sh new recovery arena training   # create worktrees + open terminals
#   ./scripts/parallel.sh list                           # show worktrees + branch state
#   ./scripts/parallel.sh merge                          # merge all branches -> main, clean up
#   ./scripts/parallel.sh clean                          # remove worktrees+branches WITHOUT merging (abandon)

set -euo pipefail

# --- locate the main repo (the non-worktree checkout) ---
MAIN_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$MAIN_ROOT" ]; then
    echo "[ERR] not inside a git repo. cd into ~/Projects/tempo first."
    exit 1
fi
PARENT="$(dirname "$MAIN_ROOT")"
REPO_NAME="$(basename "$MAIN_ROOT")"
MAIN_BRANCH="main"

# Refuse to operate from inside a linked worktree — merge/new must run from the
# real main checkout, or `git worktree add` paths and the merge target get confused.
GIT_COMMON="$(git rev-parse --git-common-dir)"
GIT_DIR="$(git rev-parse --git-dir)"
if [ "$GIT_COMMON" != "$GIT_DIR" ]; then
    echo "[ERR] you're inside a worktree, not the main repo."
    echo "      cd $MAIN_ROOT  and run this again."
    exit 1
fi

cmd="${1:-}"; shift || true

# ---------------------------------------------------------------------------
open_terminal() {
    # Open a new Terminal.app tab cd'd into $1, ready for the user to type `claude`.
    local dir="$1"
    osascript >/dev/null 2>&1 <<EOF || echo "  [WARN] couldn't auto-open a terminal for $dir — open one yourself and: cd $dir"
tell application "Terminal"
    activate
    do script "cd '$dir' && clear && echo 'worktree ready — branch:' \$(git branch --show-current) && echo 'type: claude'"
end tell
EOF
}

# ---------------------------------------------------------------------------
do_new() {
    if [ "$#" -eq 0 ]; then
        echo "[ERR] give at least one scope name, e.g.: parallel.sh new recovery arena"
        exit 1
    fi
    # Must be on a clean-ish main: worktrees branch off the current main HEAD.
    git -C "$MAIN_ROOT" fetch --quiet origin 2>/dev/null || true
    echo "Creating worktrees off '$MAIN_BRANCH' (HEAD: $(git -C "$MAIN_ROOT" rev-parse --short "$MAIN_BRANCH"))"
    echo ""
    for name in "$@"; do
        local wt="$PARENT/${REPO_NAME}-${name}"
        if [ -e "$wt" ]; then
            echo "  [SKIP] $wt already exists"
            continue
        fi
        if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$name"; then
            echo "  [SKIP] branch '$name' already exists — pick a fresh name or 'merge'/'clean' first"
            continue
        fi
        git -C "$MAIN_ROOT" worktree add -b "$name" "$wt" "$MAIN_BRANCH" >/dev/null
        echo "  [OK]  $wt   (branch: $name)"
        open_terminal "$wt"
    done
    echo ""
    echo "Each terminal: type 'claude' and give it ONE module's work."
    echo "When all sessions are done, come back here and run: ./scripts/parallel.sh merge"
}

# ---------------------------------------------------------------------------
do_list() {
    echo "=== Worktrees ==="
    git -C "$MAIN_ROOT" worktree list
    echo ""
    echo "=== Sibling worktree branches (ahead of $MAIN_BRANCH) ==="
    git -C "$MAIN_ROOT" worktree list --porcelain | awk '/^branch / {gsub("refs/heads/","",$2); print $2}' \
        | grep -v "^${MAIN_BRANCH}$" | while read -r br; do
            ahead="$(git -C "$MAIN_ROOT" rev-list --count "${MAIN_BRANCH}..${br}" 2>/dev/null || echo "?")"
            echo "  $br: $ahead commit(s) ahead of $MAIN_BRANCH"
        done
}

# ---------------------------------------------------------------------------
do_merge() {
    # Main working tree must be clean, or a merge could entangle unrelated changes.
    if [ -n "$(git -C "$MAIN_ROOT" status --porcelain)" ]; then
        echo "[ERR] main working tree ($MAIN_ROOT) is dirty. Commit or stash first, then merge."
        git -C "$MAIN_ROOT" status --short
        exit 1
    fi
    git -C "$MAIN_ROOT" checkout "$MAIN_BRANCH" >/dev/null 2>&1 || true

    # Collect worktree branches (everything except main).
    mapfile -t branches < <(git -C "$MAIN_ROOT" worktree list --porcelain \
        | awk '/^branch / {gsub("refs/heads/","",$2); print $2}' | grep -v "^${MAIN_BRANCH}$")

    if [ "${#branches[@]}" -eq 0 ]; then
        echo "No worktree branches to merge."
        exit 0
    fi

    echo "Merging ${#branches[@]} branch(es) onto $MAIN_BRANCH, one at a time:"
    for br in "${branches[@]}"; do
        echo ""
        echo "--- merging '$br' ---"
        if git -C "$MAIN_ROOT" merge --no-ff -m "merge($br): parallel session" "$br"; then
            echo "  [OK] $br merged"
            # remove its worktree + branch now that it's landed
            local wt="$PARENT/${REPO_NAME}-${br}"
            git -C "$MAIN_ROOT" worktree remove "$wt" --force 2>/dev/null || true
            git -C "$MAIN_ROOT" branch -D "$br" >/dev/null 2>&1 || true
            echo "  [OK] cleaned up worktree + branch '$br'"
        else
            echo ""
            echo "  [CONFLICT] '$br' collides with main — two sessions edited the same file."
            echo "  This is the expected manual step. Do this:"
            echo "    1. cd $MAIN_ROOT"
            echo "    2. resolve the conflicted files (both intents matter — don't blindly pick one side)"
            echo "    3. git add <files> && git commit"
            echo "    4. re-run: ./scripts/parallel.sh merge   (it resumes with the remaining branches)"
            echo ""
            echo "  Worktree '$br' was LEFT in place so you can re-read its edits if needed."
            exit 1
        fi
    done

    echo ""
    echo "All branches merged. NOW run the single authoritative build + the shared-model check:"
    echo "    /build        (Swift 6 strict-concurrency breakage surfaces here, not before)"
    echo "    then: for any @Observable service / SwiftData entity a session touched,"
    echo "          enumerate-the-readers (a clean merge can still desync two screens)."
}

# ---------------------------------------------------------------------------
do_clean() {
    # Abandon worktrees WITHOUT merging — use when the parallel work is being thrown away.
    mapfile -t branches < <(git -C "$MAIN_ROOT" worktree list --porcelain \
        | awk '/^branch / {gsub("refs/heads/","",$2); print $2}' | grep -v "^${MAIN_BRANCH}$")
    if [ "${#branches[@]}" -eq 0 ]; then
        echo "Nothing to clean."
        exit 0
    fi
    echo "About to DISCARD these worktrees and their unmerged commits:"
    printf '  %s\n' "${branches[@]}"
    read -r -p "Type 'yes' to confirm: " ans
    [ "$ans" = "yes" ] || { echo "aborted."; exit 0; }
    for br in "${branches[@]}"; do
        git -C "$MAIN_ROOT" worktree remove "$PARENT/${REPO_NAME}-${br}" --force 2>/dev/null || true
        git -C "$MAIN_ROOT" branch -D "$br" >/dev/null 2>&1 || true
        echo "  [OK] discarded '$br'"
    done
}

# ---------------------------------------------------------------------------
case "$cmd" in
    new)   do_new "$@" ;;
    list)  do_list ;;
    merge) do_merge ;;
    clean) do_clean ;;
    *)
        echo "Tempo parallel-session helper"
        echo ""
        echo "  ./scripts/parallel.sh new <scope> [<scope> ...]   create worktrees + open terminals"
        echo "  ./scripts/parallel.sh list                        show worktrees + how far ahead each is"
        echo "  ./scripts/parallel.sh merge                       merge all branches -> main, clean up"
        echo "  ./scripts/parallel.sh clean                       discard worktrees WITHOUT merging"
        echo ""
        echo "Scopes should be MODULES so sessions don't edit the same files:"
        echo "  recovery  training  arena  dashboard  accountability"
        exit 1
        ;;
esac

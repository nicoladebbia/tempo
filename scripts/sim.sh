#!/bin/bash
# sim.sh — one simulator + one DerivedData folder per worktree.
#
# WHY: sessions that share a simulator (e.g. the stock "iPhone 17") queue behind
# each other ("test runner hung before establishing connection") and install the
# app over each other. Sessions that share DerivedData hit "database is locked".
# This script gives every worktree its own of both, created on first use:
#   simulator   "Tempo · <worktree>"   (iPhone 17, latest iOS runtime)
#   DerivedData <worktree>/DerivedData (gitignored; disappears with the worktree)
#
# Usage (from anywhere inside a worktree):
#   scripts/sim.sh udid                 create/boot this worktree's sim, print its UDID
#   scripts/sim.sh build [args]         xcodebuild build for the sim
#   scripts/sim.sh test  [args]         xcodebuild test (default -only-testing:TempoTests)
#   scripts/sim.sh run   [launch args]  build, install and launch "Tempo Dev"
#   scripts/sim.sh qa    [launch args]  run past onboarding, permissions pre-granted
#   scripts/sim.sh shot  <file.png>     screenshot, resized to points so AXe taps match
#   scripts/sim.sh name | dd | dest     print the sim name / DerivedData path / -destination
#   scripts/sim.sh clean                delete this worktree's sim and DerivedData
# Target another worktree with --dir <path> (used by parallel.sh / cleanup.sh).

set -euo pipefail

DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17"
BUNDLE_ID="app.tempo.Tempo.dev"
QA_ARGS=(--uitesting-skip-onboarding -healthKitAuthorized YES -hasCompletedSetup YES)

DIR=""
if [ "${1:-}" = "--dir" ]; then
    DIR="${2:?--dir needs a path}"
    shift 2
fi
ROOT="$(git -C "${DIR:-.}" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
    echo "[ERR] not inside a Tempo worktree${DIR:+ ($DIR)}." >&2
    exit 1
fi

# Simulator name for a worktree: main repo → "main", ~/dev/tempo-r1 → "r1",
# .claude/worktrees/agent-a4ddab012c271a193 → "agent-a4ddab0".
sim_slug() {
    local root="$1" base
    if [ "$(cd "$root" && git rev-parse --git-common-dir)" = "$(cd "$root" && git rev-parse --git-dir)" ]; then
        echo "main"
        return
    fi
    base="$(basename "$root")"
    base="${base#tempo-}"
    case "$base" in agent-*) base="${base:0:13}" ;; esac
    echo "$base"
}

SIM_NAME="${TEMPO_SIM_NAME:-Tempo · $(sim_slug "$ROOT")}"
DD="$ROOT/DerivedData"
PROJECT="$ROOT/Tempo/Tempo.xcodeproj"

find_udid() {
    xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["name"] == name:
            print(d["udid"]); raise SystemExit
' "$SIM_NAME"
}

latest_runtime() {
    xcrun simctl list runtimes available -j | python3 -c '
import json, sys
ios = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS"]
ios.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(ios[-1]["identifier"] if ios else "")
'
}

# Create (once) and boot this worktree's simulator; prints the UDID.
# The lock stops two subagents in one worktree from creating two sims.
ensure_sim() {
    local udid rt lock tries=0
    lock="/tmp/tempo-sim-$(printf '%s' "$SIM_NAME" | shasum | cut -c1-12).lock"
    while ! mkdir "$lock" 2>/dev/null; do
        tries=$((tries + 1))
        # A lock older than 2 minutes is left over from a killed run.
        [ "$tries" -gt 120 ] && { rmdir "$lock" 2>/dev/null || true; tries=0; }
        sleep 1
    done
    udid="$(find_udid)"
    if [ -z "$udid" ]; then
        rt="$(latest_runtime)"
        if [ -z "$rt" ]; then
            rmdir "$lock"
            echo "[ERR] no iOS simulator runtime installed." >&2
            exit 1
        fi
        udid="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$rt")"
        echo "[sim] created \"$SIM_NAME\" ($udid)" >&2
    fi
    rmdir "$lock"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    echo "$udid"
}

xcb() {
    local action="$1" udid
    shift
    udid="$(ensure_sim)"
    xcodebuild "$action" -project "$PROJECT" -scheme Tempo \
        -destination "id=$udid" -derivedDataPath "$DD" -quiet "$@"
}

app_path() {
    local app="$DD/Build/Products/Debug-iphonesimulator/Tempo Dev.app"
    [ -d "$app" ] || { echo "[ERR] $app not found — build first." >&2; exit 1; }
    echo "$app"
}

# Pre-grant the permissions simctl can grant, so a fresh simulator doesn't stop
# QA on system prompts (HealthKit and notifications can't be granted this way).
grant_permissions() {
    local service
    for service in calendar reminders photos microphone motion; do
        xcrun simctl privacy "$1" grant "$service" "$BUNDLE_ID" 2>/dev/null || true
    done
}

do_run() {
    local udid app grant="$1"
    shift
    xcb build
    udid="$(ensure_sim)"
    app="$(app_path)"
    xcrun simctl install "$udid" "$app"
    [ "$grant" = "grant" ] && grant_permissions "$udid"
    open -a Simulator --args -CurrentDeviceUDID "$udid" 2>/dev/null || true
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" "$@"
}

do_clean() {
    local udid
    udid="$(find_udid)"
    if [ -n "$udid" ]; then
        xcrun simctl shutdown "$udid" 2>/dev/null || true
        xcrun simctl delete "$udid"
        echo "[sim] deleted \"$SIM_NAME\" ($udid)"
    fi
    if [ -d "$DD" ]; then
        rm -rf "$DD"
        echo "[sim] deleted $DD"
    fi
}

cmd="${1:-}"
shift || true
case "$cmd" in
    udid) ensure_sim ;;
    name) echo "$SIM_NAME" ;;
    dd) echo "$DD" ;;
    dest) echo "id=$(ensure_sim)" ;;
    build) xcb build "$@" ;;
    test)
        case " $* " in
            *" -only-testing"*) xcb test "$@" ;;
            *) xcb test -only-testing:TempoTests "$@" ;;
        esac
        ;;
    run) do_run nogrant "$@" ;;
    qa) do_run grant "${QA_ARGS[@]}" "$@" ;;
    shot)
        out="${1:?usage: sim.sh shot <file.png>}"
        udid="$(ensure_sim)"
        xcrun simctl io "$udid" screenshot "$out" >/dev/null 2>&1
        sips -z 874 402 "$out" >/dev/null # iPhone 17 is 402×874 points
        echo "$out"
        ;;
    clean) do_clean ;;
    *)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac

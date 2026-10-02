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
#   scripts/sim.sh qa --local [--as NAME] [--scenario NAME] [--fresh] [--free] [--no-build]
#                                       same, against the local test server (testenv.sh):
#                                       signed in as test account NAME (default: this sim),
#                                       --scenario seeds on-device data (implies --fresh),
#                                       --fresh wipes the app's data + keychain first,
#                                       --free signs in without Pro
#   scripts/sim.sh scenarios            list scenarios
#   scripts/sim.sh notify <kind> [json] deliver a push with real action buttons (list: notify help)
#   scripts/sim.sh shot  <file.png>     screenshot, resized to points so AXe taps match
#   scripts/sim.sh name | dd | dest     print the sim name / DerivedData path / -destination
#   scripts/sim.sh open <url>           open a link in the sim (e.g. a grocery share link in Safari)
#   scripts/sim.sh clean                delete this worktree's sims and DerivedData
# Target another worktree with --dir <path> (used by parallel.sh / cleanup.sh).
# Two users at once: --sim <id> uses a second simulator "Tempo · <worktree> · <id>"
# with its own test account (default name <worktree>-<id>), e.g.
#   scripts/sim.sh qa --local --as alice && scripts/sim.sh --sim b qa --local --as bob --no-build

set -euo pipefail

DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17"
BUNDLE_ID="app.tempo.Tempo.dev"
QA_ARGS=(--uitesting-skip-onboarding -healthKitAuthorized YES -hasCompletedSetup YES)

DIR=""
if [ "${1:-}" = "--dir" ]; then
    DIR="${2:?--dir needs a path}"
    shift 2
fi
SECOND=""
if [ "${1:-}" = "--sim" ]; then
    SECOND="${2:?--sim needs an id, e.g. b}"
    [[ "$SECOND" =~ ^[a-z0-9]{1,8}$ ]] || { echo "[ERR] --sim: 1-8 lowercase letters/digits" >&2; exit 1; }
    shift 2
fi
ROOT="$(git -C "${DIR:-.}" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
    echo "[ERR] not inside a Tempo worktree${DIR:+ ($DIR)}." >&2
    exit 1
fi
# --dir must be a worktree root itself: a plain folder inside another checkout
# would resolve to that checkout and `clean` would delete the wrong simulator.
if [ -n "$DIR" ] && [ "$(cd "$DIR" && pwd -P)" != "$(cd "$ROOT" && pwd -P)" ]; then
    echo "[ERR] --dir $DIR is not a worktree root (it belongs to $ROOT)." >&2
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

BASE_SIM_NAME="${TEMPO_SIM_NAME:-Tempo · $(sim_slug "$ROOT")}"
SIM_NAME="$BASE_SIM_NAME${SECOND:+ · $SECOND}"
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
    # shellcheck disable=SC2064 # expand $lock now
    trap "rmdir '$lock' 2>/dev/null || true" EXIT
    udid="$(find_udid)"
    if [ -z "$udid" ]; then
        rt="$(latest_runtime)"
        if [ -z "$rt" ]; then
            echo "[ERR] no iOS simulator runtime installed." >&2
            exit 1
        fi
        udid="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$rt")"
        echo "[sim] created \"$SIM_NAME\" ($udid)" >&2
    fi
    rmdir "$lock"
    trap - EXIT
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

# Wipe the app's on-device data: SwiftData store (it lives in the app group,
# which survives uninstall), preferences and Keychain (simulator-wide).
# Run before install: uninstalling clears the app's own container and
# preferences; the group store and Keychain need clearing separately.
wipe_app_data() {
    local udid="$1" group
    group="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" groups 2>/dev/null | awk -F'\t' '$1 == "group.app.tempo.Tempo" {print $2}' || true)"
    xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2>/dev/null || true
    if [ -n "$group" ] && [ -d "$group/Library/Application Support" ]; then
        find "$group/Library/Application Support" -maxdepth 1 -name 'Tempo.store*' -exec rm -rf {} +
    fi
    xcrun simctl keychain "$udid" reset 2>/dev/null || true
    echo "[sim] wiped app data + keychain" >&2
}

# POST /v1/test/login → launch args that hand the session to the app.
test_login_args() {
    local udid="$1" name="$2" fresh="$3" pro="$4" url
    url="$("$ROOT/scripts/testenv.sh" url)"
    curl -fsS -m 10 -X POST "$url/v1/test/login" \
        -H 'Content-Type: application/json' -H "X-Device-Id: sim-$udid" \
        -d "{\"name\":\"$name\",\"simulator_udid\":\"$udid\",\"fresh\":$fresh,\"pro\":$pro}" |
        python3 -c '
import json, sys
r = json.load(sys.stdin)
url, udid = sys.argv[1], sys.argv[2]
print("\n".join(["-tempoAPIBaseURL", url, "-tempoTestDeviceID", "sim-" + udid,
                 "-tempoTestAccessToken", r["access_token"], "-tempoTestRefreshToken", r["refresh_token"],
                 "-tempoTestUserID", r["user_id"]]))
print(("created" if r["created"] else "reused") + " test account " + r["user_id"], file=sys.stderr)
' "$url" "$udid"
}

do_run() {
    local udid app grant="$1" local_mode=0 name="" scenario="" fresh=0 pro=true build=1
    shift
    local extra=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --local) local_mode=1 ;;
            --as)
                name="${2:?--as needs a name}"; local_mode=1; shift
                [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || { echo "[ERR] --as: lowercase letters, digits and '-' only (max 40)" >&2; exit 1; } ;;
            --scenario) scenario="${2:?--scenario needs a name}"; local_mode=1; fresh=1; shift ;;
            --fresh) fresh=1 ;;
            --free) pro=false; local_mode=1 ;;
            --no-build) build=0 ;;
            *) extra+=("$1") ;;
        esac
        shift
    done
    [ "$build" = 1 ] && xcb build
    udid="$(ensure_sim)"
    app="$(app_path)"
    [ "$fresh" = 1 ] && wipe_app_data "$udid"
    xcrun simctl install "$udid" "$app"
    [ "$grant" = "grant" ] && grant_permissions "$udid"
    local server=(-tempoAPIBaseURL off)
    if [ "$local_mode" = 1 ]; then
        "$ROOT/scripts/testenv.sh" up >/dev/null
        [ -z "$name" ] && name="$(sim_slug "$ROOT" | tr '[:upper:]_.' '[:lower:]--' | tr -cd 'a-z0-9-' | cut -c1-$((40 - ${#SECOND} - (${#SECOND} > 0))))${SECOND:+-$SECOND}"
        local line
        server=()
        while IFS= read -r line; do server+=("$line"); done < <(test_login_args "$udid" "$name" "$([ "$fresh" = 1 ] && echo true || echo false)" "$pro")
        [ "${#server[@]}" -eq 10 ] || { echo "[ERR] test login failed (scripts/testenv.sh logs)" >&2; exit 1; }
        # A persona scenario also has a server half (subscription, XP, receipts).
        if [ -n "$scenario" ] && "$ROOT/scripts/testenv.sh" persona "$name" "$scenario" 2>/dev/null; then :; fi
    fi
    [ -n "$scenario" ] && extra+=(--uitesting-scenario "$scenario")
    if [ "$scenario" = fresh ]; then # first-run path: keep onboarding
        local kept=() a
        for a in ${extra[@]+"${extra[@]}"}; do [ "$a" = --uitesting-skip-onboarding ] || kept+=("$a"); done
        extra=(${kept[@]+"${kept[@]}"})
    fi
    open -a Simulator --args -CurrentDeviceUDID "$udid" 2>/dev/null || true
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" "${server[@]}" ${extra[@]+"${extra[@]}"}
    [ "$local_mode" = 1 ] && allow_notifications "$udid"
    return 0
}

# The app asks for notification permission on local runs (simctl privacy has
# no notifications service); tap Allow so test pushes are delivered.
allow_notifications() {
    command -v axe >/dev/null || { echo "[sim] install AXe to auto-allow notifications: brew install cameroncooke/axe/axe" >&2; return 0; }
    local i
    for i in $(seq 1 20); do
        if axe describe-ui --udid "$1" 2>/dev/null | grep -q '"Allow"'; then
            axe tap --label "Allow" --udid "$1" >/dev/null 2>&1 && echo "[sim] notifications allowed" && return 0
        fi
        sleep 1
    done
    return 0
}

# Payloads match what the app registers in NotificationService.registerCategories
# and what TempoNotificationDelegate reads, so long-pressing the banner shows the
# real action buttons. Server pushes keep their custom keys under "data".
notify_payload() {
    local kind="$1" cat title body extra=""
    case "$kind" in
        briefing) cat=MORNING_BRIEFING title="Morning briefing" body="Green recovery. Full effort today." ;;
        gentle | firm | urgent | final | clear)
            cat="ACCOUNTABILITY_$(echo "$kind" | tr '[:lower:]' '[:upper:]')" title="Accountability" body="You said you'd train at 18:00." ;;
        weekly-plan) cat=WEEKLY_PLAN_PROMPT title="Plan next week?" body="Two minutes. Tap Build and it's done." ;;
        plan-ready) cat=MEAL_PLAN_READY title="Your week is planned" body="7 days of meals, macros checked. Tap to review."
            extra=',"data":{"type":"meal_plan_ready","interruption_level":"time-sensitive"}' ;;
        meal) cat=MEAL_REMINDER title="Meal 2 — Lunch" body="Chicken rice bowl. 650 kcal." ;;
        training) cat=TRAINING_REMINDER title="Training in 30 min" body="Upper body. Don't skip it." ;;
        recovery) cat=RECOVERY_REPORT title="Recovery report" body="Yellow. Adjust intensity, not commitment." ;;
        bedtime) cat=BEDTIME_REMINDER title="Bed in 30 min" body="Screens off. Tomorrow starts now." ;;
        defrost) cat=DEFROST_REMINDER title="Defrost tonight" body="Move the chicken to the fridge." ;;
        prep) cat=PREP_START_REMINDER title="Start prep" body="Dinner prep starts now." ;;
        streak) cat=STREAK_WARNING title="Streak at risk" body="Log one thing before midnight." ;;
        weekly-summary) cat=WEEKLY_SUMMARY title="Your week" body="5 of 6 workouts. Protein on target 6 days." ;;
        use-it-up) cat=USE_IT_UP title="Use it up" body="Spinach expires tomorrow." ;;
        arena) cat=ARENA_SOCIAL title="Arena" body="Alex passed you on the leaderboard." ;;
        supplement) cat=SUPPLEMENT_REMINDER title="Supplements" body="Creatine, Vitamin D." extra=',"supplementNames":["Creatine","Vitamin D"]' ;;
        reorder) cat=SUPPLEMENT_REORDER title="Running low" body="About 5 days of Creatine left." extra=',"supplementName":"Creatine"' ;;
        *) return 1 ;;
    esac
    printf '{"Simulator Target Bundle":"%s","aps":{"alert":{"title":"%s","body":"%s"},"category":"%s","sound":"default"}%s}' \
        "$BUNDLE_ID" "$title" "$body" "$cat" "$extra"
}

NOTIFY_KINDS="briefing gentle firm urgent final clear weekly-plan plan-ready meal training recovery bedtime defrost prep streak weekly-summary use-it-up arena supplement reorder"

do_notify() {
    local kind="${1:-help}" udid payload file
    if [ "$kind" = help ] || ! payload="$(notify_payload "$kind")"; then
        echo "usage: sim.sh notify <kind>   (kinds: $NOTIFY_KINDS)" >&2
        echo "       sim.sh notify json '<full APNs payload>'" >&2
        echo "Long-press the banner (axe touch --down --up --delay 1.2) to see its action buttons." >&2
        [ "$kind" = help ] && exit 0 || exit 1
    fi
    udid="$(ensure_sim)"
    file="$(mktemp -t tempo-push).apns"
    printf '%s' "$payload" >"$file"
    xcrun simctl push "$udid" "$BUNDLE_ID" "$file"
    rm -f "$file"
}

do_clean() {
    local udid name
    # This worktree's sim and its --sim extras.
    while IFS=$'\t' read -r udid name; do
        [ -n "$udid" ] || continue
        xcrun simctl shutdown "$udid" 2>/dev/null || true
        xcrun simctl delete "$udid"
        echo "[sim] deleted \"$name\" ($udid)"
    done < <(xcrun simctl list devices -j | python3 -c '
import json, sys
base = sys.argv[1]
only = sys.argv[2] if len(sys.argv) > 2 else ""
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if (only and d["name"] == only) or (not only and (d["name"] == base or d["name"].startswith(base + " · "))):
            print(d["udid"] + "\t" + d["name"])
' "$BASE_SIM_NAME" "${SECOND:+$SIM_NAME}")
    # --sim <id> clean: just that extra sim; the shared build stays.
    if [ -z "$SECOND" ] && [ -d "$DD" ]; then
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
    open) xcrun simctl openurl "$(ensure_sim)" "${1:?usage: sim.sh open <url>}" ;;
    notify)
        if [ "${1:-}" = json ]; then
            udid="$(ensure_sim)"
            file="$(mktemp -t tempo-push).apns"
            printf '%s' "${2:?usage: sim.sh notify json '<payload>'}" >"$file"
            xcrun simctl push "$udid" "$BUNDLE_ID" "$file"
            rm -f "$file"
        else
            do_notify "$@"
        fi
        ;;
    scenarios)
        grep -E '^ +case "[a-z-]+":? *//' "$ROOT/Tempo/Tempo/App/ScenarioSeed.swift" 2>/dev/null |
            sed -E 's/^ +case "([a-z-]+)":? *\/\/ ?/  \1 — /' || echo "no ScenarioSeed.swift"
        ;;
    *)
        awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
        exit 1
        ;;
esac

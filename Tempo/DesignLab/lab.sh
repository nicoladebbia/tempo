#!/usr/bin/env bash
# Design lab: build one look direction and screenshot it in its own simulator.
#   Tempo/DesignLab/lab.sh A build
#   Tempo/DesignLab/lab.sh A shot today|logger|food [out.png] [extra launch args...]
#   Tempo/DesignLab/lab.sh A udid
set -euo pipefail
D="${1:?direction A|B|C}"; CMD="${2:?build|shot|udid}"; shift 2
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
NAME="Tempo · ui-rework · lab$(echo "$D" | tr 'A-Z' 'a-z')"
DD="$ROOT/DerivedData/lab-$D"
udid() {
    local u
    u="$(xcrun simctl list devices available | grep -F "$NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
    if [ -z "$u" ]; then
        local rt; rt="$(xcrun simctl list runtimes available | grep -E '^iOS' | tail -1 | sed -E 's/.* - (com\.apple\.[^ ]+).*/\1/')"
        u="$(xcrun simctl create "$NAME" "iPhone 17 Pro" "$rt")"
    fi
    xcrun simctl boot "$u" 2>/dev/null || true
    xcrun simctl bootstatus "$u" -b >/dev/null
    echo "$u"
}
build() {
    (cd "$HERE/$D" && xcodegen generate --quiet)
    rm -rf "$DD/Build/Products/Debug-iphonesimulator/Lab$D.app"   # a stale app must not hide a failed build
    xcodebuild -project "$HERE/$D/Lab$D.xcodeproj" -scheme "Lab$D" -configuration Debug \
        -destination "id=$(udid)" -derivedDataPath "$DD" -quiet build 2>&1 | grep -E "error|warning: unre|BUILD" | head -40 || true
    test -d "$DD/Build/Products/Debug-iphonesimulator/Lab$D.app" || { echo "[ERR] build failed" >&2; exit 1; }
}
case "$CMD" in
    udid) udid ;;
    build) build; echo "[lab] built Lab$D" ;;
    shot)
        screen="${1:-today}"; out="${2:-$ROOT/DerivedData/lab-$D-$screen.png}"; shift $(( $# > 2 ? 2 : $# ))
        u="$(udid)"; id="com.tempo.designlab.Lab$D"
        xcrun simctl install "$u" "$DD/Build/Products/Debug-iphonesimulator/Lab$D.app"
        xcrun simctl terminate "$u" "$id" 2>/dev/null || true
        xcrun simctl ui "$u" appearance dark >/dev/null 2>&1 || true
        xcrun simctl status_bar "$u" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 >/dev/null 2>&1 || true
        xcrun simctl launch "$u" "$id" -screen "$screen" "$@" >/dev/null
        sleep "${LAB_SETTLE:-2.5}"
        xcrun simctl io "$u" screenshot "$out" >/dev/null 2>&1
        echo "$out" ;;
    *) echo "unknown command $CMD" >&2; exit 1 ;;
esac

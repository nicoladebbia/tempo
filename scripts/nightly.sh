#!/bin/bash
# nightly.sh — test main + every open PR overnight, then notify with a report.
#
# For each target (origin/main and each open, same-repo PR) in a throwaway
# worktree under .claude/worktrees/nightly-*:
#   1. iOS unit tests (TempoTests) on the target's own simulator
#   2. backend `swift test` against the local test databases (testenv.sh)
#   3. scenario smoke: launch each scenario on the local test server,
#      screenshot it, flag crashes
# Then: an HTML report (~/.tempo-nightly/latest.html), a Mac notification that
# opens it, and cleanup of the worktrees and simulators it made.
#
#   scripts/nightly.sh                 run now (all targets)
#   scripts/nightly.sh --only main     run one target (main | pr-<number>)
#   scripts/nightly.sh --skip-ios | --skip-backend | --skip-scenarios
#   scripts/nightly.sh install         run every night at 03:00 (launchd)
#   scripts/nightly.sh uninstall
#   scripts/nightly.sh open            open the latest report

set -uo pipefail

HOME_DIR="${TEMPO_NIGHTLY_HOME:-$HOME/.tempo-nightly}"
REPO="${TEMPO_REPO:-$HOME/dev/tempo}"
LABEL="app.tempo.nightly"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
NOTIFIER="$HOME/.local/share/mise/installs/ruby/3.3/bin/terminal-notifier"
SMOKE_SCENARIOS="${TEMPO_NIGHTLY_SCENARIOS:-fresh week groceries eaten-before-update edge}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

mkdir -p "$HOME_DIR"

case "${1:-}" in
    install)
        mkdir -p "$HOME_DIR/bin" "$(dirname "$PLIST")"
        cp "$0" "$HOME_DIR/bin/nightly.sh"
        chmod +x "$HOME_DIR/bin/nightly.sh"
        cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$HOME_DIR/bin/nightly.sh</string></array>
    <key>EnvironmentVariables</key>
    <dict><key>TEMPO_REPO</key><string>$REPO</string></dict>
    <key>StartCalendarInterval</key>
    <dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
    <key>StandardOutPath</key><string>$HOME_DIR/launchd.log</string>
    <key>StandardErrorPath</key><string>$HOME_DIR/launchd.log</string>
    <key>LowPriorityIO</key><false/>
</dict>
</plist>
EOF
        launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
        launchctl bootstrap "gui/$(id -u)" "$PLIST"
        echo "installed: runs daily at 03:00 (log $HOME_DIR/launchd.log, report $HOME_DIR/latest.html)"
        exit 0
        ;;
    uninstall)
        launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
        rm -f "$PLIST"
        echo "uninstalled"
        exit 0
        ;;
    open)
        open "$HOME_DIR/latest.html"
        exit 0
        ;;
esac

ONLY="" SKIP_IOS=0 SKIP_BACKEND=0 SKIP_SCENARIOS=0
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="${2:?}"; shift ;;
        --skip-ios) SKIP_IOS=1 ;;
        --skip-backend) SKIP_BACKEND=1 ;;
        --skip-scenarios) SKIP_SCENARIOS=1 ;;
        *) echo "unknown flag $1" >&2; exit 1 ;;
    esac
    shift
done

LOCK="$HOME_DIR/.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "nightly already running ($LOCK)" >&2
    exit 1
fi
WORKTREES=()
cleanup() {
    local wt
    for wt in ${WORKTREES[@]+"${WORKTREES[@]}"}; do
        [ -d "$wt" ] || continue
        bash "$(tool "$wt" sim.sh)" --dir "$wt" clean >/dev/null 2>&1 || true
        git -C "$REPO" worktree remove --force "$wt" >/dev/null 2>&1 || true
    done
    rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT

STAMP="$(date +%Y-%m-%d_%H%M)"
RUN="$HOME_DIR/runs/$STAMP"
mkdir -p "$RUN"
exec > >(tee -a "$RUN/nightly.log") 2>&1
echo "== Tempo nightly $STAMP"

git -C "$REPO" fetch --quiet --prune origin || { echo "fetch failed"; exit 1; }

# Each target runs its own sim.sh/testenv.sh (they change together with the
# app: scenarios, test login, launch args). origin/main's copies are the
# fallback for a branch that predates them.
TOOLS="$HOME_DIR/tools"
rm -rf "$TOOLS"
mkdir -p "$TOOLS"
for f in sim.sh testenv.sh; do
    git -C "$REPO" show "origin/main:scripts/$f" >"$TOOLS/$f" 2>/dev/null || rm -f "$TOOLS/$f"
done
tool() { # tool <worktree> <script> → path
    if [ -f "$1/scripts/$2" ]; then echo "$1/scripts/$2"; else echo "$TOOLS/$2"; fi
}

# Targets: "slug|ref|title"
TARGETS=("main|origin/main|main")
while IFS=$'\t' read -r num ref title; do
    [ -n "$num" ] || continue
    TARGETS+=("pr-$num|$ref|#$num $title")
done < <(gh pr list --repo "$(git -C "$REPO" remote get-url origin)" --state open --limit 30 \
    --json number,headRefOid,title,isCrossRepository \
    -q '.[] | select(.isCrossRepository == false) | [.number, .headRefOid, .title] | @tsv' 2>/dev/null)

RESULTS="$RUN/results.tsv"
: >"$RESULTS"

# result <slug> <step> <status pass|fail|skip> <summary> [detail-file]
result() { # fields can't contain tabs/newlines (swift test output has both)
    local summary="${4//$'\t'/ }"
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${summary//$'\n'/ }" "${5:-}" >>"$RESULTS"
}

xcresult_summary() {
    xcrun xcresulttool get test-results summary --path "$1" --compact 2>/dev/null | python3 -c '
import json, sys
try:
    s = json.load(sys.stdin)
except Exception:
    print("0 0 0"); raise SystemExit
print(s.get("passedTests", 0), s.get("failedTests", 0), s.get("skippedTests", 0))
for f in s.get("testFailures", [])[:40]:
    print("FAIL", f.get("testIdentifierString") or f.get("testName"), "—", (f.get("failureText") or "").replace("\n", " ")[:300])
'
}

run_ios() {
    local slug="$1" wt="$2" out="$RUN/$slug"
    local bundle="$out/ios.xcresult"
    (cd "$wt/Tempo" && xcodegen generate --quiet) || { result "$slug" "iOS tests" fail "xcodegen failed"; return; }
    local started=$SECONDS
    bash "$(tool "$wt" sim.sh)" --dir "$wt" test -resultBundlePath "$bundle" >"$out/ios.log" 2>&1
    local code=$? secs=$((SECONDS - started))
    local summary
    summary="$(xcresult_summary "$bundle")"
    local passed failed skipped
    read -r passed failed skipped <<<"$(echo "$summary" | head -1)"
    echo "$summary" | tail -n +2 >"$out/ios-failures.txt"
    if [ "$code" = 0 ] && [ "${failed:-0}" = 0 ]; then
        result "$slug" "iOS tests" pass "$passed passed, $skipped skipped (${secs}s)"
    elif [ "${passed:-0}" = 0 ] && [ "${failed:-0}" = 0 ]; then
        grep -E "error:" "$out/ios.log" | head -20 >"$out/ios-failures.txt"
        result "$slug" "iOS tests" fail "build failed (${secs}s)" "ios-failures.txt"
    else
        result "$slug" "iOS tests" fail "$failed failed, $passed passed (${secs}s)" "ios-failures.txt"
    fi
}

run_backend() {
    local slug="$1" wt="$2" out="$RUN/$slug"
    bash "$(tool "$wt" testenv.sh)" db 3 >/dev/null 2>&1 || { result "$slug" "Backend tests" fail "test databases didn't start"; return; }
    local started=$SECONDS
    (
        eval "$(bash "$(tool "$wt" testenv.sh)" test-env 3)"
        cd "$wt/tempo-backend" && swift test --build-path "$HOME_DIR/backend-build/$slug" 2>&1
    ) >"$out/backend.log"
    local code=$? secs=$((SECONDS - started))
    local line
    line="$(grep -E "Test run with [0-9]+ tests" "$out/backend.log" | tail -1)"
    if [ "$code" = 0 ]; then
        result "$slug" "Backend tests" pass "${line:-ok} (${secs}s)"
    else
        grep -E "error:|✘|failed|FAIL" "$out/backend.log" | head -40 >"$out/backend-failures.txt"
        result "$slug" "Backend tests" fail "${line:-failed} (${secs}s)" "backend-failures.txt"
    fi
    rm -rf "$HOME_DIR/backend-build/$slug"
}

run_scenarios() {
    local slug="$1" wt="$2" out="$RUN/$slug"
    if [ ! -f "$wt/Tempo/Tempo/App/ScenarioSeed.swift" ]; then
        result "$slug" "Scenarios" skip "branch has no scenarios yet"
        return
    fi
    local sim tenv
    sim="$(tool "$wt" sim.sh)" tenv="$(tool "$wt" testenv.sh)"
    (cd "$wt" && bash "$tenv" up --rebuild) >"$out/testenv.log" 2>&1 || { result "$slug" "Scenarios" fail "local test server didn't start" "testenv.log"; return; }
    local udid name crashed=() ok=()
    udid="$(bash "$sim" --dir "$wt" udid)"
    for name in $SMOKE_SCENARIOS; do
        # With --skip-ios nothing built the app yet: the first scenario does.
        local build=--no-build
        [ "$SKIP_IOS" = 1 ] && [ ${#ok[@]} -eq 0 ] && [ ${#crashed[@]} -eq 0 ] && build=""
        bash "$sim" --dir "$wt" qa ${build:+"$build"} --scenario "$name" --as "nightly-$slug-$name" >>"$out/scenarios.log" 2>&1
        sleep 12
        bash "$sim" --dir "$wt" shot "$out/scenario-$name.png" >/dev/null 2>&1
        # Capture first: under pipefail, `| grep -q` can SIGPIPE launchctl
        # and make a running app look crashed.
        local procs
        procs="$(xcrun simctl spawn "$udid" launchctl list 2>/dev/null || true)"
        if grep -q "UIKitApplication:app.tempo.Tempo.dev" <<<"$procs"; then
            ok+=("$name")
        else
            crashed+=("$name")
        fi
    done
    if [ ${#crashed[@]} -eq 0 ]; then
        result "$slug" "Scenarios" pass "${#ok[@]} launched: ${ok[*]}"
    else
        result "$slug" "Scenarios" fail "crashed: ${crashed[*]}"
    fi
}

# main last, so the shared local test server is left running main's build.
for ((t = ${#TARGETS[@]} - 1; t >= 0; t--)); do
    target="${TARGETS[$t]}"
    IFS='|' read -r slug ref title <<<"$target"
    [ -n "$ONLY" ] && [ "$ONLY" != "$slug" ] && continue
    echo "== $title ($slug)"
    mkdir -p "$RUN/$slug"
    echo "$title" >"$RUN/$slug/title"
    wt="$REPO/.claude/worktrees/nightly-$slug"
    git -C "$REPO" worktree remove --force "$wt" >/dev/null 2>&1 || true
    if ! git -C "$REPO" worktree add --quiet --detach "$wt" "$ref"; then
        result "$slug" "Checkout" fail "git worktree add failed"
        continue
    fi
    WORKTREES+=("$wt")
    git -C "$wt" rev-parse --short HEAD >"$RUN/$slug/sha"
    # Simulator work (tests then scenarios) and the backend run in parallel.
    (
        [ "$SKIP_IOS" = 1 ] || run_ios "$slug" "$wt"
        # Scenarios need the server built from THIS target; run after its tests.
        [ "$SKIP_SCENARIOS" = 1 ] || run_scenarios "$slug" "$wt"
    ) &
    sim_pid=$!
    [ "$SKIP_BACKEND" = 1 ] || run_backend "$slug" "$wt"
    wait "$sim_pid"
    bash "$(tool "$wt" sim.sh)" --dir "$wt" clean >/dev/null 2>&1 || true
    git -C "$REPO" worktree remove --force "$wt" >/dev/null 2>&1 || true
done

# ── Report ────────────────────────────────────────────────────────────────
python3 - "$RUN" "$STAMP" <<'PY'
import html, os, sys
run, stamp = sys.argv[1], sys.argv[2]
rows = [l.rstrip("\n").split("\t", 4) for l in open(os.path.join(run, "results.tsv")) if l.strip()]
targets = []
for r in rows:
    if r[0] not in targets:
        targets.append(r[0])
fails = sum(1 for r in rows if r[2] == "fail")
def read(path):
    try:
        return open(path).read()
    except OSError:
        return ""
parts = []
for t in targets:
    d = os.path.join(run, t)
    title = html.escape(read(os.path.join(d, "title")).strip() or t)
    sha = html.escape(read(os.path.join(d, "sha")).strip())
    body = []
    for slug, step, status, summary, detail in [r + [""] * (5 - len(r)) for r in rows if r[0] == t]:
        det = read(os.path.join(d, detail)).strip() if detail else ""
        body.append(f'<tr class="{status}"><td>{html.escape(step)}</td><td><span class="pill {status}">{status}</span></td>'
                    f'<td>{html.escape(summary)}' + (f"<pre>{html.escape(det)}</pre>" if det else "") + "</td></tr>")
    shots = sorted(f for f in os.listdir(d) if f.startswith("scenario-") and f.endswith(".png"))
    gallery = "".join(f'<figure><img src="{t}/{f}" loading="lazy"><figcaption>{html.escape(f[9:-4])}</figcaption></figure>' for f in shots)
    parts.append(f'<section><h2>{title} <code>{sha}</code></h2><table>{"".join(body)}</table>'
                 + (f'<div class="shots">{gallery}</div>' if gallery else "") + "</section>")
verdict = "All green" if fails == 0 else f"{fails} failing step" + ("s" if fails != 1 else "")
page = f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tempo nightly</title><style>
:root{{--bg:#fff;--fg:#111;--muted:#666;--line:#e5e5e5;--ok:#1a7f37;--bad:#cf222e;--skip:#8a6d00;--card:#fafafa}}
@media (prefers-color-scheme:dark){{:root{{--bg:#0d1117;--fg:#e6edf3;--muted:#8b949e;--line:#30363d;--ok:#3fb950;--bad:#f85149;--skip:#d29922;--card:#161b22}}}}
body{{background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,system-ui,sans-serif;margin:0 auto;max-width:1100px;padding:24px 16px}}
h1{{margin:0 0 4px}} .sub{{color:var(--muted);margin-bottom:24px}}
section{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin:16px 0}}
h2{{font-size:18px;margin:0 0 8px}} code{{color:var(--muted);font-size:13px}}
table{{width:100%;border-collapse:collapse}} td{{border-top:1px solid var(--line);padding:8px;vertical-align:top}}
td:first-child{{width:140px;font-weight:600}} td:nth-child(2){{width:70px}}
.pill{{border-radius:99px;padding:2px 8px;font-size:12px;font-weight:600;color:#fff}}
.pill.pass{{background:var(--ok)}} .pill.fail{{background:var(--bad)}} .pill.skip{{background:var(--skip)}}
pre{{white-space:pre-wrap;font-size:12px;max-height:320px;overflow:auto;background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:8px}}
.shots{{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px;margin-top:12px}}
figure{{margin:0}} img{{width:100%;border-radius:10px;border:1px solid var(--line)}} figcaption{{font-size:12px;color:var(--muted);text-align:center}}
</style></head><body><h1>{verdict}</h1><div class="sub">Tempo nightly · {stamp.replace("_", " ")} · {len(targets)} target(s)</div>
{"".join(parts) or "<p>No targets ran.</p>"}</body></html>"""
open(os.path.join(run, "report.html"), "w").write(page)
print(verdict)
PY
VERDICT="$(python3 -c 'import sys; rows=[l.split("\t") for l in open(sys.argv[1]) if l.strip()]; f=sum(r[2]=="fail" for r in rows); print("All green" if f==0 else f"{f} failing")' "$RESULTS")"

# latest.html sits next to runs/ and points into this run's folder.
sed "s#src=\"\\([^\"]*\\)/scenario-#src=\"runs/$STAMP/\\1/scenario-#g" "$RUN/report.html" >"$HOME_DIR/latest.html"
find "$HOME_DIR/runs" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} + 2>/dev/null

echo "== $VERDICT — $HOME_DIR/latest.html"
if [ -x "$NOTIFIER" ]; then
    "$NOTIFIER" -title "Tempo nightly" -message "$VERDICT · ${#TARGETS[@]} target(s)" \
        -open "file://$HOME_DIR/latest.html" -group tempo-nightly >/dev/null 2>&1 || true
else
    osascript -e "display notification \"$VERDICT\" with title \"Tempo nightly\"" || true
fi

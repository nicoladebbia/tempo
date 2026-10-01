#!/bin/bash
# testenv.sh — local Tempo test servers: one per worktree, so parallel sessions
# never restart or wipe each other's server.
#
# Postgres + Redis run in Docker (OrbStack) on their own ports; the Vapor
# backend runs natively in TEST MODE: fake Claude/USDA/Open Food Facts/
# Instacart/OpenAI/Whoop, pushes captured and delivered to the simulator,
# and /v1/test/login so each simulator signs in as its own test account.
# Only simulator runs started with `sim.sh qa --local` use it; the iPhone
# keeps talking to production.
#
# Every worktree gets its own server: the main checkout on :58080, others on
# :58081+ with their own database and Redis db (`testenv.sh servers` lists
# them). Postgres and Redis containers are shared. All commands act on the
# server of the worktree you run them from.
#
#   scripts/testenv.sh up [--rebuild] [--real-ai [--record]]   start (or reuse) the server
#   scripts/testenv.sh down [--all]                  stop this worktree's server (--all: every server + containers)
#   scripts/testenv.sh status                        what is running, AI mode
#   scripts/testenv.sh servers [--prune]             every worktree's server (--prune: stop ones whose worktree is gone)
#   scripts/testenv.sh reset                         wipe this server's test data, restart
#   scripts/testenv.sh logs [-f]                     server log
#   scripts/testenv.sh ai <fake|broken|empty|slow|error|real|replay> [slow-seconds]
#   scripts/testenv.sh pushes [name]                 pushes the server sent
#   scripts/testenv.sh url                           base URL for the app
#   scripts/testenv.sh users                         test accounts
#   scripts/testenv.sh fault add <path> <kind> [v]   break requests: error [status] | slow [s] | logout |
#                        [--count N] [--as NAME]     garbage | empty | timeout   (fault list | clear)
#   scripts/testenv.sh auth ttl <secs|off>           short access tokens → exercise silent re-login
#   scripts/testenv.sh sign-out <name>               revoke a test user's sessions
#   scripts/testenv.sh time [set <when> | +2d | -3h | reset]   move the server clock
#   scripts/testenv.sh job run <job> [--as NAME] [--force]     run a background job now
#   scripts/testenv.sh sub <name> <state> [--days N]  free | trial | active | cancelled | grace |
#                                                    billing-retry | expired | refunded (server side)
#   scripts/testenv.sh persona <name> <persona>      server half of a person with history (sim.sh
#                                                    --scenario <persona> does both halves)
#   scripts/testenv.sh shared <name>                 a user's grocery share links (open as the shopper)
#   scripts/testenv.sh db [slot]                     only the databases (for swift test); empties that slot's Redis
#   eval "$(scripts/testenv.sh test-env [slot])"     env for `swift test`: slot 1 (default) = you,
#                                                    2 = fast check, 3 = nightly — runs at the same
#                                                    time don't share a test DB or Redis db
#
# --rebuild: build the backend from THIS worktree and restart on it.
# --real-ai: real Claude calls (costs money). Key from $ANTHROPIC_API_KEY,
#            tempo-backend/.env, or ~/.tempo-testenv/anthropic.key.
# --record:  with --real-ai, save every real reply per feature
#            (~/.tempo-testenv/ai-recordings); later `ai replay` serves them free.

set -euo pipefail

STATE="${TEMPO_TESTENV_HOME:-$HOME/.tempo-testenv}"
PG=tempo-test-pg
REDIS=tempo-test-redis
PG_PORT=55432
REDIS_PORT=56379
LANES="$STATE/lanes"
MAX_LANES=40
mkdir -p "$LANES"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# Lane = one worktree's server. 0 is the main checkout (and anything outside a
# repo); worktrees get 1..MAX_LANES from $LANES/<n>/ROOT.
set_lane() {
    LANE="$1"
    if [ "$LANE" = 0 ]; then
        LDIR="$STATE" DB_NAME=tempo_local REDIS_DB=0
    else
        LDIR="$LANES/$LANE" DB_NAME="tempo_local_$LANE" REDIS_DB=$((16 + LANE))
    fi
    PORT=$((58080 + LANE))
    URL="http://127.0.0.1:$PORT"
    SERVER="$LDIR/server"
    PIDFILE="$LDIR/server.pid"
    LOG="$LDIR/server.log"
}
is_main_checkout() {
    [ -z "$ROOT" ] && return 0
    [ "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)" = "$(git -C "$ROOT" rev-parse --path-format=absolute --git-dir)" ]
}
find_lane() {
    local d
    for d in "$LANES"/*/; do
        [ -f "$d/ROOT" ] && [ "$(cat "$d/ROOT")" = "$ROOT" ] && { basename "$d"; return 0; }
    done
    return 1
}
# Needs the lock. A lane whose worktree is gone is reused (its data wiped).
alloc_lane() {
    local n d
    find_lane && return 0
    for n in $(seq 1 $MAX_LANES); do
        d="$LANES/$n"
        if [ ! -d "$d" ]; then
            mkdir -p "$d" && echo "$ROOT" >"$d/ROOT" && echo "$n"
            return 0
        fi
    done
    for n in $(seq 1 $MAX_LANES); do
        d="$LANES/$n"
        if [ ! -d "$(cat "$d/ROOT" 2>/dev/null)" ]; then
            (set_lane "$n"; stop_server)
            rm -rf "$d/server"
            echo "$ROOT" >"$d/ROOT" && touch "$d/FRESH" && echo "$n"
            return 0
        fi
    done
    die "all $MAX_LANES test servers are taken (scripts/testenv.sh servers --prune)"
}

if is_main_checkout; then
    set_lane 0
elif n="$(find_lane)"; then
    set_lane "$n"
else
    set_lane 0
    LANE=""  # this worktree has no server yet; `up` allocates one
fi
need_lane() { [ -n "$LANE" ] || die "this worktree has no test server yet (scripts/testenv.sh up)"; }

log() { echo "[testenv] $*" >&2; }
die() { echo "[testenv] ERROR: $*" >&2; exit 1; }

# One `up`/`reset`/`down` at a time across all sessions.
LOCK="$STATE/.lock"
lock() {
    local i=0
    until mkdir "$LOCK" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -gt 600 ] && die "another testenv command holds $LOCK (remove it if stale)"
        sleep 1
    done
    trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
}

server_pid() {
    [ -f "$PIDFILE" ] || return 1
    local pid
    pid="$(cat "$PIDFILE")"
    kill -0 "$pid" 2>/dev/null || return 1
    echo "$pid"
}

healthy() { curl -fsS -m 2 "$URL/health" >/dev/null 2>&1; }

need_docker() {
    command -v docker >/dev/null || die "docker not found (install OrbStack: brew install orbstack)"
    docker info >/dev/null 2>&1 || { open -ga OrbStack 2>/dev/null || true; sleep 5; docker info >/dev/null 2>&1 || die "Docker isn't running (start OrbStack)"; }
}

container_running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }

start_containers() {
    need_docker
    if ! container_running "$PG"; then
        docker rm -f "$PG" >/dev/null 2>&1 || true
        # tmpfs + fsync off: test data is disposable and this is ~10x faster.
        docker run -d --name "$PG" --restart unless-stopped -p "127.0.0.1:$PG_PORT:5432" \
            -e POSTGRES_USER=tempo -e POSTGRES_PASSWORD=tempo_dev -e POSTGRES_DB=tempo_local \
            --tmpfs /var/lib/postgresql/data postgres:16-alpine \
            -c fsync=off -c synchronous_commit=off -c full_page_writes=off -c max_connections=300 >/dev/null
    fi
    if ! container_running "$REDIS"; then
        docker rm -f "$REDIS" >/dev/null 2>&1 || true
        docker run -d --name "$REDIS" --restart unless-stopped -p "127.0.0.1:$REDIS_PORT:6379" \
            redis:7-alpine redis-server --save "" --appendonly no --databases 64 >/dev/null
    elif [ "$(docker exec "$REDIS" redis-cli CONFIG GET databases | tail -1)" -lt 64 ]; then
        # Older container with 16 dbs: worktree servers need 17+. Redis only
        # holds caches and rate limits, so recreating it loses nothing real.
        log "recreating Redis with 64 databases (one per worktree server)"
        docker rm -f "$REDIS" >/dev/null
        docker run -d --name "$REDIS" --restart unless-stopped -p "127.0.0.1:$REDIS_PORT:6379" \
            redis:7-alpine redis-server --save "" --appendonly no --databases 64 >/dev/null
        for i in $(seq 1 20); do docker exec "$REDIS" redis-cli ping >/dev/null 2>&1 && break; sleep 0.25; done
    fi
    local i
    for i in $(seq 1 60); do
        docker exec "$PG" pg_isready -U tempo -d tempo_local >/dev/null 2>&1 && break
        sleep 0.5
    done
    docker exec "$PG" pg_isready -U tempo -d tempo_local >/dev/null 2>&1 || die "Postgres didn't start"
    docker exec "$PG" psql -U tempo -d tempo_local -tAc "SELECT 1 FROM pg_database WHERE datname='tempo_test'" | grep -q 1 \
        || docker exec "$PG" createdb -U tempo tempo_test
}

# This lane's own database (lane 0 uses the container's tempo_local). The
# server migrates an empty one on start.
lane_db() {
    [ "$LANE" = 0 ] && return 0
    if [ -f "$LDIR/FRESH" ]; then
        docker exec "$PG" dropdb -U tempo --force --if-exists "$DB_NAME"
        docker exec "$REDIS" redis-cli -n "$REDIS_DB" FLUSHDB >/dev/null
        rm -f "$LDIR/FRESH"
    fi
    docker exec "$PG" psql -U tempo -d tempo_local -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 \
        || docker exec "$PG" createdb -U tempo "$DB_NAME"
}

# Test slot n → its own Postgres database and Redis db (Redis has 16).
slot_db() { if [ "$1" = 1 ]; then echo tempo_test; else echo "tempo_test_$1"; fi; }
check_slot() { [[ "$1" =~ ^([1-9]|1[0-5])$ ]] || die "slot must be 1-15"; }

# Copy the built server out of the worktree so it keeps running (and can be
# restarted) after that worktree is removed.
build_server() {
    [ -n "$ROOT" ] && [ -d "$ROOT/tempo-backend" ] || die "run --rebuild from inside a Tempo worktree"
    log "building backend from $ROOT ..."
    (cd "$ROOT/tempo-backend" && swift build --product App 2>&1 | grep -E "error:|Compiling|Build complete" | grep -v Compiling | tail -20)
    local bin
    bin="$(cd "$ROOT/tempo-backend" && swift build --product App --show-bin-path)/App"
    [ -x "$bin" ] || die "build failed (no $bin)"
    rm -rf "$SERVER.new"
    mkdir -p "$SERVER.new"
    cp "$bin" "$SERVER.new/App"
    cp -R "$ROOT/tempo-backend/Resources" "$ROOT/tempo-backend/Public" "$SERVER.new/"
    echo "$ROOT @ $(git -C "$ROOT" rev-parse --short HEAD)" >"$SERVER.new/SOURCE"
    rm -rf "$SERVER"
    mv "$SERVER.new" "$SERVER"
}

anthropic_key() {
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then echo "$ANTHROPIC_API_KEY"; return; fi
    if [ -n "$ROOT" ] && [ -f "$ROOT/tempo-backend/.env" ]; then
        local k
        k="$(grep -E '^ANTHROPIC_API_KEY=' "$ROOT/tempo-backend/.env" | tail -1 | cut -d= -f2- | tr -d '"'"'" || true)"
        [ -n "$k" ] && { echo "$k"; return; }
    fi
    [ -f "$STATE/anthropic.key" ] && { tr -d '[:space:]' <"$STATE/anthropic.key"; return; }
    return 1
}

stop_server() {
    local pid
    if pid="$(server_pid)"; then
        kill "$pid" 2>/dev/null || true
        local i
        for i in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
}

start_server() {
    local ai="fake" key="test-mode-fake-key" record=0
    if [ "${REAL_AI:-0}" = 1 ]; then
        key="$(anthropic_key)" || die "--real-ai needs a key: export ANTHROPIC_API_KEY, add it to tempo-backend/.env, or put it in $STATE/anthropic.key"
        ai="real"
        [ "${RECORD_AI:-0}" = 1 ] && record=1
    fi
    [ -x "$SERVER/App" ] || build_server
    log "starting server on $URL (AI: $ai) ..."
    : >"$LOG"
    (
        cd "$SERVER"
        env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
            TEMPO_TEST_MODE=1 TEMPO_TEST_AI="$ai" TEMPO_TEST_AI_RECORD="$record" \
            TEMPO_TEST_AI_RECORDINGS="$STATE/ai-recordings" LOG_LEVEL=info \
            DB_HOST=127.0.0.1 DB_PORT="$PG_PORT" DB_USER=tempo DB_PASSWORD=tempo_dev DB_NAME="$DB_NAME" \
            REDIS_URL="redis://127.0.0.1:$REDIS_PORT/$REDIS_DB" JWT_SECRET=tempo-test-mode-secret \
            ANTHROPIC_API_KEY="$key" OPENAI_API_KEY=test-mode INSTACART_API_KEY=test-mode USDA_API_KEY=test-mode \
            WHOOP_CLIENT_ID=test-mode WHOOP_CLIENT_SECRET=test-mode PUBLIC_BASE_URL="$URL" \
            nohup ./App serve --env development --hostname 127.0.0.1 --port "$PORT" >>"$LOG" 2>&1 &
        echo $! >"$PIDFILE"
    )
    local i
    for i in $(seq 1 120); do
        healthy && { log "ready: $URL"; return 0; }
        server_pid >/dev/null || { tail -30 "$LOG" >&2; die "server exited (log: $LOG)"; }
        sleep 0.5
    done
    tail -30 "$LOG" >&2
    die "server didn't become healthy in 60s (log: $LOG)"
}

cmd_up() {
    local rebuild=0
    REAL_AI=0 RECORD_AI=0
    for a in "$@"; do
        case "$a" in
            --rebuild) rebuild=1 ;;
            --real-ai) REAL_AI=1 ;;
            --record) RECORD_AI=1 ;;
            *) die "unknown flag $a" ;;
        esac
    done
    [ "$RECORD_AI" = 1 ] && [ "$REAL_AI" = 0 ] && die "--record needs --real-ai"
    lock
    if [ -z "$LANE" ]; then
        local n
        n="$(alloc_lane)" || exit 1
        set_lane "$n"
        log "this worktree's own test server: $URL"
    fi
    start_containers
    lane_db
    if [ "$rebuild" = 1 ] || [ ! -x "$SERVER/App" ]; then
        build_server
        stop_server
    fi
    if server_pid >/dev/null && healthy; then
        if [ "$REAL_AI" = 1 ]; then stop_server; start_server; fi
    else
        stop_server
        start_server
    fi
    cmd_status
}

cmd_down() {
    lock
    if [ "${1:-}" = "--all" ]; then
        local d
        (set_lane 0; stop_server)
        for d in "$LANES"/*/; do [ -d "$d" ] && (set_lane "$(basename "$d")"; stop_server); done
        if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
            docker rm -f "$PG" "$REDIS" >/dev/null 2>&1 || true
        fi
        log "stopped every test server and the databases (all test data gone)"
        return
    fi
    need_lane
    stop_server
    log "stopped $URL (other worktrees' servers keep running; --all stops everything)"
}

cmd_reset() {
    need_lane
    lock
    stop_server
    start_containers
    docker exec "$PG" dropdb -U tempo --force --if-exists "$DB_NAME"
    docker exec "$PG" createdb -U tempo "$DB_NAME"
    docker exec "$REDIS" redis-cli -n "$REDIS_DB" FLUSHDB >/dev/null
    start_server
    log "reset $URL: fresh database, every test account starts empty"
}

cmd_servers() {
    local prune=0 d n root state me="$LANE"
    if [ "${1:-}" = "--prune" ]; then prune=1; lock; fi
    printf '%-6s %-24s %-9s %s\n' port url state worktree
    for n in 0 $(cd "$LANES" && ls | sort -n); do
        if [ "$n" = 0 ]; then
            root="(main checkout)"
        else
            root="$(cat "$LANES/$n/ROOT" 2>/dev/null || echo '?')"
        fi
        (
            set_lane "$n"
            state=stopped
            server_pid >/dev/null && state=running
            if [ "$n" != 0 ] && [ ! -d "$root" ]; then
                if [ "$prune" = 1 ]; then
                    stop_server
                    docker exec "$PG" dropdb -U tempo --force --if-exists "$DB_NAME" 2>/dev/null || true
                    rm -rf "$LANES/$n"
                    state=pruned
                fi
                root="$root  (worktree gone)"
            fi
            if [ "$n" = "$me" ]; then root="$root  ← you"; fi
            printf '%-6s %-24s %-9s %s\n' "$PORT" "$URL" "$state" "$root"
        )
    done
}

cmd_status() {
    local pid
    if [ -n "$LANE" ] && pid="$(server_pid)" && healthy; then
        echo "server   running (pid $pid) $URL"
        echo "source   $(cat "$SERVER/SOURCE" 2>/dev/null || echo '?')"
        curl -fsS -m 3 "$URL/v1/test/status" | python3 -c '
import json, sys
s = json.load(sys.stdin)
mode, slow = s["ai_mode"], s["slow_seconds"]
extra = (" (%gs)" % slow if mode == "slow" else "") + ("" if s["real_ai_available"] else "  (no real key)")
if s.get("recording_ai"):
    extra += "  (recording real replies)"
recs = s.get("ai_recordings") or {}
if recs:
    extra += "  (%d recorded replies for %d features)" % (sum(recs.values()), len(recs))
print("AI mode  " + mode + extra)
print("pushes   %d   AI calls %d" % (s["pushes"], s["ai_calls"]))
if abs(s.get("clock_offset_seconds", 0)) >= 1:
    print("clock    moved %+.1f h (testenv.sh time reset)" % (s["clock_offset_seconds"] / 3600))
if s.get("faults"):
    print("faults   %d active (testenv.sh fault list)" % s["faults"])
if s.get("access_ttl_seconds", 900) != 900:
    print("tokens   access tokens last %d s (testenv.sh auth ttl off)" % s["access_ttl_seconds"])
print("control  " + sys.argv[1] + "/v1/test/   (open in a browser)")
' "$URL" || echo "test API not answering (built without test mode? run: testenv.sh up --rebuild)"
    else
        if [ -n "$LANE" ]; then
            echo "server   not running   (scripts/testenv.sh up)"
        else
            echo "server   none for this worktree yet   (scripts/testenv.sh up)"
        fi
    fi
    local others
    others="$(cmd_servers | awk 'NR > 1 && $3 == "running" && !/← you/' | wc -l | tr -d ' ')"
    if [ "$others" -gt 0 ]; then
        echo "others   $others other worktree server(s) running (scripts/testenv.sh servers)"
    fi
    if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
        container_running "$PG" && echo "postgres 127.0.0.1:$PG_PORT" || echo "postgres down"
        container_running "$REDIS" && echo "redis    127.0.0.1:$REDIS_PORT" || echo "redis    down"
    fi
}

cmd_ai() {
    local mode="${1:?mode: fake|broken|empty|slow|error|real|replay}" secs="${2:-}"
    healthy || die "server not running (scripts/testenv.sh up)"
    local body="{\"mode\":\"$mode\"${secs:+,\"slow_seconds\":$secs}}"
    curl -fsS -m 5 -X POST -H 'Content-Type: application/json' -d "$body" "$URL/v1/test/ai" >/dev/null \
        || die "server refused AI mode '$mode' (real needs: testenv.sh up --real-ai)"
    log "AI mode: $mode"
}

cmd_pushes() {
    healthy || die "server not running"
    curl -fsS -m 5 "$URL/v1/test/pushes${1:+?name=$1}" | python3 -c '
import json, sys
for p in json.load(sys.stdin):
    aps = json.loads(p["payload"]).get("aps", {})
    alert = aps.get("alert", {})
    print(p["created_at"][:19], p["delivery"].ljust(10), aps.get("category", "silent"), "-", alert.get("title", ""))
'
}

case "${1:-status}" in
    up) shift; cmd_up "$@" ;;
    down) shift; cmd_down "$@" ;;
    reset) cmd_reset ;;
    servers) shift; cmd_servers "$@" ;;
    status) cmd_status ;;
    logs) need_lane; if [ "${2:-}" = "-f" ]; then tail -f "$LOG"; else tail -100 "$LOG"; fi ;;
    ai) shift; need_lane; cmd_ai "$@" ;;
    fault | auth | sign-out | users | time | job | sub | persona | shared) need_lane; TEMPO_TEST_URL="$URL" python3 "$(dirname "$0")/testctl.py" "$@" ;;
    pushes) shift; need_lane; cmd_pushes "$@" ;;
    url) need_lane; echo "$URL" ;;
    db)
        slot="${2:-1}"; check_slot "$slot"
        lock; start_containers
        # Keep the database: a fresh one makes every suite's parallel
        # autoMigrate race. A new slot starts as a copy of slot 1's
        # (already migrated) when nobody is using it.
        name="$(slot_db "$slot")"
        if ! docker exec "$PG" psql -U tempo -d tempo_local -tAc "SELECT 1 FROM pg_database WHERE datname='$name'" | grep -q 1; then
            docker exec "$PG" createdb -U tempo -T tempo_test "$name" 2>/dev/null \
                || docker exec "$PG" createdb -U tempo "$name"
        fi
        # Redis starts empty every run (rate-limit counters), like CI's
        # fresh service container did.
        docker exec "$REDIS" redis-cli -n "$slot" FLUSHDB >/dev/null
        log "databases up (postgres $PG_PORT, redis $REDIS_PORT; test slot $slot emptied)" ;;
    healthy) healthy ;;
    test-env)
        slot="${2:-1}"; check_slot "$slot"
        echo "export DB_HOST=127.0.0.1 DB_PORT=$PG_PORT DB_USER=tempo DB_PASSWORD=tempo_dev DB_NAME=$(slot_db "$slot") REDIS_URL=redis://127.0.0.1:$REDIS_PORT/$slot"
        ;;
    -h | --help | help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0" ;;
    *) die "unknown command '$1' (try: scripts/testenv.sh help)" ;;
esac

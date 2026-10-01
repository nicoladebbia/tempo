#!/bin/bash
# testenv.sh — one local Tempo test server, shared by every simulator.
#
# Postgres + Redis run in Docker (OrbStack) on their own ports; the Vapor
# backend runs natively in TEST MODE: fake Claude/USDA/Open Food Facts/
# Instacart/OpenAI/Whoop, pushes captured and delivered to the simulator,
# and /v1/test/login so each simulator signs in as its own test account.
# Only simulator runs started with `sim.sh qa --local` use it; the iPhone
# keeps talking to production.
#
#   scripts/testenv.sh up [--rebuild] [--real-ai]   start (or reuse) the server
#   scripts/testenv.sh down                          stop server + containers
#   scripts/testenv.sh status                        what is running, AI mode
#   scripts/testenv.sh reset                         wipe all test data, restart
#   scripts/testenv.sh logs [-f]                     server log
#   scripts/testenv.sh ai <fake|broken|empty|slow|error|real> [slow-seconds]
#   scripts/testenv.sh pushes [name]                 pushes the server sent
#   scripts/testenv.sh url                           base URL for the app
#   scripts/testenv.sh db                            only the databases (for swift test)
#   eval "$(scripts/testenv.sh test-env)"            env for `swift test` (own DB + Redis db 1)
#
# --rebuild: build the backend from THIS worktree and restart on it.
# --real-ai: real Claude calls (costs money). Key from $ANTHROPIC_API_KEY,
#            tempo-backend/.env, or ~/.tempo-testenv/anthropic.key.

set -euo pipefail

STATE="${TEMPO_TESTENV_HOME:-$HOME/.tempo-testenv}"
PG=tempo-test-pg
REDIS=tempo-test-redis
PG_PORT=55432
REDIS_PORT=56379
PORT=58080
URL="http://127.0.0.1:$PORT"
SERVER="$STATE/server"
PIDFILE="$STATE/server.pid"
LOG="$STATE/server.log"
mkdir -p "$STATE"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

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
            redis:7-alpine redis-server --save "" --appendonly no >/dev/null
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
    local ai="fake" key="test-mode-fake-key"
    if [ "${REAL_AI:-0}" = 1 ]; then
        key="$(anthropic_key)" || die "--real-ai needs a key: export ANTHROPIC_API_KEY, add it to tempo-backend/.env, or put it in $STATE/anthropic.key"
        ai="real"
    fi
    [ -x "$SERVER/App" ] || build_server
    log "starting server on $URL (AI: $ai) ..."
    : >"$LOG"
    (
        cd "$SERVER"
        env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
            TEMPO_TEST_MODE=1 TEMPO_TEST_AI="$ai" LOG_LEVEL=info \
            DB_HOST=127.0.0.1 DB_PORT="$PG_PORT" DB_USER=tempo DB_PASSWORD=tempo_dev DB_NAME=tempo_local \
            REDIS_URL="redis://127.0.0.1:$REDIS_PORT" JWT_SECRET=tempo-test-mode-secret \
            ANTHROPIC_API_KEY="$key" OPENAI_API_KEY=test-mode INSTACART_API_KEY=test-mode USDA_API_KEY=test-mode \
            WHOOP_CLIENT_ID=test-mode WHOOP_CLIENT_SECRET=test-mode \
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
    REAL_AI=0
    for a in "$@"; do
        case "$a" in
            --rebuild) rebuild=1 ;;
            --real-ai) REAL_AI=1 ;;
            *) die "unknown flag $a" ;;
        esac
    done
    lock
    start_containers
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
    stop_server
    if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
        docker rm -f "$PG" "$REDIS" >/dev/null 2>&1 || true
    fi
    log "stopped (all test data gone)"
}

cmd_reset() {
    lock
    stop_server
    need_docker
    docker rm -f "$PG" "$REDIS" >/dev/null 2>&1 || true
    start_containers
    start_server
    log "reset: fresh database, every test account starts empty"
}

cmd_status() {
    local pid
    if pid="$(server_pid)" && healthy; then
        echo "server   running (pid $pid) $URL"
        echo "source   $(cat "$SERVER/SOURCE" 2>/dev/null || echo '?')"
        curl -fsS -m 3 "$URL/v1/test/status" | python3 -c '
import json, sys
s = json.load(sys.stdin)
mode, slow = s["ai_mode"], s["slow_seconds"]
extra = (" (%gs)" % slow if mode == "slow" else "") + ("" if s["real_ai_available"] else "  (no real key)")
print("AI mode  " + mode + extra)
print("pushes   %d   AI calls %d" % (s["pushes"], s["ai_calls"]))
' || echo "test API not answering (built without test mode? run: testenv.sh up --rebuild)"
    else
        echo "server   not running   (scripts/testenv.sh up)"
    fi
    if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
        container_running "$PG" && echo "postgres 127.0.0.1:$PG_PORT" || echo "postgres down"
        container_running "$REDIS" && echo "redis    127.0.0.1:$REDIS_PORT" || echo "redis    down"
    fi
}

cmd_ai() {
    local mode="${1:?mode: fake|broken|empty|slow|error|real}" secs="${2:-}"
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
    down) cmd_down ;;
    reset) cmd_reset ;;
    status) cmd_status ;;
    logs) if [ "${2:-}" = "-f" ]; then tail -f "$LOG"; else tail -100 "$LOG"; fi ;;
    ai) shift; cmd_ai "$@" ;;
    pushes) shift; cmd_pushes "$@" ;;
    url) echo "$URL" ;;
    db) lock; start_containers; log "databases up (postgres $PG_PORT, redis $REDIS_PORT)" ;;
    healthy) healthy ;;
    test-env)
        echo "export DB_HOST=127.0.0.1 DB_PORT=$PG_PORT DB_USER=tempo DB_PASSWORD=tempo_dev DB_NAME=tempo_test REDIS_URL=redis://127.0.0.1:$REDIS_PORT/1"
        ;;
    -h | --help | help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command '$1' (try: scripts/testenv.sh help)" ;;
esac

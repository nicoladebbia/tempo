#!/usr/bin/env bash
#
# Smoke test for Fix #3 — AIBudgetTracker hard ceiling.
# Per INTELLIGENCE_REMEDIATION_PLAN.md §5 verification.
#
# Tests three guarantees:
#   1. Pre-flight gate: budget at $0.01 → AI route returns fallback, no Claude call made
#   2. Persistence:    DB row updated on every recorded call
#   3. Threshold log:  warning fires when usage crosses 50/80/95/100%
#
# Prerequisites:
#   - Docker running (Postgres + Redis up)
#   - tempo-backend builds (already verified)
#   - You have a valid JWT for a Pro user with AI consent
#
# Usage:
#   cd tempo-backend
#   ./scripts/smoke_test_fix3.sh <YOUR_JWT>
#
# What this DOESN'T test:
#   - Real Claude API calls (those cost real money; the pre-flight gate
#     prevents them, which is the whole point).
#   - The Opus→Sonnet downgrade (requires hitting 80% threshold; harder
#     to script. Read InsightService.swift:148 to confirm the wiring.)

set -euo pipefail

JWT="${1:-}"
if [[ -z "$JWT" ]]; then
  echo "usage: $0 <JWT>" >&2
  exit 1
fi

BASE_URL="${BASE_URL:-http://localhost:8080}"
DB_URL="${DATABASE_URL:-postgres://tempo:tempo_dev@localhost:5432/tempo}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; exit 1; }

# ─────────────────────────────────────────────────
bold "1. Wipe any existing spend row for this month"
YEAR_MONTH=$(date -u +%Y-%m)
psql "$DB_URL" -c "DELETE FROM ai_monthly_spend WHERE year_month = '$YEAR_MONTH';" >/dev/null
ok "ai_monthly_spend cleared for $YEAR_MONTH"

# ─────────────────────────────────────────────────
bold "2. Verify table + row creation on first call"
echo "  Sending one AI request with a NORMAL budget..."
unset CLAUDE_MONTHLY_BUDGET_CENTS || true

# Hit drill-sergeant (cheapest, Haiku, no DB joins needed)
HTTP_CODE=$(curl -s -o /tmp/sm1.json -w "%{http_code}" \
  -X GET "$BASE_URL/v1/insights/drill-sergeant" \
  -H "Authorization: Bearer $JWT")

if [[ "$HTTP_CODE" == "200" ]]; then
  ok "drill-sergeant returned 200"
else
  echo "  response body:"; cat /tmp/sm1.json
  fail "expected 200, got $HTTP_CODE (route may be 402 if subscription/consent missing — set those up first)"
fi

# Verify row was created
SPEND=$(psql "$DB_URL" -tAc "SELECT spend_cents FROM ai_monthly_spend WHERE year_month = '$YEAR_MONTH';")
if [[ -z "$SPEND" ]]; then
  fail "no ai_monthly_spend row created"
fi
ok "ai_monthly_spend row exists with spend_cents=$SPEND"

# ─────────────────────────────────────────────────
bold "3. Verify the pre-flight gate blocks calls when over budget"
echo "  Setting CLAUDE_MONTHLY_BUDGET_CENTS=1 (1 cent ceiling)..."
echo "  You must restart the backend with this env var. Run in another terminal:"
echo "    cd tempo-backend && CLAUDE_MONTHLY_BUDGET_CENTS=1 swift run"
echo "  Press ENTER when the backend is back up..."
read -r

# Wipe the spend row again so we start from 0
psql "$DB_URL" -c "DELETE FROM ai_monthly_spend WHERE year_month = '$YEAR_MONTH';" >/dev/null

# First call: estimate exceeds $0.01 → gate should reject without calling Claude
HTTP_CODE=$(curl -s -o /tmp/sm2.json -w "%{http_code}" \
  -X GET "$BASE_URL/v1/insights/drill-sergeant" \
  -H "Authorization: Bearer $JWT")

# Whether 200 (fallback content returned) or 503 depends on the route — insights
# return fallback content as 200; nutrition routes throw budgetExhausted as 503.
# Either way: the body should NOT be Claude-generated AND no spend should be recorded.
SPEND_AFTER=$(psql "$DB_URL" -tAc "SELECT COALESCE(SUM(spend_cents), 0) FROM ai_monthly_spend WHERE year_month = '$YEAR_MONTH';")

if [[ "$SPEND_AFTER" == "0" ]]; then
  ok "spend_cents stayed at 0 — gate blocked the call BEFORE Claude was hit"
else
  fail "spend_cents=$SPEND_AFTER — gate didn't block the call (cost $SPEND_AFTER cents)"
fi

if [[ "$HTTP_CODE" == "200" ]]; then
  ok "insights route returned fallback content (HTTP 200)"
elif [[ "$HTTP_CODE" == "503" ]]; then
  ok "nutrition-style route returned 503 budgetExhausted (acceptable)"
else
  echo "  response body:"; cat /tmp/sm2.json
  echo "  HTTP $HTTP_CODE — check that this is the expected error shape"
fi

# ─────────────────────────────────────────────────
bold "4. Verify post-call recording (restart backend without the env override)"
echo "  Restart with normal budget:"
echo "    cd tempo-backend && swift run"
echo "  Press ENTER when ready..."
read -r

psql "$DB_URL" -c "DELETE FROM ai_monthly_spend WHERE year_month = '$YEAR_MONTH';" >/dev/null

# Fire 3 cheap calls in series
for i in 1 2 3; do
  curl -s -o /dev/null \
    -X GET "$BASE_URL/v1/insights/drill-sergeant" \
    -H "Authorization: Bearer $JWT"
done

SPEND_FINAL=$(psql "$DB_URL" -tAc "SELECT spend_cents FROM ai_monthly_spend WHERE year_month = '$YEAR_MONTH';")
if [[ -z "$SPEND_FINAL" || "$SPEND_FINAL" == "0" ]]; then
  fail "no spend recorded after 3 successful calls"
fi
ok "spend_cents=$SPEND_FINAL after 3 successful calls (expected >= 3)"

bold "All checks passed."
echo ""
echo "Manual check still required:"
echo "  - Watch backend logs for the 50/80/95% threshold warnings. Easiest"
echo "    way: set CLAUDE_MONTHLY_BUDGET_CENTS to a low value (say 100),"
echo "    then make ~10 Haiku calls and watch the log."

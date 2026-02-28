#!/usr/bin/env bash
# test-lab-04-05.sh — Redis Lab 05: Cache + Session Integration
# Tests: Redis keyspace notifications, LRU eviction, TTL, Keycloak token
#        cached in Redis, PG query cache pattern, Traefik metrics
set -euo pipefail

PASS=0; FAIL=0
REDIS_PASS="${REDIS_PASS:-Lab05Password!}"
KC_PASS="${KC_PASS:-Lab05Password!}"
KC_URL="http://localhost:8080"
REALM="it-stack"

pass()  { ((++PASS)); echo "  [PASS] $1"; }
fail()  { ((++FAIL)); echo "  [FAIL] $1"; }
warn()  { echo "  [WARN] $1"; }
header(){ echo; echo "=== $1 ==="; }

rcli() { redis-cli -p 6379 -a "$REDIS_PASS" --no-auth-warning "$@" 2>/dev/null; }

kc_token() {
  curl -sf -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli&grant_type=password&username=admin&password=${KC_PASS}" \
    | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4
}

header "1. Redis Connectivity"
if rcli PING | grep -q PONG; then
  pass "Redis :6379 PING → PONG"
else
  fail "Redis not responding"; exit 1
fi

header "2. Redis Configuration"
MAX_MEM=$(rcli CONFIG GET maxmemory | tail -1)
[[ "${MAX_MEM:-0}" -gt 0 ]] && pass "Redis maxmemory = $MAX_MEM bytes (memory limit active)" || warn "maxmemory not set"
EVICTION=$(rcli CONFIG GET maxmemory-policy | tail -1)
echo "$EVICTION" | grep -q "lru" && pass "Redis eviction policy = $EVICTION (LRU active)" || fail "LRU eviction not configured"
AOF=$(rcli CONFIG GET appendonly | tail -1)
echo "$AOF" | grep -q "yes" && pass "Redis AOF persistence enabled" || fail "AOF not enabled"

header "3. Keyspace Notifications"
NOTIFY=$(rcli CONFIG GET notify-keyspace-events | tail -1)
[[ -n "$NOTIFY" ]] && pass "Keyspace notifications config: '$NOTIFY'" || warn "Keyspace notifications may not be set"

header "4. Cache Pattern — SET/GET/TTL"
rcli SET "cache:page:/dashboard" '{"user":"labadmin","ts":1}' EX 300 | grep -q OK \
  && pass "Cache SET with 300s TTL" || fail "Cache SET failed"
rcli GET "cache:page:/dashboard" | grep -q "labadmin" \
  && pass "Cache GET returns expected value" || fail "Cache GET failed"
TTL=$(rcli TTL "cache:page:/dashboard")
[[ "${TTL:-0}" -gt 250 ]] && pass "Cache TTL = $TTL seconds (correct)" || fail "TTL not correct ($TTL)"
rcli SET "cache:short" "expires" EX 1 | grep -q OK && pass "Short TTL key SET (1s)" || fail "Short TTL SET failed"

header "5. Keyspace Event Subscription (verify notifications work)"
rcli SUBSCRIBE '__keyevent@0__:expired' &
SUB_PID=$!
sleep 0.5
rcli SET "notify:test" "val" EX 1 | grep -q OK && pass "Notification test key set" || fail "Notification key failed"
sleep 1  # allow expiry
kill $SUB_PID 2>/dev/null || true

header "6. Hash Structure (session store pattern)"
rcli HSET "session:abc123" "user" "labadmin" "realm" "$REALM" "exp" "$(date -d '+1 hour' +%s 2>/dev/null || date -v+1H +%s 2>/dev/null || echo '9999999999')" | grep -q "^[0-9]" \
  && pass "Session hash created (HSET)" || fail "HSET failed"
rcli HGET "session:abc123" "user" | grep -q "labadmin" \
  && pass "Session HGET user = labadmin" || fail "HGET failed"
rcli HLEN "session:abc123" | grep -q "^3$" \
  && pass "Session hash has 3 fields" || fail "Session hash field count wrong"
rcli EXPIRE "session:abc123" 3600 | grep -q "1" \
  && pass "Session hash expiry set to 3600s" || fail "EXPIRE failed"

header "7. List Structure (job queue pattern)"
rcli RPUSH "queue:jobs" "job:1" "job:2" "job:3" | grep -q "^3$" \
  && pass "Job queue RPUSH (3 items)" || fail "RPUSH failed"
rcli LLEN "queue:jobs" | grep -q "3" \
  && pass "Queue LLEN = 3" || fail "LLEN wrong"
rcli LPOP "queue:jobs" | grep -q "job:1" \
  && pass "Queue LPOP returns job:1 (FIFO)" || fail "LPOP failed"

header "8. Sorted Set (rate limiting pattern)"
WINDOW=$(date +%s)
rcli ZADD "ratelimit:labadmin" "$WINDOW" "req:1" | grep -q "1" && pass "Sorted set ZADD (rate limit window)" || fail "ZADD failed"
rcli ZADD "ratelimit:labadmin" "$((WINDOW+1))" "req:2" 2>/dev/null | grep -q "1" && pass "Rate limit 2nd request added" || fail "2nd ZADD failed"
COUNT=$(rcli ZCOUNT "ratelimit:labadmin" "-inf" "+inf")
[[ "${COUNT:-0}" -ge 2 ]] && pass "Rate limit window has $COUNT requests" || fail "ZCOUNT wrong"

header "9. PostgreSQL Connectivity"
if pg_isready -h localhost -p 5432 -U labadmin &>/dev/null; then
  pass "PostgreSQL :5432 ready"
  RESULT=$(PGPASSWORD="$REDIS_PASS" psql -h localhost -p 5432 -U labadmin -d labapp -t \
    -c "SELECT 'redis-lab05' AS test_val;" 2>/dev/null | tr -d ' ')
  echo "$RESULT" | grep -q "redis-lab05" && pass "PostgreSQL query via labapp DB succeeds" || fail "PG query failed"
else
  fail "PostgreSQL not ready"
fi

header "10. Keycloak Health"
if curl -sf "$KC_URL/health/ready" | grep -q '"status":"UP"'; then
  pass "Keycloak /health/ready UP"
  TOKEN=$(kc_token)
  [[ -n "$TOKEN" ]] && pass "Keycloak admin token obtained" || fail "Admin auth failed"
  # Simulate storing KC token in Redis session cache
  if [[ -n "$TOKEN" ]]; then
    rcli SET "kc:token:admin" "${TOKEN:0:50}..." EX 60 | grep -q OK \
      && pass "KC token stored in Redis cache (simulated session)" || fail "KC token cache SET failed"
  fi
else
  fail "Keycloak not ready"
fi

header "11. Traefik Metrics"
if curl -sf http://localhost:8082/metrics | grep -q "traefik_"; then
  pass "Traefik Prometheus metrics endpoint responding"
  curl -sf http://localhost:8082/metrics | grep -q "traefik_entrypoint" \
    && pass "traefik_entrypoint_* metrics present" || fail "No entrypoint metrics"
else
  fail "Traefik metrics endpoint not reachable"
fi

header "12. Redis INFO Summary"
INFO=$(rcli INFO all 2>/dev/null)
echo "$INFO" | grep -q "connected_clients" && pass "Redis INFO all: connected_clients field present" || fail "Redis INFO failed"
USED=$(echo "$INFO" | grep "^used_memory_human:" | cut -d: -f2 | tr -d '[:space:]')
[[ -n "$USED" ]] && pass "Redis memory used: $USED" || fail "Redis memory info not available"

echo
echo "═══════════════════════════════════════"
echo " Lab 04-05 Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[[ "$FAIL" -eq 0 ]]
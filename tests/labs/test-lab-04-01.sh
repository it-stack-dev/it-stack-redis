#!/usr/bin/env bash
# test-lab-04-01.sh — Lab 04-01: Standalone
# Module 04: Redis cache and session store
# Basic redis functionality in complete isolation
set -euo pipefail

LAB_ID="04-01"
LAB_NAME="Standalone"
MODULE="redis"
COMPOSE_FILE="docker/docker-compose.standalone.yml"
PASS=0
FAIL=0

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((++PASS)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((++FAIL)); }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN} Lab ${LAB_ID}: ${LAB_NAME}${NC}"
echo -e "${CYAN} Module: ${MODULE}${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# ── Helpers ───────────────────────────────────────────────────────────────────
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASS="Lab01Password!"

rcli() {
  redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASS}" \
    --no-auth-warning "$@" 2>/dev/null
}

rcli_check() {
  local cmd="$1" expected="$2" test_name="$3"
  local result
  # shellcheck disable=SC2086
  result=$(rcli ${cmd} 2>/dev/null)
  if [[ "${result}" == *"${expected}"* ]]; then
    pass "${test_name}"
  else
    fail "${test_name} (expected '${expected}', got '${result}')"
  fi
}

wait_for_redis() {
  local retries=30
  until redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" \
      -a "${REDIS_PASS}" --no-auth-warning PING > /dev/null 2>&1; do
    retries=$((retries - 1))
    if [[ "${retries}" -le 0 ]]; then
      fail "Redis did not become ready within 150 seconds"
      return 1
    fi
    info "Waiting for Redis... (${retries} retries left)"
    sleep 5
  done
  pass "Redis is ready"
}

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
info "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" pull --quiet 2>/dev/null || true
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans
info "Waiting for Redis to be ready..."
wait_for_redis

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
info "Phase 2: Health Checks"

if docker compose -f "${COMPOSE_FILE}" ps redis | grep -qE "running|Up|healthy"; then
  pass "Container is running"
else
  fail "Container is not running"
fi

if nc -z -w3 "${REDIS_HOST}" "${REDIS_PORT}" 2>/dev/null; then
  pass "Port ${REDIS_PORT} is open"
else
  fail "Port ${REDIS_PORT} is not reachable"
fi

HEALTH=$(docker inspect --format='{{.State.Health.Status}}' it-stack-redis-lab01 2>/dev/null)
if [[ "${HEALTH}" == "healthy" ]]; then
  pass "Docker healthcheck reports healthy"
else
  warn "Docker healthcheck: ${HEALTH}"
fi

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
info "Phase 3: Functional Tests"

# 3.1 Authentication
info "3.1 — Authentication"
rcli_check "PING" "PONG" "Authenticated PING returns PONG"

# Wrong password should be rejected
if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "wrongpass" \
    --no-auth-warning PING 2>&1 | grep -qi "WRONGPASS\|ERR\|NOAUTH"; then
  pass "Wrong password correctly rejected"
else
  fail "Wrong password was accepted (auth misconfigured)"
fi

# 3.2 String operations
info "3.2 — String operations (SET / GET / DEL / EXISTS)"
rcli_check "SET lab:test:str 'hello-it-stack'" "OK" "SET key"
rcli_check "GET lab:test:str" "hello-it-stack" "GET key returns expected value"
rcli_check "EXISTS lab:test:str" "1" "EXISTS returns 1 for set key"
rcli_check "DEL lab:test:str" "1" "DEL removes key"
rcli_check "EXISTS lab:test:str" "0" "EXISTS returns 0 after DEL"

# 3.3 Counter operations
info "3.3 — Counter operations (INCR / DECR / INCRBY)"
rcli SET lab:counter 0 > /dev/null
rcli_check "INCR lab:counter" "1" "INCR increments to 1"
rcli_check "INCR lab:counter" "2" "INCR increments to 2"
rcli_check "INCRBY lab:counter 8" "10" "INCRBY adds 8 → 10"
rcli_check "DECR lab:counter" "9" "DECR decrements to 9"
rcli DEL lab:counter > /dev/null

# 3.4 TTL / Expiry
info "3.4 — TTL and key expiry"
rcli SET lab:ttl:key tempvalue EX 5 > /dev/null
TTL=$(rcli TTL lab:ttl:key)
if [[ "${TTL}" -gt 0 ]] 2>/dev/null; then
  pass "TTL is set (${TTL}s remaining)"
else
  fail "TTL not set correctly (got: ${TTL})"
fi
rcli_check "PERSIST lab:ttl:key" "1" "PERSIST removes expiry"
rcli_check "TTL lab:ttl:key" "-1" "TTL is -1 after PERSIST (no expiry)"
rcli DEL lab:ttl:key > /dev/null

# 3.5 List operations
info "3.5 — List operations (LPUSH / RPUSH / LRANGE / LLEN)"
rcli DEL lab:list > /dev/null
rcli RPUSH lab:list alpha > /dev/null
rcli RPUSH lab:list beta > /dev/null
rcli RPUSH lab:list gamma > /dev/null
rcli_check "LLEN lab:list" "3" "LLEN returns 3"
rcli_check "LINDEX lab:list 0" "alpha" "LINDEX 0 returns alpha"
rcli_check "LPOP lab:list" "alpha" "LPOP returns alpha"
rcli_check "LLEN lab:list" "2" "LLEN is 2 after LPOP"
rcli DEL lab:list > /dev/null

# 3.6 Hash operations
info "3.6 — Hash operations (HSET / HGET / HMGET / HDEL)"
rcli HSET lab:user:1 name "Alice" email "alice@lab.local" role "admin" > /dev/null
rcli_check "HGET lab:user:1 name" "Alice" "HGET name returns Alice"
rcli_check "HGET lab:user:1 role" "admin" "HGET role returns admin"
rcli_check "HLEN lab:user:1" "3" "HLEN returns 3 fields"
rcli_check "HDEL lab:user:1 role" "1" "HDEL removes role field"
rcli_check "HEXISTS lab:user:1 role" "0" "HEXISTS returns 0 after HDEL"
rcli DEL lab:user:1 > /dev/null

# 3.7 Set operations
info "3.7 — Set operations (SADD / SISMEMBER / SUNION)"
rcli SADD lab:tags:a red green blue > /dev/null
rcli SADD lab:tags:b green yellow blue > /dev/null
rcli_check "SISMEMBER lab:tags:a green" "1" "SISMEMBER finds green in set a"
rcli_check "SISMEMBER lab:tags:a yellow" "0" "SISMEMBER confirms yellow not in set a"
rcli_check "SCARD lab:tags:a" "3" "SCARD returns 3 for set a"
UNION_COUNT=$(rcli SUNIONSTORE lab:tags:union lab:tags:a lab:tags:b)
if [[ "${UNION_COUNT}" -eq 4 ]] 2>/dev/null; then
  pass "SUNION of {r,g,b} and {g,y,b} = 4 unique"
else
  fail "SUNION expected 4, got ${UNION_COUNT}"
fi
rcli DEL lab:tags:a lab:tags:b lab:tags:union > /dev/null

# 3.8 Sorted set operations
info "3.8 — Sorted set operations (ZADD / ZRANK / ZRANGEBYSCORE)"
rcli ZADD lab:scores 100 alice 85 bob 95 carol > /dev/null
rcli_check "ZRANK lab:scores alice" "2" "ZRANK: alice is rank 2 (0-indexed, scores asc)"
rcli_check "ZSCORE lab:scores carol" "95" "ZSCORE: carol has score 95"
rcli_check "ZCARD lab:scores" "3" "ZCARD returns 3"
rcli DEL lab:scores > /dev/null

# 3.9 Pipeline performance
info "3.9 — Pipeline throughput"
START_MS=$(date +%s%3N)
for i in $(seq 1 1000); do
  rcli SET "lab:perf:${i}" "value${i}" > /dev/null
done
END_MS=$(date +%s%3N)
ELAPSED=$((END_MS - START_MS))
if [[ "${ELAPSED}" -lt 30000 ]]; then
  pass "1000 sequential SETs completed in ${ELAPSED}ms (<30s threshold)"
else
  warn "1000 SETs took ${ELAPSED}ms — may indicate slow Docker I/O"
fi
rcli FLUSHDB ASYNC > /dev/null 2>&1 || true

# 3.10 Redis INFO verification
info "3.10 — Redis INFO verification"
INFO_OUT=$(rcli INFO server)
if echo "${INFO_OUT}" | grep -q "redis_version:7"; then
  pass "Redis version is 7.x"
else
  fail "Redis version not 7.x (got: $(echo "${INFO_OUT}" | grep redis_version))"
fi

if rcli INFO persistence | grep -q "aof_enabled:1"; then
  pass "AOF persistence is enabled"
else
  fail "AOF persistence is not enabled (check docker-compose command: --appendonly yes)"
fi

MEMORY_POLICY=$(rcli CONFIG GET maxmemory-policy | tail -1)
if [[ "${MEMORY_POLICY}" == "allkeys-lru" ]]; then
  pass "maxmemory-policy is allkeys-lru"
else
  fail "maxmemory-policy unexpected: ${MEMORY_POLICY}"
fi

# ── PHASE 4: Cleanup ──────────────────────────────────────────────────────────
info "Phase 4: Cleanup"
docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
info "Cleanup complete"

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi

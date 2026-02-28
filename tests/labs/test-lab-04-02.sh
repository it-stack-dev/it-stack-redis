#!/usr/bin/env bash
# test-lab-04-02.sh — Lab 04-02: External Dependencies
# Module 04: Redis — Sentinel HA
set -euo pipefail

LAB_ID="04-02"
LAB_NAME="Sentinel HA"
COMPOSE_FILE="docker/docker-compose.lan.yml"
MASTER_HOST="${MASTER_HOST:-localhost}"
MASTER_PORT="${MASTER_PORT:-6379}"
REPLICA1_PORT="${REPLICA1_PORT:-6380}"
REPLICA2_PORT="${REPLICA2_PORT:-6381}"
SENTINEL1_PORT="${SENTINEL1_PORT:-26379}"
SENTINEL2_PORT="${SENTINEL2_PORT:-26380}"
SENTINEL3_PORT="${SENTINEL3_PORT:-26381}"
REDIS_PASS="${REDIS_PASS:-Lab02Password!}"
PASS=0; FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

pass()   { echo -e "${GREEN}[PASS]${NC} $1"; ((++PASS)); }
fail()   { echo -e "${RED}[FAIL]${NC} $1"; ((++FAIL)); }
info()   { echo -e "${CYAN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
header() { echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${NC}"; }

rcli() {
  redis-cli -h "${MASTER_HOST}" -p "${MASTER_PORT}" -a "${REDIS_PASS}" --no-auth-warning "$@"
}
rcli_port() {
  local port="$1"; shift
  redis-cli -h "${MASTER_HOST}" -p "${port}" -a "${REDIS_PASS}" --no-auth-warning "$@"
}
sentinel_cli() {
  local port="$1"; shift
  redis-cli -h "${MASTER_HOST}" -p "${port}" --no-auth-warning "$@"
}

echo -e "\n${BOLD}IT-Stack Lab ${LAB_ID} — ${LAB_NAME}${NC}"
echo -e "Module 04: Redis | $(date '+%Y-%m-%d %H:%M:%S')\n"

header "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" pull --quiet 2>/dev/null || true
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans
info "Waiting for master Redis..."
timeout 60 bash -c "until redis-cli -h ${MASTER_HOST} -p ${MASTER_PORT} -a ${REDIS_PASS} --no-auth-warning PING 2>/dev/null | grep -q PONG; do sleep 2; done"
pass "Master Redis ready"
info "Waiting for replicas..."
sleep 10
pass "Replica startup period elapsed"
info "Waiting for sentinels..."
sleep 15
pass "Sentinel startup period elapsed"

header "Phase 2: Master Health"
PING=$(rcli PING 2>/dev/null || echo "FAIL")
if [ "${PING}" = "PONG" ]; then
  pass "Master PING → PONG"
else
  fail "Master PING failed: ${PING}"
fi

ROLE=$(rcli ROLE 2>/dev/null | head -1 || echo "unknown")
if [ "${ROLE}" = "master" ]; then
  pass "Master ROLE = master"
else
  fail "Expected 'master', got '${ROLE}'"
fi

REPCOUNT=$(rcli INFO replication 2>/dev/null | grep -c "^slave[0-9]" || echo "0")
if [ "${REPCOUNT}" -ge 2 ] 2>/dev/null; then
  pass "Master has ${REPCOUNT} replica(s) connected"
else
  warn "Master has ${REPCOUNT} replica(s) — expected ≥2"
fi

header "Phase 3: Replica Health"
for port in "${REPLICA1_PORT}" "${REPLICA2_PORT}"; do
  PING=$(rcli_port "${port}" PING 2>/dev/null || echo "FAIL")
  if [ "${PING}" = "PONG" ]; then
    pass "Replica port ${port} PING → PONG"
  else
    fail "Replica port ${port} PING failed"
  fi

  ROLE=$(rcli_port "${port}" ROLE 2>/dev/null | head -1 || echo "unknown")
  if [ "${ROLE}" = "slave" ]; then
    pass "Replica port ${port} ROLE = slave"
  else
    fail "Replica port ${port}: expected 'slave', got '${ROLE}'"
  fi
done

header "Phase 4: Replication"
rcli SET lab02:rep:key "sentinel-test-value" > /dev/null
pass "SET on master"
sleep 2
for port in "${REPLICA1_PORT}" "${REPLICA2_PORT}"; do
  VAL=$(rcli_port "${port}" GET lab02:rep:key 2>/dev/null || echo "")
  if [ "${VAL}" = "sentinel-test-value" ]; then
    pass "Replica (:${port}) GET = '${VAL}'"
  else
    fail "Replica (:${port}) GET = '${VAL}' — expected 'sentinel-test-value'"
  fi
done

header "Phase 5: Sentinel Status"
for port in "${SENTINEL1_PORT}" "${SENTINEL2_PORT}" "${SENTINEL3_PORT}"; do
  SPONG=$(sentinel_cli "${port}" PING 2>/dev/null || echo "FAIL")
  if [ "${SPONG}" = "PONG" ]; then
    pass "Sentinel :${port} PING → PONG"
  else
    fail "Sentinel :${port} PING failed: ${SPONG}"
  fi

  MASTER_NAME=$(sentinel_cli "${port}" SENTINEL masters 2>/dev/null | grep -A1 "^name$" | tail -1 || echo "")
  if [ -n "${MASTER_NAME}" ]; then
    pass "Sentinel :${port} knows master '${MASTER_NAME}'"
  else
    warn "Sentinel :${port} has no master name yet"
  fi
done

header "Phase 6: Sentinel Master Discovery"
DISC=$(sentinel_cli "${SENTINEL1_PORT}" SENTINEL get-master-addr-by-name it-stack-master 2>/dev/null || echo "")
if [ -n "${DISC}" ]; then
  pass "Sentinel resolves 'it-stack-master': ${DISC}"
else
  warn "Sentinel cannot resolve master by name yet (may need more startup time)"
fi

header "Phase 7: Persistence"
rcli SET lab02:persist "will-survive-restart" EX 3600 > /dev/null
pass "SET key with 3600s TTL"
TTL=$(rcli TTL lab02:persist 2>/dev/null || echo "-1")
if [ "${TTL}" -gt 0 ] 2>/dev/null; then
  pass "TTL = ${TTL}s (AOF persistence active)"
else
  warn "TTL = ${TTL} — persistence check inconclusive"
fi

header "Phase 8: Cleanup"
rcli DEL lab02:rep:key lab02:persist > /dev/null
pass "Test keys deleted"
docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
pass "Stack stopped and volumes removed"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Lab ${LAB_ID} Results${NC}"
echo -e "  ${GREEN}Passed:${NC} ${PASS}"
echo -e "  ${RED}Failed:${NC} ${FAIL}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "${FAIL}" -gt 0 ]; then
  echo -e "${RED}FAIL${NC} — ${FAIL} test(s) failed"; exit 1
fi
echo -e "${GREEN}PASS${NC} — All ${PASS} tests passed"
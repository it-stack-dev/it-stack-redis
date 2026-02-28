#!/usr/bin/env bash
# test-lab-04-03.sh — Redis Lab 03: Advanced Features
# Tests: Redis Cluster health, slot distribution, cross-shard reads, AOF persistence
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { echo -e "${GREEN}  PASS${NC} $1"; ((++PASS)); }
fail() { echo -e "${RED}  FAIL${NC} $1"; ((++FAIL)); }
warn() { echo -e "${YELLOW}  WARN${NC} $1"; }
header() { echo -e "\n${BLUE}══ $1 ══${NC}"; }

PASS=0; FAIL=0
REDIS_PASS="${REDIS_PASS:-Lab03Password!}"

rcli() { redis-cli -p 7001 -a "$REDIS_PASS" --no-auth-warning "$@" 2>/dev/null; }
rcli_port() { local port=$1; shift; redis-cli -p "$port" -a "$REDIS_PASS" --no-auth-warning "$@" 2>/dev/null; }
rcli_cluster() { redis-cli -c -p 7001 -a "$REDIS_PASS" --no-auth-warning "$@" 2>/dev/null; }

# ── 1. Cluster state ─────────────────────────────────────────────────────────
header "1. Cluster State"
cluster_state=$(rcli CLUSTER INFO | grep "^cluster_state:" | cut -d: -f2 | tr -d '[:space:]')
if [[ "$cluster_state" == "ok" ]]; then pass "cluster_state: ok"
else fail "cluster_state: $cluster_state (expected ok)"; fi

# ── 2. Slot coverage ─────────────────────────────────────────────────────────
header "2. Slot Coverage"
slots_assigned=$(rcli CLUSTER INFO | grep "^cluster_slots_assigned:" | cut -d: -f2 | tr -d '[:space:]')
if [[ "$slots_assigned" == "16384" ]]; then pass "cluster_slots_assigned: 16384 (full coverage)"
else fail "cluster_slots_assigned: $slots_assigned (expected 16384)"; fi

slots_fail=$(rcli CLUSTER INFO | grep "^cluster_slots_fail:" | cut -d: -f2 | tr -d '[:space:]')
if [[ "$slots_fail" == "0" ]]; then pass "cluster_slots_fail: 0"
else fail "cluster_slots_fail: $slots_fail (expected 0)"; fi

# ── 3. Node count ────────────────────────────────────────────────────────────
header "3. Node Count"
node_count=$(rcli CLUSTER NODES | grep -v "^$" | wc -l | tr -d '[:space:]')
if [[ "$node_count" -eq 6 ]]; then pass "CLUSTER NODES: 6 nodes total"
else fail "CLUSTER NODES: $node_count nodes (expected 6)"; fi

primary_count=$(rcli CLUSTER NODES | grep "master" | wc -l | tr -d '[:space:]')
if [[ "$primary_count" -eq 3 ]]; then pass "3 primary (master) nodes"
else fail "$primary_count primary nodes (expected 3)"; fi

replica_count=$(rcli CLUSTER NODES | grep "slave" | wc -l | tr -d '[:space:]')
if [[ "$replica_count" -eq 3 ]]; then pass "3 replica (slave) nodes"
else fail "$replica_count replica nodes (expected 3)"; fi

# ── 4. PING all 6 nodes ──────────────────────────────────────────────────────
header "4. Node Connectivity"
for port in 7001 7002 7003 7004 7005 7006; do
  pong=$(rcli_port "$port" PING)
  if [[ "$pong" == "PONG" ]]; then pass "Node :$port PING → PONG"
  else fail "Node :$port PING failed (got: '$pong')"; fi
done

# ── 5. Cross-shard write and read (-c follows MOVED) ────────────────────────
header "5. Distributed Data Operations"
rcli_cluster SET "lab03:user:1" "alice" >/dev/null
rcli_cluster SET "lab03:user:2" "bob" >/dev/null
rcli_cluster SET "lab03:user:3" "carol" >/dev/null

val1=$(rcli_cluster GET "lab03:user:1")
val2=$(rcli_cluster GET "lab03:user:2")
val3=$(rcli_cluster GET "lab03:user:3")

if [[ "$val1" == "alice" ]]; then pass "GET lab03:user:1 = alice (cross-shard)"
else fail "GET lab03:user:1 = '$val1' (expected alice)"; fi
if [[ "$val2" == "bob" ]]; then pass "GET lab03:user:2 = bob"
else fail "GET lab03:user:2 = '$val2' (expected bob)"; fi
if [[ "$val3" == "carol" ]]; then pass "GET lab03:user:3 = carol"
else fail "GET lab03:user:3 = '$val3' (expected carol)"; fi

# ── 6. Hash tags keep related keys on same shard ─────────────────────────────
header "6. Hash Tag Slot Affinity"
rcli_cluster SET "{session}:auth" "jwt-token" >/dev/null
rcli_cluster SET "{session}:data" "user-payload" >/dev/null
auth_val=$(rcli_cluster GET "{session}:auth")
data_val=$(rcli_cluster GET "{session}:data")
if [[ "$auth_val" == "jwt-token" && "$data_val" == "user-payload" ]]; then
  pass "Hash tag keys {session}:* co-located and accessible"
else fail "Hash tag keys not accessible properly"; fi

slot=$(rcli CLUSTER KEYSLOT "{session}")
if [[ "$slot" =~ ^[0-9]+$ && "$slot" -ge 0 && "$slot" -le 16383 ]]; then
  pass "CLUSTER KEYSLOT {session} = $slot (valid slot)"
else fail "CLUSTER KEYSLOT returned invalid slot: '$slot'"; fi

# ── 7. AOF persistence ───────────────────────────────────────────────────────
header "7. AOF Persistence"
aof_status=$(rcli_port 7001 CONFIG GET appendonly | tail -1)
if [[ "$aof_status" == "yes" ]]; then pass "AOF enabled on node :7001 (appendonly=yes)"
else fail "AOF not enabled on :7001 (got: '$aof_status')"; fi

aof_status2=$(rcli_port 7004 CONFIG GET appendonly | tail -1)
if [[ "$aof_status2" == "yes" ]]; then pass "AOF enabled on node :7004 (appendonly=yes)"
else fail "AOF not enabled on :7004 (got: '$aof_status2')"; fi

# ── 8. Cluster info metrics ──────────────────────────────────────────────────
header "8. Cluster Health Metrics"
known_nodes=$(rcli CLUSTER INFO | grep "^cluster_known_nodes:" | cut -d: -f2 | tr -d '[:space:]')
if [[ "$known_nodes" -eq 6 ]]; then pass "cluster_known_nodes: 6"
else fail "cluster_known_nodes: $known_nodes (expected 6)"; fi

cluster_size=$(rcli CLUSTER INFO | grep "^cluster_size:" | cut -d: -f2 | tr -d '[:space:]')
if [[ "$cluster_size" -eq 3 ]]; then pass "cluster_size: 3 (3 primary shards)"
else fail "cluster_size: $cluster_size (expected 3)"; fi

# ── Cleanup ──────────────────────────────────────────────────────────────────
rcli_cluster DEL "lab03:user:1" "lab03:user:2" "lab03:user:3" >/dev/null 2>&1 || true

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo -e "  Tests passed: ${GREEN}${PASS}${NC}"
echo -e "  Tests failed: ${RED}${FAIL}${NC}"
echo "══════════════════════════════════════════"
[[ $FAIL -eq 0 ]] && echo -e "${GREEN}Lab 04-03 PASSED${NC}" || { echo -e "${RED}Lab 04-03 FAILED${NC}"; exit 1; }

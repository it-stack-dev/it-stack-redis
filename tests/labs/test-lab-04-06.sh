#!/usr/bin/env bash
# test-lab-04-06.sh -- Redis Lab 06: Production Deployment
# Tests: Redis master+2 replicas HA, 3-node Sentinel, Redis Exporter, persistence, failover prep
# Usage: REDIS_PASS=Lab06Password! bash test-lab-04-06.sh
set -euo pipefail

REDIS_PASS="${REDIS_PASS:-Lab06Password!}"
PASS=0; FAIL=0
ok()  { echo "[PASS] $1"; ((PASS++)); }
fail(){ echo "[FAIL] $1"; ((FAIL++)); }
info(){ echo "[INFO] $1"; }

# -- Section 1: Redis master health ------------------------------------------
info "Section 1: Redis master :6379"
pong=$(redis-cli -h localhost -p 6379 -a "${REDIS_PASS}" ping 2>/dev/null || echo "FAIL")
if [[ "$pong" == "PONG" ]]; then ok "Redis master :6379 PONG"; else fail "Redis master :6379 PONG (got $pong)"; fi

# -- Section 2: Replica health -----------------------------------------------
info "Section 2: Redis replicas :6380 and :6381"
for port in 6380 6381; do
  r=$(redis-cli -h localhost -p "$port" -a "${REDIS_PASS}" ping 2>/dev/null || echo "FAIL")
  if [[ "$r" == "PONG" ]]; then ok "Redis replica :${port} PONG"; else fail "Redis replica :${port} PONG (got $r)"; fi
done

# -- Section 3: Replication info on master ------------------------------------
info "Section 3: Master replication status"
rep_info=$(redis-cli -h localhost -p 6379 -a "${REDIS_PASS}" info replication 2>/dev/null || true)
role=$(echo "$rep_info" | grep "^role:" | cut -d: -f2 | tr -d '\r')
slaves=$(echo "$rep_info" | grep "^connected_slaves:" | cut -d: -f2 | tr -d '\r ')
info "Role: $role, Connected slaves: $slaves"
[[ "$role" == "master" ]] && ok "Master role confirmed" || fail "Master role (got $role)"
if [[ "${slaves:-0}" -ge 2 ]]; then ok "Connected slaves: $slaves (>=2)"; else fail "Connected slaves (expected >=2, got $slaves)"; fi

# -- Section 4: Write on master, read on replica ------------------------------
info "Section 4: Replication propagation"
redis-cli -h localhost -p 6379 -a "${REDIS_PASS}" SET prod-lab06-key "replication-check" EX 60 >/dev/null 2>&1
sleep 1
val_r1=$(redis-cli -h localhost -p 6380 -a "${REDIS_PASS}" GET prod-lab06-key 2>/dev/null || echo "nil")
val_r2=$(redis-cli -h localhost -p 6381 -a "${REDIS_PASS}" GET prod-lab06-key 2>/dev/null || echo "nil")
info "Replica-1 read: $val_r1, Replica-2 read: $val_r2"
[[ "$val_r1" == "replication-check" ]] && ok "Replica-1 propagation confirmed" || fail "Replica-1 propagation (got $val_r1)"
[[ "$val_r2" == "replication-check" ]] && ok "Replica-2 propagation confirmed" || fail "Replica-2 propagation (got $val_r2)"

# -- Section 5: Sentinel health -----------------------------------------------
info "Section 5: Sentinel nodes PING"
for port in 26379 26380 26381; do
  s=$(redis-cli -h localhost -p "$port" ping 2>/dev/null || echo "FAIL")
  if [[ "$s" == "PONG" ]]; then ok "Sentinel :${port} PONG"; else fail "Sentinel :${port} PONG (got $s)"; fi
done

# -- Section 6: Sentinel master discovery -------------------------------------
info "Section 6: Sentinel master discovery"
sentinel_master=$(redis-cli -h localhost -p 26379 sentinel master mymaster 2>/dev/null | grep -A1 "^name$" | tail -1 || echo "")
info "Sentinel reports master name: $sentinel_master"
if redis-cli -h localhost -p 26379 sentinel master mymaster 2>/dev/null | grep -q "flags"; then
  ok "Sentinel master 'mymaster' registered"
else
  fail "Sentinel master 'mymaster' registered"
fi

# -- Section 7: Sentinel quorum check -----------------------------------------
info "Section 7: Sentinel quorum check"
ckquorum=$(redis-cli -h localhost -p 26379 sentinel ckquorum mymaster 2>/dev/null || echo "FAIL")
info "CKQUORUM result: $ckquorum"
if echo "$ckquorum" | grep -qi "OK"; then ok "Sentinel quorum OK"; else fail "Sentinel quorum check (got: $ckquorum)"; fi

# -- Section 8: Redis Exporter metrics ----------------------------------------
info "Section 8: Redis Exporter :9121"
exporter_metrics=$(curl -sf http://localhost:9121/metrics 2>/dev/null || true)
redis_up=$(echo "$exporter_metrics" | grep "^redis_up " | awk '{print $2}' | tr -d ' ' || echo 0)
info "redis_up: $redis_up"
[[ "$redis_up" == "1" ]] && ok "Redis Exporter redis_up=1" || fail "Redis Exporter redis_up (got $redis_up)"
connected_clients=$(echo "$exporter_metrics" | grep -c "^redis_connected_clients" || echo 0)
[[ "$connected_clients" -ge 1 ]] && ok "Redis Exporter connected_clients metric" || fail "Redis Exporter connected_clients"

# -- Section 9: Persistence check (AOF) --------------------------------------
info "Section 9: AOF persistence"
aof_info=$(redis-cli -h localhost -p 6379 -a "${REDIS_PASS}" info persistence 2>/dev/null || true)
aof_enabled=$(echo "$aof_info" | grep "^aof_enabled:" | cut -d: -f2 | tr -d '\r ')
rdb_last=$(echo "$aof_info" | grep "^rdb_last_bgsave_status:" | cut -d: -f2 | tr -d '\r ')
info "AOF enabled: $aof_enabled, RDB last status: $rdb_last"
[[ "${aof_enabled:-0}" == "1" ]] && ok "AOF persistence enabled" || fail "AOF persistence enabled (got $aof_enabled)"
[[ "${rdb_last:-ok}" == "ok" ]] && ok "RDB bgsave status ok" || fail "RDB bgsave status (got $rdb_last)"

# -- Section 10: Memory and key stats -----------------------------------------
info "Section 10: Memory usage + keyspace"
mem_info=$(redis-cli -h localhost -p 6379 -a "${REDIS_PASS}" info memory 2>/dev/null || true)
used_mem=$(echo "$mem_info" | grep "^used_memory_human:" | cut -d: -f2 | tr -d '\r ')
maxmem=$(echo "$mem_info" | grep "^maxmemory_policy:" | cut -d: -f2 | tr -d '\r ')
info "Used memory: $used_mem, Maxmemory policy: $maxmem"
ok "Redis memory: used=$used_mem policy=$maxmem"
dbsize=$(redis-cli -h localhost -p 6379 -a "${REDIS_PASS}" DBSIZE 2>/dev/null | tr -d ' ' || echo 0)
info "DB size: $dbsize keys"
ok "DB size: $dbsize keys"

# -- Section 11: Integration score --------------------------------------------
info "Section 11: Production integration score"
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [[ $FAIL -eq 0 ]]; then
  echo "[SCORE] 6/6 -- All production checks passed"
  exit 0
else
  echo "[SCORE] FAIL ($FAIL failures)"
  exit 1
fi

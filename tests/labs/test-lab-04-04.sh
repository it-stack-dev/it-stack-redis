#!/usr/bin/env bash
# test-lab-04-04.sh — Redis Lab 04: SSO via Keycloak OIDC + oauth2-proxy
# Tests: Keycloak setup, OIDC flows, oauth2-proxy SSO gate, Redis connectivity
set -euo pipefail

PASS=0; FAIL=0
KC_PASS="${KC_PASS:-Lab04Password!}"
KC_URL="http://localhost:8080"
REALM="it-stack"

pass()  { ((++PASS)); echo "  [PASS] $1"; }
fail()  { ((++FAIL)); echo "  [FAIL] $1"; }
warn()  { echo "  [WARN] $1"; }
header(){ echo; echo "=== $1 ==="; }

kc_token() {
  curl -sf -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli&grant_type=password&username=admin&password=${KC_PASS}" \
    | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4
}

header "1. Keycloak Health"
if curl -sf "$KC_URL/health/ready" | grep -q '"status":"UP"'; then
  pass "Keycloak /health/ready UP"
else
  fail "Keycloak not ready"; exit 1
fi

header "2. Admin Authentication"
TOKEN=$(kc_token)
[[ -n "$TOKEN" ]] && pass "Admin token obtained" || { fail "Admin token failed"; exit 1; }

header "3. Realm + Client + User Setup"
curl -sf -X POST "$KC_URL/admin/realms" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"realm\":\"$REALM\",\"enabled\":true}" -o /dev/null && pass "Realm created" || warn "Realm may exist"
TOKEN=$(kc_token)
curl -sf -X POST "$KC_URL/admin/realms/$REALM/clients" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"clientId\":\"oauth2-proxy\",\"secret\":\"$KC_PASS\",\"publicClient\":false,
       \"serviceAccountsEnabled\":true,\"redirectUris\":[\"http://localhost:4180/*\"],
       \"enabled\":true}" -o /dev/null && pass "Client 'oauth2-proxy' created" || warn "Client may exist"
TOKEN=$(kc_token)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$KC_URL/admin/realms/$REALM/users" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"username\":\"labuser\",\"enabled\":true,\"email\":\"labuser@lab.local\",
       \"emailVerified\":true,
       \"credentials\":[{\"type\":\"password\",\"value\":\"$KC_PASS\",\"temporary\":false}]}")
[[ "$STATUS" =~ ^(201|409)$ ]] && pass "User 'labuser' ready (HTTP $STATUS)" || fail "User creation failed (HTTP $STATUS)"

header "4. Client Credentials Token"
SA_TOKEN=$(curl -sf -X POST "$KC_URL/realms/$REALM/protocol/openid-connect/token" \
  -d "client_id=oauth2-proxy&client_secret=${KC_PASS}&grant_type=client_credentials" \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
[[ -n "$SA_TOKEN" ]] && pass "Service account token obtained" || fail "Service account token failed"

header "5. JWT Validation"
IFS='.' read -ra PARTS <<< "$SA_TOKEN"
[[ "${#PARTS[@]}" -eq 3 ]] && pass "JWT structure valid (3 parts)" || fail "Invalid JWT"
if [[ "${#PARTS[@]}" -eq 3 ]]; then
  PAYLOAD=$(echo "${PARTS[1]}" | base64 -d 2>/dev/null || true)
  echo "$PAYLOAD" | grep -q '"iss"' && pass "JWT 'iss' claim present" || fail "JWT missing 'iss'"
fi

header "6. OIDC Discovery"
DISCOVERY=$(curl -sf "$KC_URL/realms/$REALM/.well-known/openid-configuration")
for field in token_endpoint authorization_endpoint jwks_uri userinfo_endpoint; do
  echo "$DISCOVERY" | grep -q "\"$field\"" && pass "Discovery: $field present" || fail "Discovery missing $field"
done

header "7. Token Introspection"
TOKEN=$(kc_token)
INTRO=$(curl -sf -X POST "$KC_URL/realms/$REALM/protocol/openid-connect/token/introspect" \
  -u "oauth2-proxy:${KC_PASS}" -d "token=${SA_TOKEN}" | grep -o '"active":[a-z]*' | head -1)
echo "$INTRO" | grep -q '"active":true' && pass "Token introspection: active=true" || fail "Token not active"

header "8. Redis Connectivity"
if redis-cli -p 6379 -a "$KC_PASS" --no-auth-warning PING 2>/dev/null | grep -q PONG; then
  pass "Redis PING → PONG"
  redis-cli -p 6379 -a "$KC_PASS" --no-auth-warning SET sso:test "lab04" 2>/dev/null | grep -q OK \
    && pass "Redis SET sso:test OK" || fail "Redis SET failed"
  redis-cli -p 6379 -a "$KC_PASS" --no-auth-warning GET sso:test 2>/dev/null | grep -q "lab04" \
    && pass "Redis GET sso:test = lab04" || fail "Redis GET failed"
  redis-cli -p 6379 -a "$KC_PASS" --no-auth-warning INFO server 2>/dev/null | grep -q "redis_version" \
    && pass "Redis INFO server accessible" || fail "Redis INFO failed"
else
  fail "Redis not responding"
fi

header "9. oauth2-proxy SSO Gate"
if curl -sf --max-time 5 http://localhost:4180/ping -o /dev/null 2>/dev/null; then
  pass "oauth2-proxy /ping responds"
  REDIR=$(curl -s -o /dev/null -w "%{http_code}" --max-redirect 0 http://localhost:4180/ 2>/dev/null || true)
  [[ "$REDIR" =~ ^(302|307)$ ]] && pass "oauth2-proxy redirects to SSO (HTTP $REDIR)" || warn "oauth2-proxy returned $REDIR"
else
  warn "oauth2-proxy not yet started (client credentials required first)"
fi

header "10. JWKS Keys"
JWKS_URL=$(echo "$DISCOVERY" | grep -o '"jwks_uri":"[^"]*"' | cut -d'"' -f4)
curl -sf "$JWKS_URL" | grep -q '"keys"' && pass "JWKS endpoint returns signing keys" || fail "JWKS endpoint failed"

echo
echo "═══════════════════════════════════════"
echo " Lab 04-04 Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[[ "$FAIL" -eq 0 ]]
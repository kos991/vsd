#!/usr/bin/env bash
# daed-provision.sh — load rendered dns/routing from config.dae into daed's
# wing.db via the GraphQL API. daed does NOT read config.dae from disk; the -c
# directory only holds wing.db and config is served from the DB. See
# docs/superpowers/specs/2026-06-23-vyos-daed-smartdns-mosdns-design.md (section D).
#
# First-boot strategy: import-and-select, do NOT run. The committed routing ends
# in `fallback: proxy`; a real run fails with no node in the proxy group, and
# the appliance ships without a node. So we create+select config/dns/routing and
# stop. daed forwards nothing until the user adds a node in the :2023 dashboard and
# triggers a run there (matches the README "overseas blackholed until node added").
#
# Idempotent: guarded by numberUsers and a sentinel file; safe to re-run each boot.
set -u

ENDPOINT="http://127.0.0.1:2023/graphql"
BASE="/config/custom-services"
CONFIG_DAE="${BASE}/daed/config.dae"
CRED_FILE="${BASE}/daed/admin-credentials"
SENTINEL="${BASE}/daed/.provisioned"
LOG="/var/log/daed-provision.log"
ADMIN_USER="admin"

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*" | tee -a "$LOG" >&2; }

if [ -f "$SENTINEL" ]; then
  log "Already provisioned (sentinel present); nothing to do."
  exit 0
fi

for dep in curl jq awk; do
  command -v "$dep" >/dev/null 2>&1 || { log "Missing dependency: $dep"; exit 1; }
done

# gql QUERY [VARIABLES_JSON] [TOKEN] -> prints response body; returns nonzero on
# transport error or a GraphQL "errors" array.
gql() {
  q="$1"; vars="${2:-null}"; token="${3:-}"
  body="$(jq -n --arg q "$q" --argjson v "$vars" '{query:$q, variables:$v}')"
  if [ -n "$token" ]; then
    resp="$(curl -fsS -m 15 -H 'Content-Type: application/json' \
      -H "Authorization: Bearer ${token}" -d "$body" "$ENDPOINT" 2>>"$LOG")"
  else
    resp="$(curl -fsS -m 15 -H 'Content-Type: application/json' \
      -d "$body" "$ENDPOINT" 2>>"$LOG")"
  fi
  [ -z "$resp" ] && return 1
  if echo "$resp" | jq -e '.errors' >/dev/null 2>&1; then
    log "GraphQL error: $(echo "$resp" | jq -c '.errors')"
    echo "$resp"
    return 1
  fi
  echo "$resp"
}

# --- 1. Wait for the API (healthCheck returns 1) -----------------------------
ready=""
for _ in $(seq 1 60); do
  if gql 'query{healthCheck}' >/dev/null 2>&1; then ready=1; break; fi
  sleep 2
done
if [ -z "$ready" ]; then
  log "daed GraphQL API not reachable at ${ENDPOINT} after 120s; aborting."
  exit 1
fi

# --- 2. Obtain a token (idempotent createUser) -------------------------------
num="$(gql 'query{numberUsers}' | jq -r '.data.numberUsers // empty')"
TOKEN=""
if [ "${num:-0}" = "0" ]; then
  # Generate a strong random admin password (>=6 chars, has letters + digits).
  PASS="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)"
  case "$PASS" in *[0-9]*[A-Za-z]*|*[A-Za-z]*[0-9]*) : ;; *) PASS="${PASS}a1" ;; esac
  resp="$(gql 'mutation($u:String!,$p:String!){createUser(username:$u,password:$p)}' \
    "$(jq -n --arg u "$ADMIN_USER" --arg p "$PASS" '{u:$u,p:$p}')")" || {
      log "createUser failed; aborting."; exit 1; }
  TOKEN="$(echo "$resp" | jq -r '.data.createUser // empty')"
  if [ -n "$TOKEN" ]; then
    umask 077
    {
      echo "# daed dashboard admin credentials (auto-generated at first boot)."
      echo "# Change the password after logging in at http://<gateway-ip>:2023"
      echo "username=${ADMIN_USER}"
      echo "password=${PASS}"
    } >"$CRED_FILE"
    chmod 600 "$CRED_FILE"
    log "Created daed admin user '${ADMIN_USER}'; credentials written to ${CRED_FILE}."
  fi
else
  log "A daed user already exists; cannot derive token non-interactively. Skipping import."
  touch "$SENTINEL"
  exit 0
fi

if [ -z "$TOKEN" ]; then log "Empty token; aborting."; exit 1; fi

# --- 3. Extract dns{} and routing{} bodies from the rendered config.dae ------
# daed's createDns/createRouting take the text INSIDE the block (no wrapper).
# config.dae has a nested routing inside dns{}, so use brace-depth tracking and
# take only the top-level dns{...} and routing{...} blocks.
extract_block() {
  # $1 = keyword (dns|routing); prints inner text of the FIRST TOP-LEVEL block.
  # Tracks brace depth across ALL lines so a nested block of the same name
  # (e.g. the routing{} inside dns{}) is never mistaken for the top-level one.
  awk -v kw="$1" '
    BEGIN { depth=0; grabbing=0 }
    {
      line=$0
      # Match the keyword only at top level (depth 0) and before this line opens it.
      if (grabbing==0 && depth==0 && $1==kw && index($0,"{")>0) {
        grabbing=1
        sub(/^[^{]*\{/, "", line)   # drop "kw {"
        depth = 1
        # account for any further braces on the same line
        n=gsub(/\{/,"{",line); m=gsub(/\}/,"}",line); depth += n - m
        if (depth<=0) { sub(/\}[^}]*$/, "", line); if (length(line)>0) print line; exit }
        if (length(line)>0) print line
        next
      }
      if (grabbing==1) {
        n=gsub(/\{/,"{",line); m=gsub(/\}/,"}",line)
        depth += n - m
        if (depth<=0) { sub(/\}[^}]*$/, "", line); if (length(line)>0) print line; exit }
        print line
        next
      }
      # Not grabbing: still track global brace depth so nested blocks are skipped.
      n=gsub(/\{/,"{",line); m=gsub(/\}/,"}",line)
      depth += n - m
    }
  ' "$CONFIG_DAE"
}

DNS_BODY="$(extract_block dns)"
ROUTING_BODY="$(extract_block routing)"
if [ -z "$DNS_BODY" ] || [ -z "$ROUTING_BODY" ]; then
  log "Failed to extract dns/routing bodies from ${CONFIG_DAE}; aborting."
  exit 1
fi

# --- 4. Create config + dns + routing ----------------------------------------
CFG="$(gql 'mutation{createConfig(name:"default"){id}}' null "$TOKEN" \
  | jq -r '.data.createConfig.id // empty')"
DNS="$(gql 'mutation($d:String){createDns(name:"default",dns:$d){id}}' \
  "$(jq -n --arg d "$DNS_BODY" '{d:$d}')" "$TOKEN" \
  | jq -r '.data.createDns.id // empty')"
RT="$(gql 'mutation($r:String){createRouting(name:"default",routing:$r){id}}' \
  "$(jq -n --arg r "$ROUTING_BODY" '{r:$r}')" "$TOKEN" \
  | jq -r '.data.createRouting.id // empty')"

if [ -z "$CFG" ] || [ -z "$DNS" ] || [ -z "$RT" ]; then
  log "create config/dns/routing failed (cfg=$CFG dns=$DNS rt=$RT); aborting."
  exit 1
fi

# --- 5. Select all three (do NOT run: proxy group has no node yet) -----------
gql 'mutation($id:ID!){selectConfig(id:$id)}'  "$(jq -n --arg id "$CFG" '{id:$id}')" "$TOKEN" >/dev/null || true
gql 'mutation($id:ID!){selectDns(id:$id)}'     "$(jq -n --arg id "$DNS" '{id:$id}')" "$TOKEN" >/dev/null || true
gql 'mutation($id:ID!){selectRouting(id:$id)}' "$(jq -n --arg id "$RT"  '{id:$id}')" "$TOKEN" >/dev/null || true

touch "$SENTINEL"
log "Provisioned and selected config/dns/routing. NOT running: add a proxy node at"
log "http://<gateway-ip>:2023 and apply there to start forwarding overseas traffic."
exit 0

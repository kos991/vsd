#!/usr/bin/env bash
# daed-provision.sh - load rendered dns/routing from config.dae into daed's
# wing.db via the GraphQL API. daed does NOT read config.dae from disk; the -c
# directory only holds wing.db and config is served from the DB. See
# docs/superpowers/specs/2026-06-23-vyos-daed-smartdns-mosdns-design.md (section D).
#
# First-boot strategy: create/select DNS and routing, then only run when the
# daed "proxy" group already has at least one node. The appliance ships without a
# node, so first boot imports config but keeps overseas traffic inert.
#
# Idempotent: safe to re-run each boot. Existing selected DNS/routing rows are
# updated in place so late-bound LAN IP changes reach wing.db.
set -eu

ENDPOINT="http://127.0.0.1:2023/graphql"
BASE="/config/custom-services"
CONFIG_DAE="${BASE}/daed/config.dae"
CRED_FILE="${BASE}/daed/admin-credentials"
SENTINEL="${BASE}/daed/.provisioned"
LOG="/var/log/daed-provision.log"
ADMIN_USER="admin"

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*" | tee -a "$LOG" >&2; }

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

# --- 2. Obtain a token (idempotent createUser/login) -------------------------
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
  if [ -f "$CRED_FILE" ]; then
    ADMIN_USER="$(awk -F= '$1=="username"{print $2; exit}' "$CRED_FILE")"
    PASS="$(awk -F= '$1=="password"{print $2; exit}' "$CRED_FILE")"
    if [ -z "${ADMIN_USER}" ] || [ -z "${PASS}" ]; then
      log "Credentials file ${CRED_FILE} is malformed; aborting."
      exit 1
    fi
    TOKEN="$(gql 'query($u:String!,$p:String!){token(username:$u,password:$p)}' \
      "$(jq -n --arg u "$ADMIN_USER" --arg p "$PASS" '{u:$u,p:$p}')" \
      | jq -r '.data.token // empty')"
    log "Logged in to daed GraphQL as '${ADMIN_USER}'."
  else
    log "A daed user already exists but ${CRED_FILE} is missing; refusing to update wing.db."
    log "Log in manually or restore the credential file, then re-run this script."
    exit 1
  fi
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

# --- 4. Ensure a selected global config exists -------------------------------
CFG="$(gql 'query{configs{id selected}}' null "$TOKEN" \
  | jq -r '.data.configs[]? | select(.selected == true) | .id' | head -n 1)"
if [ -z "$CFG" ]; then
  CFG="$(gql 'mutation{createConfig(name:"default"){id}}' null "$TOKEN" \
    | jq -r '.data.createConfig.id // empty')"
  if [ -z "$CFG" ]; then
    log "createConfig failed; aborting."
    exit 1
  fi
  gql 'mutation($id:ID!){selectConfig(id:$id)}' \
    "$(jq -n --arg id "$CFG" '{id:$id}')" "$TOKEN" >/dev/null
  log "Created and selected default global config (${CFG})."
fi

# --- 5. Update selected DNS/routing, or create+select when absent ------------
DNS="$(gql 'query{dnss{id selected}}' null "$TOKEN" \
  | jq -r '.data.dnss[]? | select(.selected == true) | .id' | head -n 1)"
if [ -n "$DNS" ]; then
  gql 'mutation($id:ID!,$d:String!){updateDns(id:$id,dns:$d){id selected}}' \
    "$(jq -n --arg id "$DNS" --arg d "$DNS_BODY" '{id:$id,d:$d}')" "$TOKEN" >/dev/null
  log "Updated selected DNS (${DNS})."
else
  DNS="$(gql 'mutation($d:String){createDns(name:"default",dns:$d){id}}' \
    "$(jq -n --arg d "$DNS_BODY" '{d:$d}')" "$TOKEN" \
    | jq -r '.data.createDns.id // empty')"
  if [ -z "$DNS" ]; then
    log "createDns failed; aborting."
    exit 1
  fi
  gql 'mutation($id:ID!){selectDns(id:$id)}' \
    "$(jq -n --arg id "$DNS" '{id:$id}')" "$TOKEN" >/dev/null
  log "Created and selected DNS (${DNS})."
fi

RT="$(gql 'query{routings{id selected}}' null "$TOKEN" \
  | jq -r '.data.routings[]? | select(.selected == true) | .id' | head -n 1)"
if [ -n "$RT" ]; then
  gql 'mutation($id:ID!,$r:String!){updateRouting(id:$id,routing:$r){id selected}}' \
    "$(jq -n --arg id "$RT" --arg r "$ROUTING_BODY" '{id:$id,r:$r}')" "$TOKEN" >/dev/null
  log "Updated selected routing (${RT})."
else
  RT="$(gql 'mutation($r:String){createRouting(name:"default",routing:$r){id}}' \
    "$(jq -n --arg r "$ROUTING_BODY" '{r:$r}')" "$TOKEN" \
    | jq -r '.data.createRouting.id // empty')"
  if [ -z "$RT" ]; then
    log "createRouting failed; aborting."
    exit 1
  fi
  gql 'mutation($id:ID!){selectRouting(id:$id)}' \
    "$(jq -n --arg id "$RT" '{id:$id}')" "$TOKEN" >/dev/null
  log "Created and selected routing (${RT})."
fi

# --- 6. Validate and apply only when proxy has nodes -------------------------
gql 'mutation{run(dry:true)}' null "$TOKEN" >/dev/null

PROXY_NODES="$(gql 'query{groups{name nodes{id}}}' null "$TOKEN" \
  | jq -r '[.data.groups[]? | select(.name == "proxy") | .nodes[]?] | length')"
touch "$SENTINEL"
if [ "${PROXY_NODES:-0}" -gt 0 ]; then
  gql 'mutation{run(dry:false)}' null "$TOKEN" >/dev/null
  log "Applied daed config: proxy group has ${PROXY_NODES} node(s)."
else
  log "Provisioned DNS/routing and passed dry-run. NOT applying: proxy group has no node."
  log "Add a proxy node at http://<gateway-ip>:2023 and apply there to start forwarding overseas traffic."
fi
exit 0

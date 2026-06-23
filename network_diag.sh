#!/usr/bin/env bash

set -u

DAE_SERVICE="dae.service"
PAOPAODNS_SERVICE="paopaodns"
PAOPAODNS_ADDR="127.0.0.1"
PAOPAODNS_PORT="5304"
DOMESTIC_DOMAIN="baidu.com"
BLOCKED_DOMAIN="google.com"
DIRECT_TEST_URL="https://myip.ipip.net"
PROXY_TEST_URL="https://ipinfo.io/ip"
CURL_TIMEOUT="5"

if [ -t 1 ]; then
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  BOLD="$(printf '\033[1m')"
  RESET="$(printf '\033[0m')"
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  BOLD=""
  RESET=""
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
PROXY_TEST_FAILED=0
CURL_LAST_BODY=""

section() {
  printf '\n%s%s== %s ==%s\n' "$BOLD" "$BLUE" "$1" "$RESET"
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '%s[PASS]%s %s\n' "$GREEN" "$RESET" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '%s[FAIL]%s %s\n' "$RED" "$RESET" "$1"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$1"
}

info() {
  printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$1"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "This script must be run as root."
    exit 1
  fi
}

check_systemd_service() {
  service_name="$1"
  label="$2"

  if ! have_cmd systemctl; then
    fail "systemctl is not available; cannot check ${label}."
    return 1
  fi

  if systemctl is-active --quiet "$service_name"; then
    pass "${label} is active (${service_name})."
    return 0
  fi

  fail "${label} is not active (${service_name})."
  systemctl --no-pager --plain status "$service_name" 2>/dev/null | sed -n '1,12p'
  return 1
}

check_paopaodns_listener() {
  if ! have_cmd ss; then
    fail "ss is not available; cannot verify PaopaoDNS listener."
    return 1
  fi

  listener_lines="$(
    ss -H -lntu 2>/dev/null \
      | awk -v addr="$PAOPAODNS_ADDR" -v port=":${PAOPAODNS_PORT}" '
          $5 == addr port || $5 == "[" addr "]" port || $5 ~ ("^" addr ":" port "$") { print }
        '
  )"
  wildcard_listener_lines="$(
    ss -H -lntu 2>/dev/null \
      | awk -v port=":${PAOPAODNS_PORT}" '
          $5 == "0.0.0.0" port || $5 == "*" port || $5 == "[::]" port || $5 == "::" port { print }
        '
  )"

  if [ -n "$listener_lines" ]; then
    pass "PaopaoDNS is listening on ${PAOPAODNS_ADDR}:${PAOPAODNS_PORT}."
    printf '%s\n' "$listener_lines" | sed 's/^/       /'
    return 0
  fi

  if [ -n "$wildcard_listener_lines" ]; then
    warn "PaopaoDNS is listening on a wildcard address for port ${PAOPAODNS_PORT}; localhost can use it, but it is broader than ${PAOPAODNS_ADDR}:${PAOPAODNS_PORT}."
    printf '%s\n' "$wildcard_listener_lines" | sed 's/^/       /'
    return 0
  fi

  fail "PaopaoDNS is not listening on ${PAOPAODNS_ADDR}:${PAOPAODNS_PORT}."
  info "Current DNS-related listeners:"
  ss -H -lntu 2>/dev/null | awk '$5 ~ /:(53|5304|5303|5302|5301)$/ { print "       " $0 }'
  return 1
}

check_dae_ebpf() {
  ebpf_ok=1

  if ip link show dae0 >/dev/null 2>&1; then
    pass "dae0 interface exists; dae eBPF datapath is likely attached."
    ip -br link show dae0 2>/dev/null | sed 's/^/       /'
    ebpf_ok=0
  fi

  if journalctl -u "$DAE_SERVICE" --since boot --no-pager 2>/dev/null \
      | grep -Eqi 'Loaded eBPF programs and maps|Bind to LAN|Bind to WAN'; then
    pass "dae logs show eBPF/control-plane attachment."
    journalctl -u "$DAE_SERVICE" --since boot --no-pager 2>/dev/null \
      | grep -Ei 'Loaded eBPF programs and maps|Bind to LAN|Bind to WAN' \
      | tail -n 6 \
      | sed 's/^/       /'
    ebpf_ok=0
  fi

  if [ "$ebpf_ok" -ne 0 ]; then
    fail "Could not confirm dae eBPF attachment from dae0 or dae logs."
    info "Recent dae warnings/errors:"
    journalctl -u "$DAE_SERVICE" --since boot --no-pager 2>/dev/null \
      | grep -Ei 'ebpf|bpf|error|fail|warn' \
      | tail -n 10 \
      | sed 's/^/       /'
    return 1
  fi

  return 0
}

extract_ips_from_dig() {
  awk '
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print }
    /^[0-9a-fA-F:]+:[0-9a-fA-F:]+/ { print }
  '
}

extract_ips_from_nslookup() {
  awk '
    /^Address: / && seen_server == 1 { print $2 }
    /^Address: / && seen_server == 0 { seen_server = 1 }
    /^Addresses: / { for (i = 2; i <= NF; i++) print $i }
  '
}

dns_query() {
  domain="$1"

  if have_cmd dig; then
    dig @"$PAOPAODNS_ADDR" -p "$PAOPAODNS_PORT" "$domain" A +short 2>/dev/null \
      | extract_ips_from_dig
    return "${PIPESTATUS[0]}"
  fi

  if have_cmd nslookup; then
    nslookup -port="$PAOPAODNS_PORT" "$domain" "$PAOPAODNS_ADDR" 2>/dev/null \
      | extract_ips_from_nslookup
    return "${PIPESTATUS[0]}"
  fi

  if have_cmd python3; then
    python3 - "$PAOPAODNS_ADDR" "$PAOPAODNS_PORT" "$domain" <<'PY'
import ipaddress
import random
import socket
import struct
import sys

server = sys.argv[1]
port = int(sys.argv[2])
domain = sys.argv[3]
query_id = random.randrange(0, 65536)

header = struct.pack("!HHHHHH", query_id, 0x0100, 1, 0, 0, 0)
qname = b"".join(bytes([len(part)]) + part.encode("ascii") for part in domain.split(".")) + b"\x00"
payload = header + qname + struct.pack("!HH", 1, 1)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(4)
try:
    sock.sendto(payload, (server, port))
    data, _ = sock.recvfrom(4096)
finally:
    sock.close()

if len(data) < 12 or struct.unpack("!H", data[:2])[0] != query_id:
    raise SystemExit(1)
rcode = data[3] & 0x0F
if rcode != 0:
    raise SystemExit(1)

offset = 12
while offset < len(data) and data[offset] != 0:
    offset += data[offset] + 1
offset += 5
answers = struct.unpack("!H", data[6:8])[0]

def skip_name(buf, pos):
    while pos < len(buf):
        length = buf[pos]
        if length & 0xC0 == 0xC0:
            return pos + 2
        if length == 0:
            return pos + 1
        pos += length + 1
    raise ValueError("bad dns name")

for _ in range(answers):
    offset = skip_name(data, offset)
    if offset + 10 > len(data):
        raise SystemExit(1)
    rrtype, rrclass, _ttl, rdlen = struct.unpack("!HHIH", data[offset:offset + 10])
    offset += 10
    rdata = data[offset:offset + rdlen]
    offset += rdlen
    if rrclass == 1 and rrtype == 1 and rdlen == 4:
        print(str(ipaddress.ip_address(rdata)))
PY
    return $?
  fi

  return 127
}

check_dns_domain() {
  domain="$1"
  label="$2"

  if ! have_cmd dig && ! have_cmd nslookup && ! have_cmd python3; then
    fail "dig, nslookup, and python3 are unavailable; cannot test ${label} DNS."
    return 1
  fi

  ips="$(dns_query "$domain" | sort -u)"
  if [ -n "$ips" ]; then
    pass "${label} DNS resolution succeeded: ${domain}"
    printf '%s\n' "$ips" | sed 's/^/       /'
    return 0
  fi

  fail "${label} DNS resolution failed: ${domain}"
  return 1
}

curl_body() {
  url="$1"
  curl -m "$CURL_TIMEOUT" -fsSL "$url" 2>/dev/null | tr -d '\r' | sed 's/[[:space:]]*$//'
}

check_curl_test() {
  url="$1"
  label="$2"
  CURL_LAST_BODY=""

  if ! have_cmd curl; then
    fail "curl is not available; cannot run ${label}."
    PROXY_TEST_FAILED=1
    return 1
  fi

  body="$(curl_body "$url")"
  if [ -n "$body" ]; then
    pass "${label} succeeded: ${url}"
    printf '       %s\n' "$body"
    CURL_LAST_BODY="$body"
    return 0
  fi

  fail "${label} failed: ${url}"
  PROXY_TEST_FAILED=1
  return 1
}

main() {
  require_root

  printf '%sdae + PaopaoDNS Network Diagnostic%s\n' "$BOLD" "$RESET"
  printf 'Host: %s\n' "$(hostname 2>/dev/null || printf unknown)"
  printf 'Time: %s\n' "$(date -Is 2>/dev/null || date)"
  printf 'PaopaoDNS target: udp://%s:%s\n' "$PAOPAODNS_ADDR" "$PAOPAODNS_PORT"

  section "Service Health Check"
  check_systemd_service "$DAE_SERVICE" "dae"
  check_systemd_service "$PAOPAODNS_SERVICE" "PaopaoDNS"
  check_paopaodns_listener
  check_dae_ebpf

  section "DNS Pipeline Test (PaopaoDNS)"
  check_dns_domain "$DOMESTIC_DOMAIN" "Domestic"
  check_dns_domain "$BLOCKED_DOMAIN" "Blocked/foreign"

  section "Routing & Proxy Test (dae)"
  check_curl_test "$DIRECT_TEST_URL" "Direct route public IP check"
  direct_status=$?
  direct_output="$CURL_LAST_BODY"
  check_curl_test "$PROXY_TEST_URL" "Proxy route public IP check"
  proxy_status=$?
  proxy_output="$CURL_LAST_BODY"

  if [ "$direct_status" -ne 0 ] || [ "$proxy_status" -ne 0 ]; then
    PROXY_TEST_FAILED=1
  elif [ -n "$direct_output" ] && [ -n "$proxy_output" ] && [ "$direct_output" = "$proxy_output" ]; then
    warn "Direct and proxy checks returned identical output; verify dae routing and proxy group selection."
    PROXY_TEST_FAILED=1
  else
    pass "Direct and proxy checks returned different outputs, indicating route separation."
  fi

  if [ "$PROXY_TEST_FAILED" -ne 0 ]; then
    section "Error Log Extraction"
    info "Last 15 lines from journalctl -u ${DAE_SERVICE}:"
    journalctl -u "$DAE_SERVICE" --no-pager 2>/dev/null | tail -n 15 | sed 's/^/       /'
  fi

  section "Summary"
  printf '%sPASS:%s %s  %sWARN:%s %s  %sFAIL:%s %s\n' \
    "$GREEN" "$RESET" "$PASS_COUNT" \
    "$YELLOW" "$RESET" "$WARN_COUNT" \
    "$RED" "$RESET" "$FAIL_COUNT"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
  fi

  exit 0
}

main "$@"

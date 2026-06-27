#!/usr/bin/env bash
set -eu

LAN_IF="${1:?usage: dns-hijack.sh <lan-interface>}"
command -v nft >/dev/null 2>&1 || {
  echo "nft is required for DNS hijack rules." >&2
  exit 1
}

nft delete table inet daed_dns_hijack 2>/dev/null || true
nft -f - <<EOF
table inet daed_dns_hijack {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "${LAN_IF}" udp dport 53 redirect to :53
    iifname "${LAN_IF}" tcp dport 53 redirect to :53
  }

  chain forward {
    type filter hook forward priority filter; policy accept;
    iifname "${LAN_IF}" tcp dport 853 reject
    iifname "${LAN_IF}" udp dport 853 reject
  }
}
EOF

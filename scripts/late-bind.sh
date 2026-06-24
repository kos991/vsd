#!/usr/bin/env bash
set -e

BASE="/opt/custom-services"
LAN_IF="${LAN_INTERFACE:-eth1}"
LAN_BIND_IP=""
LAN_SUBNET=""

for _ in $(seq 1 30); do
  if ip link show "${LAN_IF}" >/dev/null 2>&1; then
    LAN_CIDR="$(ip -o -4 addr show dev "${LAN_IF}" scope global | awk '{print $4; exit}')"
    if [ -n "${LAN_CIDR}" ]; then
      LAN_BIND_IP="${LAN_CIDR%/*}"
      LAN_SUBNET="$(ip route show dev "${LAN_IF}" proto kernel scope link | awk '{print $1; exit}')"
      LAN_SUBNET="${LAN_SUBNET:-${LAN_CIDR}}"
      break
    fi
  fi
  sleep 1
done

case "${LAN_BIND_IP}" in
  ""|"0.0.0.0"|"127."*)
    echo "Refusing unsafe or missing LAN bind address: '${LAN_BIND_IP}'" >&2
    exit 1
    ;;
esac

sed \
  -e "s|<LAN_BIND_IP>|${LAN_BIND_IP}|g" \
  -e "s|<LAN_SUBNET>|${LAN_SUBNET}|g" \
  "${BASE}/mosdns/config.yaml.template" > "${BASE}/mosdns/config.yaml"

sed \
  -e "s|<LAN_BIND_IP>|${LAN_BIND_IP}|g" \
  -e "s|<LAN_SUBNET>|${LAN_SUBNET}|g" \
  "${BASE}/daed/config.dae.template" > "${BASE}/daed/config.dae"

systemctl restart smartdns.service
systemctl restart mosdns.service
systemctl restart daed.service

# daed stores DNS/routing in wing.db, not config.dae. After rendering the
# late-bound template, import and select it through the local GraphQL API.
"${BASE}/scripts/daed-provision.sh" || logger -t daed-provision "daed provisioning failed"

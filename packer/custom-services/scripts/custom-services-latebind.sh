#!/usr/bin/env bash
set -e

BASE="/config/custom-services"
LAN_IF_FILE="${BASE}/lan-interface"

resolve_lan_if() {
  if [ -n "${LAN_INTERFACE:-}" ]; then
    echo "${LAN_INTERFACE}"
    return
  fi

  if [ -f "${LAN_IF_FILE}" ]; then
    tr -d '[:space:]' <"${LAN_IF_FILE}"
    return
  fi

  DEFAULT_IF="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
  CAND="$(
    ip -o -4 addr show scope global 2>/dev/null |
      awk -v def="${DEFAULT_IF}" '
        $2 == "lo" { next }
        $2 ~ /^(dae|ifb|pim|docker|br-|veth|virbr)/ { next }
        $2 != def { print $2; found=1; exit }
        { fallback=$2 }
        END { if (!found && fallback != "") print fallback }
      '
  )"
  echo "${CAND:-${DEFAULT_IF}}"
}

LAN_BIND_IP=""
LAN_SUBNET=""
# Race-condition fix: wait up to 30s for the LAN interface to get a real IPv4.
for _ in $(seq 1 30); do
  LAN_IF="$(resolve_lan_if)"
  if [ -n "${LAN_IF}" ]; then
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
    echo "Refusing unsafe or missing LAN bind address: '${LAN_BIND_IP}' on interface '${LAN_IF:-unknown}'" >&2
    ip -o link show >&2 || true
    ip -o -4 addr show scope global >&2 || true
    exit 1
    ;;
esac

# Render real LAN address every boot; never bake an IP or bind 0.0.0.0 into the image.
sed \
  -e "s|<LAN_BIND_IP>|${LAN_BIND_IP}|g" \
  -e "s|<LAN_SUBNET>|${LAN_SUBNET}|g" \
  "${BASE}/mosdns/config.yaml.template" >"${BASE}/mosdns/config.yaml"

sed \
  -e "s|<LAN_BIND_IP>|${LAN_BIND_IP}|g" \
  -e "s|<LAN_SUBNET>|${LAN_SUBNET}|g" \
  "${BASE}/daed/config.dae.template" >"${BASE}/daed/config.dae"

ln -sf "${BASE}/geo/geoip.dat" "${BASE}/daed/geoip.dat"
ln -sf "${BASE}/geo/geosite.dat" "${BASE}/daed/geosite.dat"

systemctl daemon-reload
systemctl enable smartdns.service mosdns.service daed.service
systemctl restart smartdns.service
systemctl restart mosdns.service
systemctl restart daed.service

# daed does not read config.dae from disk; load the rendered dns/routing into its
# database via GraphQL (import-and-select, no run until a node is added). Idempotent.
"${BASE}/scripts/daed-provision.sh" || logger -t daed-provision "daed provisioning failed"

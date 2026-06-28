#!/usr/bin/env bash
set -eu

BASE="/opt/custom-services"

log() {
  echo "late-bind: $*"
}

resolve_lan_if() {
  local wan_if
  wan_if="$(ip route show default | awk '/default/ {print $5; exit}')"

  local lan_if
  lan_if="$(ip -o -4 addr show scope global | awk -v wan="${wan_if}" '
    $2 != wan && $2 !~ /^(lo|docker|podman|br-|virbr|veth)/ {
      print $2
      exit
    }
  ')"

  if [ -n "${lan_if}" ]; then
    echo "${lan_if}"
    return
  fi

  ip -o -4 addr show scope global | awk '
    $2 !~ /^(lo|docker|podman|br-|virbr|veth)/ {
      print $2
      exit
    }
  '
}

LAN_IP=""
LAN_IF="${LAN_INTERFACE:-}"
for attempt in $(seq 1 120); do
  if [ -z "${LAN_IF}" ]; then
    LAN_IF="$(resolve_lan_if)"
  fi
  if [ -z "${LAN_IF}" ]; then
    [ "${attempt}" = 1 ] && log "waiting for a LAN interface with IPv4 address"
    sleep 1
    continue
  fi

  LAN_IP="$(ip -o -4 addr show dev "${LAN_IF}" scope global | awk 'NR==1 { split($4, a, "/"); print a[1] }')"
  [ -n "${LAN_IP}" ] && break
  [ "${attempt}" = 1 ] && log "waiting for IPv4 address on interface ${LAN_IF}"
  [ -z "${LAN_INTERFACE:-}" ] && LAN_IF=""
  sleep 1
done

case "${LAN_IP}" in
  ""|127.*|169.254.*|0.*)
    echo "Refusing unsafe LAN DNS bind: interface=${LAN_IF}, ip=${LAN_IP:-none}" >&2
    exit 1
    ;;
esac

log "using LAN interface ${LAN_IF} with address ${LAN_IP}"

# Fallback DNS for the router itself, preventing daed subscription fetch failures
if ! grep -q -i "nameserver" /etc/resolv.conf 2>/dev/null; then
  log "resolv.conf is empty. Injecting fallback public DNS."
  echo "nameserver 223.5.5.5" > /etc/resolv.conf
  echo "nameserver 114.114.114.114" >> /etc/resolv.conf
fi

if [ -r "${BASE}/system/sysctl.conf" ]; then
  sysctl -q -p "${BASE}/system/sysctl.conf" || true
fi
modprobe nf_conntrack 2>/dev/null || true
if [ -w /proc/sys/net/netfilter/nf_conntrack_max ]; then
  echo 2097152 >/proc/sys/net/netfilter/nf_conntrack_max || true
fi
for scope in all default "${LAN_IF}"; do
  if [ -w "/proc/sys/net/ipv6/conf/${scope}/disable_ipv6" ]; then
    echo 1 >"/proc/sys/net/ipv6/conf/${scope}/disable_ipv6" || true
  fi
done

cp -f "${BASE}/mosdns/config.yaml.template" "${BASE}/mosdns/config.yaml"
sed -i "s|<LAN_BIND_IP>|${LAN_IP}|g" "${BASE}/mosdns/config.yaml"
"${BASE}/scripts/dns-hijack.sh" "${LAN_IF}"

ln -sf "${BASE}/geo/geoip.dat" "${BASE}/daed/geoip.dat"
ln -sf "${BASE}/geo/geosite.dat" "${BASE}/daed/geosite.dat"

systemctl daemon-reload
systemctl disable mosdns.service daed.service >/dev/null 2>&1 || true
systemctl reset-failed mosdns.service daed.service 2>/dev/null || true
systemctl restart mosdns.service
if systemctl is-active --quiet daed.service && [ "${RESTART_DAED:-0}" != "1" ]; then
  log "daed service already active"
else
  if [ "${RESTART_DAED:-0}" = "1" ]; then
    systemctl restart daed.service
  else
    systemctl start daed.service
  fi
fi
log "mosdns service restarted and daed service is active"

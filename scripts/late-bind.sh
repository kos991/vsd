#!/usr/bin/env bash
set -e

BASE="/opt/custom-services"

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
for _ in $(seq 1 60); do
  if [ -z "${LAN_IF}" ]; then
    LAN_IF="$(resolve_lan_if)"
  fi
  if [ -z "${LAN_IF}" ]; then
    sleep 1
    continue
  fi

  LAN_IP="$(ip -o -4 addr show dev "${LAN_IF}" scope global | awk 'NR==1 { split($4, a, "/"); print a[1] }')"
  [ -n "${LAN_IP}" ] && break
  [ -z "${LAN_INTERFACE:-}" ] && LAN_IF=""
  sleep 1
done

case "${LAN_IP}" in
  ""|127.*|169.254.*|0.*)
    echo "Refusing unsafe LAN DNS bind: interface=${LAN_IF}, ip=${LAN_IP:-none}" >&2
    exit 1
    ;;
esac

cp -f "${BASE}/mosdns/config.yaml.template" "${BASE}/mosdns/config.yaml"
sed -i "s|<LAN_BIND_IP>|${LAN_IP}|g" "${BASE}/mosdns/config.yaml"
"${BASE}/scripts/dns-hijack.sh" "${LAN_IF}"

ln -sf "${BASE}/geo/geoip.dat" "${BASE}/daed/geoip.dat"
ln -sf "${BASE}/geo/geosite.dat" "${BASE}/daed/geosite.dat"

systemctl daemon-reload
systemctl enable mosdns.service daed.service
systemctl restart mosdns.service
systemctl restart daed.service

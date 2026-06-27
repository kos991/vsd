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

LAN_IF="${LAN_INTERFACE:-$(resolve_lan_if)}"
if [ -z "${LAN_IF}" ]; then
  echo "Unable to detect LAN interface. Set LAN_INTERFACE explicitly." >&2
  exit 1
fi

LAN_IP=""
for _ in $(seq 1 30); do
  LAN_IP="$(ip -o -4 addr show dev "${LAN_IF}" scope global | awk 'NR==1 { split($4, a, "/"); print a[1] }')"
  [ -n "${LAN_IP}" ] && break
  sleep 1
done

case "${LAN_IP}" in
  ""|127.*|169.254.*|0.*)
    echo "Refusing unsafe LAN DNS bind: interface=${LAN_IF}, ip=${LAN_IP:-none}" >&2
    exit 1
    ;;
esac

cp -f "${BASE}/mosdns/config.yaml.template" "${BASE}/mosdns/config.yaml"

# Apply CAKE SQM to mitigate Bufferbloat
# If SQM_BANDWIDTH is set (e.g., SQM_BANDWIDTH=1000m), it will act as a rate limiter.
# Otherwise, it provides advanced AQM without a hard bandwidth limit.
if [ -n "${SQM_BANDWIDTH}" ]; then
  echo "Applying CAKE SQM with bandwidth ${SQM_BANDWIDTH} on ${LAN_IF}..."
  tc qdisc replace dev "${LAN_IF}" root cake bandwidth "${SQM_BANDWIDTH}"
else
  echo "Applying CAKE SQM (AQM only) on ${LAN_IF}..."
  tc qdisc replace dev "${LAN_IF}" root cake
fi
sed -i "s|<LAN_BIND_IP>|${LAN_IP}|g" "${BASE}/mosdns/config.yaml"
"${BASE}/scripts/dns-hijack.sh" "${LAN_IF}"

ln -sf "${BASE}/geo/geoip.dat" "${BASE}/daed/geoip.dat"
ln -sf "${BASE}/geo/geosite.dat" "${BASE}/daed/geosite.dat"

systemctl daemon-reload
systemctl enable mosdns.service daed.service
systemctl restart mosdns.service
systemctl restart daed.service

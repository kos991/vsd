#!/usr/bin/env bash
set -e

BASE="/config/custom-services"

resolve_lan_if() {
  ip -o -4 addr show scope global | awk '
    $2 !~ /^(lo|docker|podman|br-|virbr|veth)/ {
      split($4, a, "/")
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
cp -f "${BASE}/daed/config.dae.template" "${BASE}/daed/config.dae"
sed -i "s|<LAN_BIND_IP>|${LAN_IP}|g" "${BASE}/mosdns/config.yaml"
"${BASE}/scripts/dns-hijack.sh" "${LAN_IF}"

ln -sf "${BASE}/geo/geoip.dat" "${BASE}/daed/geoip.dat"
ln -sf "${BASE}/geo/geosite.dat" "${BASE}/daed/geosite.dat"

systemctl daemon-reload
systemctl enable mosdns.service daed.service
systemctl restart mosdns.service
systemctl restart daed.service

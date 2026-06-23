#!/usr/bin/env bash
set -e

GEO_DIR="/config/custom-services/geo"
BASE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
MIN_LINES=1000

mkdir -p "${GEO_DIR}"
tmp_cn="$(mktemp)"
tmp_noncn="$(mktemp)"
trap 'rm -f "${tmp_cn}" "${tmp_noncn}"' EXIT

curl -fL --retry 5 --retry-delay 3 "${BASE_URL}/geolocation-cn.txt" -o "${tmp_cn}"
curl -fL --retry 5 --retry-delay 3 "${BASE_URL}/geolocation-!cn.txt" -o "${tmp_noncn}"

cn_lines="$(wc -l <"${tmp_cn}")"
noncn_lines="$(wc -l <"${tmp_noncn}")"

# Failsafe: refuse to install short/empty lists that would break DNS routing.
if [ "${cn_lines}" -lt "${MIN_LINES}" ] || [ "${noncn_lines}" -lt "${MIN_LINES}" ]; then
  echo "Geosite lists too short (cn=${cn_lines}, noncn=${noncn_lines}); aborting." >&2
  exit 1
fi

install -m 0644 "${tmp_cn}" "${GEO_DIR}/geolocation-cn.txt"
install -m 0644 "${tmp_noncn}" "${GEO_DIR}/geolocation-!cn.txt"

if systemctl is-active --quiet mosdns.service; then
  systemctl reload mosdns.service || systemctl restart mosdns.service
fi

echo "Geosite lists updated (cn=${cn_lines}, noncn=${noncn_lines})."

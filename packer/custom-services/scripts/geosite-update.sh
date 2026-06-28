#!/usr/bin/env bash
set -e

GEO_DIR="${CUSTOM_SERVICES_GEO_DIR:-/opt/custom-services/geo}"
DAED_DIR="${CUSTOM_SERVICES_DAED_DIR:-/opt/custom-services/daed}"

# [FIX P2] 统一数据源：txt (MosDNS) 和 dat (daed) 来自同一 release
# Loyalsoldier/v2ray-rules-dat 同时提供 txt 和 dat，确保两者完全一致
BASE_URL="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release"
MIN_LINES=1000

mkdir -p "${GEO_DIR}"
tmp_cn="$(mktemp)"
tmp_noncn="$(mktemp)"
tmp_geosite="$(mktemp)"
tmp_geoip="$(mktemp)"
trap 'rm -f "${tmp_cn}" "${tmp_noncn}" "${tmp_geosite}" "${tmp_geoip}"' EXIT

echo "Downloading geo data from ${BASE_URL} ..."

# ── MosDNS 数据源（txt）────────────────────────────────────────
curl -fL --retry 5 --retry-delay 3 "${BASE_URL}/direct-list.txt"  -o "${tmp_cn}"
curl -fL --retry 5 --retry-delay 3 "${BASE_URL}/proxy-list.txt"   -o "${tmp_noncn}"

# ── daed 数据源（dat）- 同一 release，确保与 txt 一致 ──────────
curl -fL --retry 5 --retry-delay 3 "${BASE_URL}/geosite.dat" -o "${tmp_geosite}"
curl -fL --retry 5 --retry-delay 3 "${BASE_URL}/geoip.dat"   -o "${tmp_geoip}"

# ── 完整性校验 ─────────────────────────────────────────────────
cn_lines="$(wc -l <"${tmp_cn}")"
noncn_lines="$(wc -l <"${tmp_noncn}")"
geosite_size="$(wc -c <"${tmp_geosite}")"
geoip_size="$(wc -c <"${tmp_geoip}")"

if [ "${cn_lines}" -lt "${MIN_LINES}" ] || [ "${noncn_lines}" -lt "${MIN_LINES}" ]; then
  echo "Geosite txt lists too short (cn=${cn_lines}, noncn=${noncn_lines}); aborting." >&2
  exit 1
fi
if [ "${geosite_size}" -lt 500000 ] || [ "${geoip_size}" -lt 100000 ]; then
  echo "Geosite/Geoip dat files too small (geosite=${geosite_size}B, geoip=${geoip_size}B); aborting." >&2
  exit 1
fi

# ── 原子替换：校验通过后一次性写入 ───────────────────────────────
install -m 0644 "${tmp_cn}"      "${GEO_DIR}/geolocation-cn.txt"
install -m 0644 "${tmp_noncn}"   "${GEO_DIR}/geolocation-!cn.txt"
install -m 0644 "${tmp_geosite}" "${GEO_DIR}/geosite.dat"
install -m 0644 "${tmp_geoip}"   "${GEO_DIR}/geoip.dat"

# ── 更新 daed symlink（late-bind.sh 创建，此处确保同步）─────────
if [ -d "${DAED_DIR}" ]; then
  ln -sf "${GEO_DIR}/geoip.dat"   "${DAED_DIR}/geoip.dat"
  ln -sf "${GEO_DIR}/geosite.dat" "${DAED_DIR}/geosite.dat"
fi

# ── 热重载服务 ─────────────────────────────────────────────────
if systemctl is-active --quiet mosdns.service; then
  systemctl restart mosdns.service
  echo "mosdns.service restarted."
fi
if systemctl is-active --quiet daed.service; then
  systemctl restart daed.service
  echo "daed.service restarted."
fi

echo "Geo data updated: txt(cn=${cn_lines}, noncn=${noncn_lines}) dat(geosite=${geosite_size}B, geoip=${geoip_size}B)."

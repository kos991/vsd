#!/usr/bin/env bash
set -e

BASE="/config/custom-services"
BIN_DIR="${BASE}/bin"
GEO_DIR="${BASE}/geo"
DAED_DIR="${BASE}/daed"
MOSDNS_DIR="${BASE}/mosdns"
SMARTDNS_DIR="${BASE}/smartdns"
SCRIPTS_DIR="${BASE}/scripts"
SYSTEMD_DIR="/etc/systemd/system"
DAED_VERSION="${DAED_VERSION:-latest}"

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

mkdir -p "${BIN_DIR}" "${GEO_DIR}" "${DAED_DIR}" "${MOSDNS_DIR}" "${SMARTDNS_DIR}" "${SCRIPTS_DIR}"

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl jq unzip tar gzip xz-utils ca-certificates iproute2 sed
fi

github_latest_tag_with_asset() {
  repo="$1"; asset_regex="$2"
  curl -fsSL "https://api.github.com/repos/${repo}/releases?per_page=30" |
    jq -r --arg re "${asset_regex}" '
      .[] | select(.tag_name | test("^v?[0-9]"))
      | select(any(.assets[]?; .name | test($re; "i"))) | .tag_name' |
    head -n 1
}

download_latest_asset() {
  repo="$1"; asset_regex="$2"; binary_name="$3"; version="${4:-latest}"
  tmpdir="$(mktemp -d)"
  if [ "${version}" = "latest" ]; then
    api_url="https://api.github.com/repos/${repo}/releases/latest"
  else
    api_url="https://api.github.com/repos/${repo}/releases/tags/${version}"
  fi
  asset_url="$(
    curl -fsSL "${api_url}" |
      jq -r --arg re "${asset_regex}" '.assets[] | select(.name | test($re; "i")) | .browser_download_url' |
      head -n 1
  )"
  if [ -z "${asset_url}" ] || [ "${asset_url}" = "null" ]; then
    echo "No matching release asset for ${repo}, regex=${asset_regex}" >&2; exit 1
  fi
  archive="${tmpdir}/asset"
  curl -fL --retry 5 --retry-delay 3 "${asset_url}" -o "${archive}"
  mkdir -p "${tmpdir}/extract"
  case "${asset_url}" in
    *.zip) unzip -q "${archive}" -d "${tmpdir}/extract" ;;
    *.tar.gz|*.tgz) tar -xzf "${archive}" -C "${tmpdir}/extract" ;;
    *.tar.xz|*.txz) tar -xJf "${archive}" -C "${tmpdir}/extract" ;;
    *.gz) gzip -dc "${archive}" >"${tmpdir}/extract/${binary_name}" ;;
    *) cp "${archive}" "${tmpdir}/extract/${binary_name}" ;;
  esac
  found="$(find "${tmpdir}/extract" -type f \( -name "${binary_name}" -o -name "${binary_name}-linux-x86_64" -o -name "${binary_name}-linux-amd64" \) | head -n 1)"
  if [ -z "${found}" ]; then
    echo "Binary ${binary_name} not found in ${asset_url}" >&2; exit 1
  fi
  install -m 0755 "${found}" "${BIN_DIR}/${binary_name}"
  rm -rf "${tmpdir}"
}

if [ "${DAED_VERSION}" = "latest" ]; then
  DAED_VERSION="$(github_latest_tag_with_asset "daeuniverse/daed" "daed-linux-x86_64\\.zip$")"
fi
download_latest_asset "daeuniverse/daed" "daed-linux-x86_64\\.zip$" "daed" "${DAED_VERSION}"
download_latest_asset "IrineSistiana/mosdns" "linux.*(x86_64|amd64).*(zip|tar\\.gz|tgz)$" "mosdns"
download_latest_asset "pymumu/smartdns" "^smartdns-x86_64$" "smartdns"

# geo data: daed dat files + mosdns geosite txt lists
curl -fL --retry 5 --retry-delay 3 \
  "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" -o "${GEO_DIR}/geoip.dat"
curl -fL --retry 5 --retry-delay 3 \
  "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" -o "${GEO_DIR}/geosite.dat"
curl -fL --retry 5 --retry-delay 3 \
  "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geolocation-cn.txt" -o "${GEO_DIR}/geolocation-cn.txt"
curl -fL --retry 5 --retry-delay 3 \
  "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geolocation-!cn.txt" -o "${GEO_DIR}/geolocation-!cn.txt"

# Copy committed config templates + scripts uploaded by Packer.
if [ -d /tmp/custom-services ]; then
  cp -a /tmp/custom-services/. "${BASE}/"
fi
chmod +x "${SCRIPTS_DIR}/custom-services-latebind.sh" "${SCRIPTS_DIR}/geosite-update.sh" "${SCRIPTS_DIR}/daed-provision.sh"

# Templates the late-bind step renders each boot.
cp -f "${DAED_DIR}/config.dae" "${DAED_DIR}/config.dae.template"
cp -f "${MOSDNS_DIR}/config.yaml" "${MOSDNS_DIR}/config.yaml.template"

cat >"${SYSTEMD_DIR}/smartdns.service" <<'EOF'
[Unit]
Description=SmartDNS CN resolver
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/config/custom-services/bin/smartdns -f -c /config/custom-services/smartdns/smartdns.conf
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

cat >"${SYSTEMD_DIR}/mosdns.service" <<'EOF'
[Unit]
Description=MosDNS LAN-bound DNS front desk
After=network-online.target smartdns.service
Wants=network-online.target smartdns.service

[Service]
Type=simple
ExecStart=/config/custom-services/bin/mosdns start -c /config/custom-services/mosdns/config.yaml
ExecReload=/bin/systemctl try-restart mosdns.service
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

cat >"${SYSTEMD_DIR}/daed.service" <<'EOF'
[Unit]
Description=daed eBPF transparent proxy
After=network-online.target mosdns.service smartdns.service
Wants=network-online.target mosdns.service smartdns.service

[Service]
Type=simple
Environment=HOME=/root
Environment=XDG_DATA_HOME=/root/.local/share
ExecStartPre=-/bin/mount -t bpf bpf /sys/fs/bpf
ExecStart=/config/custom-services/bin/daed run -c /config/custom-services/daed/
Restart=on-failure
RestartSec=3
LimitMEMLOCK=infinity
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_BPF CAP_SYS_ADMIN
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_BPF CAP_SYS_ADMIN

[Install]
WantedBy=multi-user.target
EOF

cat >"${SYSTEMD_DIR}/custom-services-latebind.service" <<EOF
[Unit]
Description=Late-bind LAN IP for daed/mosdns/smartdns
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPTS_DIR}/custom-services-latebind.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat >"${SYSTEMD_DIR}/geosite-update.service" <<EOF
[Unit]
Description=Refresh MosDNS geosite lists
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPTS_DIR}/geosite-update.sh
EOF

cat >"${SYSTEMD_DIR}/geosite-update.timer" <<'EOF'
[Unit]
Description=Weekly MosDNS geosite refresh

[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable custom-services-latebind.service geosite-update.timer

mkdir -p /config/scripts
VYOS_BOOT="/config/scripts/vyos-postconfig-bootup.script"
touch "${VYOS_BOOT}"
chmod +x "${VYOS_BOOT}"
if ! grep -Fq "${SCRIPTS_DIR}/custom-services-latebind.sh" "${VYOS_BOOT}"; then
  cat >>"${VYOS_BOOT}" <<EOF

# daed gateway late binding: render LAN-bound configs and start services.
${SCRIPTS_DIR}/custom-services-latebind.sh || logger -t custom-services-latebind "late binding failed"
EOF
fi

echo "Custom daed gateway services installed under ${BASE}."

#!/usr/bin/env bash
set -e

BASE="/config/custom-services"
BIN_DIR="${BASE}/bin"
GEO_DIR="${BASE}/geo"
DAED_DIR="${BASE}/daed"
MOSDNS_DIR="${BASE}/mosdns"
SMARTDNS_DIR="${BASE}/smartdns"
SYSTEMD_DIR="${BASE}/systemd"
DAED_VERSION="${DAED_VERSION:-latest}"

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

mkdir -p \
  "${BIN_DIR}" \
  "${GEO_DIR}" \
  "${DAED_DIR}" \
  "${MOSDNS_DIR}" \
  "${SMARTDNS_DIR}" \
  "${SYSTEMD_DIR}"

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl jq unzip tar gzip xz-utils ca-certificates iproute2 sed
fi

github_latest_tag_with_asset() {
  repo="$1"
  asset_regex="$2"

  curl -fsSL "https://api.github.com/repos/${repo}/releases?per_page=30" |
    jq -r --arg re "${asset_regex}" '
      .[]
      | select(.tag_name | test("^v?[0-9]"))
      | select(any(.assets[]?; .name | test($re; "i")))
      | .tag_name
    ' |
    head -n 1
}

download_latest_asset() {
  repo="$1"
  asset_regex="$2"
  binary_name="$3"
  version="${4:-latest}"

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
    echo "No matching release asset found for ${repo}, regex=${asset_regex}" >&2
    exit 1
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
    echo "Binary ${binary_name} not found in ${asset_url}" >&2
    exit 1
  fi

  install -m 0755 "${found}" "${BIN_DIR}/${binary_name}"
  rm -rf "${tmpdir}"
}

if [ "${DAED_VERSION}" = "latest" ]; then
  DAED_VERSION="$(github_latest_tag_with_asset "daeuniverse/daed" "daed-linux-x86_64\\.zip$")"
fi
download_latest_asset "daeuniverse/daed" "daed-linux-x86_64\\.zip$" "daed" "${DAED_VERSION}"
download_latest_asset "IrineSistiana/mosdns" "linux.*(x86_64|amd64).*(zip|tar\\.gz|tgz)$" "mosdns"
download_latest_asset "pymumu/smartdns" "linux.*(x86_64|amd64).*(tar\\.gz|tgz)$" "smartdns"

curl -fL --retry 5 --retry-delay 3 \
  "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
  -o "${GEO_DIR}/geoip.dat"

curl -fL --retry 5 --retry-delay 3 \
  "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
  -o "${GEO_DIR}/geosite.dat"

if [ -d /tmp/custom-services ]; then
  cp -a /tmp/custom-services/. "${BASE}/"
fi

if [ ! -f "${DAED_DIR}/config.dae" ]; then
  cat >"${DAED_DIR}/config.dae" <<'EOF'
global {
  log_level: info
  tproxy_port: 12345
  lan_interface: auto
  wan_interface: auto
  auto_config_kernel_parameter: true
}

dns {
  upstream {
    local: 'udp://127.0.0.1:6053'
  }
  routing {
    request {
      fallback: local
    }
  }
}

node {
}

group {
  direct {
    policy: fixed(0)
  }
}

routing {
  dip(<LAN_SUBNET>) -> direct
  fallback: direct
}
EOF
fi

if [ ! -f "${MOSDNS_DIR}/config.yaml" ]; then
  cat >"${MOSDNS_DIR}/config.yaml" <<'EOF'
log:
  level: info

plugins:
  - tag: forward_smartdns
    type: forward
    args:
      upstreams:
        - addr: "udp://127.0.0.1:6053"
        - addr: "tcp://127.0.0.1:6053"

  - tag: main_sequence
    type: sequence
    args:
      - exec: "$forward_smartdns"

servers:
  - exec: main_sequence
    listeners:
      - protocol: udp
        addr: "<LAN_BIND_IP>:53"
      - protocol: tcp
        addr: "<LAN_BIND_IP>:53"
EOF
fi

if [ ! -f "${SMARTDNS_DIR}/smartdns.conf" ]; then
  cat >"${SMARTDNS_DIR}/smartdns.conf" <<'EOF'
bind 127.0.0.1:6053
bind-tcp 127.0.0.1:6053
cache-size 4096
prefetch-domain yes
serve-expired yes
server-tls 1.1.1.1
server-tls 8.8.8.8
EOF
fi

cp -f "${DAED_DIR}/config.dae" "${DAED_DIR}/config.dae.template"
cp -f "${MOSDNS_DIR}/config.yaml" "${MOSDNS_DIR}/config.yaml.template"

cat >"${SYSTEMD_DIR}/smartdns.service" <<'EOF'
[Unit]
Description=SmartDNS local anti-pollution upstream
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
Description=MosDNS LAN-bound DNS entry
After=network-online.target smartdns.service
Wants=network-online.target smartdns.service

[Service]
Type=simple
ExecStart=/config/custom-services/bin/mosdns start -c /config/custom-services/mosdns/config.yaml
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

cat >"${BIN_DIR}/custom-services-latebind.sh" <<'EOF'
#!/usr/bin/env bash
set -e

BASE="/config/custom-services"
LAN_IF_FILE="${BASE}/lan-interface"

if [ -f "${LAN_IF_FILE}" ]; then
  LAN_IF="$(tr -d '[:space:]' <"${LAN_IF_FILE}")"
else
  DEFAULT_IF="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
  LAN_IF="$(
    ip -o -4 addr show scope global |
      awk -v def="${DEFAULT_IF}" '$2 != "lo" && $2 != def {print $2; exit}'
  )"
  LAN_IF="${LAN_IF:-${DEFAULT_IF}}"
fi

if [ -z "${LAN_IF}" ]; then
  echo "Unable to determine LAN interface" >&2
  exit 1
fi

LAN_CIDR="$(ip -o -4 addr show dev "${LAN_IF}" scope global | awk '{print $4; exit}')"
if [ -z "${LAN_CIDR}" ]; then
  echo "No IPv4 address found on LAN interface ${LAN_IF}" >&2
  exit 1
fi

LAN_BIND_IP="${LAN_CIDR%/*}"
LAN_SUBNET="$(ip route show dev "${LAN_IF}" proto kernel scope link | awk '{print $1; exit}')"
LAN_SUBNET="${LAN_SUBNET:-${LAN_CIDR}}"

case "${LAN_BIND_IP}" in
  ""|"0.0.0.0"|"127."*)
    echo "Refusing unsafe LAN bind address: ${LAN_BIND_IP}" >&2
    exit 1
    ;;
esac

# Late Binding：每次启动都从模板渲染真实 LAN 地址，避免镜像里固化 IP 或监听 0.0.0.0。
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

ln -sf "${BASE}/systemd/smartdns.service" /etc/systemd/system/smartdns.service
ln -sf "${BASE}/systemd/mosdns.service" /etc/systemd/system/mosdns.service
ln -sf "${BASE}/systemd/daed.service" /etc/systemd/system/daed.service

systemctl daemon-reload
systemctl enable smartdns.service mosdns.service daed.service
systemctl restart smartdns.service
systemctl restart mosdns.service
systemctl restart daed.service
EOF

chmod +x "${BIN_DIR}/custom-services-latebind.sh"

cat >/etc/systemd/system/custom-services-latebind.service <<EOF
[Unit]
Description=Late-bind LAN IP for daed/mosdns/smartdns
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${BIN_DIR}/custom-services-latebind.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable custom-services-latebind.service

mkdir -p /config/scripts
VYOS_BOOT="/config/scripts/vyos-postconfig-bootup.script"
touch "${VYOS_BOOT}"
chmod +x "${VYOS_BOOT}"

if ! grep -Fq "${BIN_DIR}/custom-services-latebind.sh" "${VYOS_BOOT}"; then
  cat >>"${VYOS_BOOT}" <<EOF

# daed gateway Late Binding: render LAN-bound configs and start services.
${BIN_DIR}/custom-services-latebind.sh || logger -t custom-services-latebind "late binding failed"
EOF
fi

echo "Custom daed gateway services installed under ${BASE}."

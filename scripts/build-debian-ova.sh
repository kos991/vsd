#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
IMAGE_NAME="daed-debian-gateway"

DEBIAN_VERSION="${DEBIAN_VERSION:-13}"
DEBIAN_CODENAME="${DEBIAN_CODENAME:-trixie}"
DAED_VERSION="${DAED_VERSION:-latest}"
PAOPAODNS_IMAGE="${PAOPAODNS_IMAGE:-sliamb/paopaodns:latest}"
XANMOD_PACKAGE="${XANMOD_PACKAGE:-linux-xanmod-x64v3}"
DISK_SIZE="${DISK_SIZE:-8G}"
MEMORY_MB="${MEMORY_MB:-2048}"
CPU_COUNT="${CPU_COUNT:-2}"
SKIP_PAOPAODNS_PRELOAD="${SKIP_PAOPAODNS_PRELOAD:-0}"

QCOW_IMAGE="${BUILD_DIR}/${IMAGE_NAME}.qcow2"
VMDK_IMAGE="${DIST_DIR}/${IMAGE_NAME}.vmdk"
OVF_FILE="${DIST_DIR}/${IMAGE_NAME}.ovf"
OVA_FILE="${DIST_DIR}/${IMAGE_NAME}.ova"
PAOPAODNS_TAR="${BUILD_DIR}/paopaodns.tar"
OVERLAY_TAR="${BUILD_DIR}/overlay-debian.tar"
SETUP_SCRIPT="${BUILD_DIR}/setup-debian-gateway.sh"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must run as root because virt-customize needs root privileges." >&2
    exit 1
  fi
}

cloud_image_url() {
  printf 'https://cloud.debian.org/images/cloud/%s/latest/debian-%s-genericcloud-amd64.qcow2\n' \
    "${DEBIAN_CODENAME}" "${DEBIAN_VERSION}"
}

download_cloud_image() {
  local url
  url="$(cloud_image_url)"
  curl -fsSL "${url}" -o "${QCOW_IMAGE}"
  qemu-img resize "${QCOW_IMAGE}" "${DISK_SIZE}"
}

preload_paopaodns_image() {
  if [ "${SKIP_PAOPAODNS_PRELOAD}" = "1" ]; then
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required to preload ${PAOPAODNS_IMAGE}; set SKIP_PAOPAODNS_PRELOAD=1 to skip." >&2
    exit 1
  fi
  docker pull "${PAOPAODNS_IMAGE}"
  docker save "${PAOPAODNS_IMAGE}" -o "${PAOPAODNS_TAR}"
}

customize_image() {
  tar -C "${ROOT_DIR}/overlay-debian" -cf "${OVERLAY_TAR}" .

  cat >"${SETUP_SCRIPT}" <<SETUP
#!/usr/bin/env bash
set -euxo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  apparmor \
  bash \
  bpftool \
  ca-certificates \
  curl \
  dbus \
  docker.io \
  ethtool \
  gnupg \
  iproute2 \
  iptables \
  kmod \
  nftables \
  open-vm-tools \
  openssh-server \
  pciutils \
  procps \
  tar \
  unzip \
  xz-utils

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${DEBIAN_CODENAME} main" >/etc/apt/sources.list.d/xanmod-release.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${XANMOD_PACKAGE}"

DAED_VERSION='${DAED_VERSION}' sh /tmp/install-daed-debian.sh
rm -f /tmp/install-daed-debian.sh
MINI_PPDNS_REF='release' sh /tmp/install-mini-ppdns.sh
rm -f /tmp/install-mini-ppdns.sh

tar -xf /tmp/overlay-debian.tar -C /
rm -f /tmp/overlay-debian.tar
sed -i "s#^PAOPAODNS_IMAGE=.*#PAOPAODNS_IMAGE=${PAOPAODNS_IMAGE}#" /etc/paopaodns/paopaodns.env

chmod +x /usr/local/sbin/check-ebpf
chmod +x /usr/local/sbin/dae-gateway-firstboot
chmod +x /usr/local/sbin/gateway
chmod +x /usr/local/sbin/dae-gateway-manager
chmod +x /usr/local/sbin/daed-manager
chmod +x /usr/local/sbin/paopaodns-load-image
chmod +x /usr/local/sbin/paopaodns-manager
chmod +x /usr/local/sbin/mini-ppdns-manager
chmod +x /usr/local/sbin/qos-manager
mkdir -p /etc/dae-gateway /etc/paopaodns /var/lib/paopaodns /opt/dae-gateway/images /etc/daed /var/log/daed
if [ -f /tmp/paopaodns.tar ]; then
  mv /tmp/paopaodns.tar /opt/dae-gateway/images/paopaodns.tar
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
echo daed-gateway >/etc/hostname
passwd -l root || true
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/disable-stub.conf <<'EOF'
[Resolve]
DNSStubListener=no
EOF
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
rm -f /etc/ssh/ssh_host_*
systemctl enable systemd-networkd systemd-resolved ssh docker open-vm-tools
cat >/etc/dae-gateway-release <<EOF
DEBIAN_VERSION='${DEBIAN_VERSION}'
DEBIAN_CODENAME='${DEBIAN_CODENAME}'
DAED_VERSION='${DAED_VERSION}'
PAOPAODNS_IMAGE='${PAOPAODNS_IMAGE}'
XANMOD_PACKAGE='${XANMOD_PACKAGE}'
IMAGE_NAME='${IMAGE_NAME}'
EOF
systemctl enable check-ebpf.service
systemctl enable dae-gateway-firstboot.service
systemctl enable paopaodns.service
systemctl enable dae-qos.service
systemctl enable dae-ssh-hostkeys.service
systemctl enable daed.service
SETUP

  chmod +x "${SETUP_SCRIPT}"

  virt-customize -a "${QCOW_IMAGE}" \
    --copy-in "${ROOT_DIR}/scripts/install-daed-debian.sh:/tmp" \
    --copy-in "${ROOT_DIR}/scripts/install-mini-ppdns.sh:/tmp" \
    --copy-in "${OVERLAY_TAR}:/tmp" \
    --copy-in "${SETUP_SCRIPT}:/tmp"

  if [ -f "${PAOPAODNS_TAR}" ]; then
    virt-customize -a "${QCOW_IMAGE}" --copy-in "${PAOPAODNS_TAR}:/tmp"
  fi

  virt-customize -a "${QCOW_IMAGE}" --run /tmp/setup-debian-gateway.sh
}

package_ova() {
  mkdir -p "${DIST_DIR}"
  local RAW_CAPACITY_BYTES
  RAW_CAPACITY_BYTES="$(qemu-img info --output=json "${QCOW_IMAGE}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')"
  qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized,adapter_type=lsilogic "${QCOW_IMAGE}" "${VMDK_IMAGE}"
  bash "${ROOT_DIR}/scripts/render-ovf.sh" \
    "${IMAGE_NAME}" \
    "$(basename "${VMDK_IMAGE}")" \
    "${MEMORY_MB}" \
    "${CPU_COUNT}" \
    "${OVF_FILE}" \
    "${RAW_CAPACITY_BYTES}" \
    "Debian daed gateway" \
    "Debian GNU/Linux 13 64-bit"
  (cd "${DIST_DIR}" && tar -cf "$(basename "${OVA_FILE}")" "$(basename "${OVF_FILE}")" "$(basename "${VMDK_IMAGE}")")
  sha256sum "${OVA_FILE}" >"${DIST_DIR}/${IMAGE_NAME}.sha256"
}

main() {
  require_root
  rm -rf "${BUILD_DIR}" "${DIST_DIR}"
  mkdir -p "${BUILD_DIR}" "${DIST_DIR}"
  download_cloud_image
  preload_paopaodns_image
  customize_image
  package_ova
  echo "Built ${OVA_FILE}"
}

main "$@"

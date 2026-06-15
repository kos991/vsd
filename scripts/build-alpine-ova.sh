#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
IMAGE_NAME="dae-alpine-gateway"
ARCH="x86_64"

ALPINE_VERSION="${ALPINE_VERSION:-3.20}"
DAE_VERSION="${DAE_VERSION:-latest}"
MINI_PPDNS_REF="${MINI_PPDNS_REF:-release}"
DISK_SIZE="${DISK_SIZE:-4G}"
MEMORY_MB="${MEMORY_MB:-1024}"
CPU_COUNT="${CPU_COUNT:-1}"

RAW_IMAGE="${BUILD_DIR}/${IMAGE_NAME}.raw"
VMDK_IMAGE="${DIST_DIR}/${IMAGE_NAME}.vmdk"
OVF_FILE="${DIST_DIR}/${IMAGE_NAME}.ovf"
OVA_FILE="${DIST_DIR}/${IMAGE_NAME}.ova"
ROOTFS_DIR="${BUILD_DIR}/rootfs"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must run as root because it mounts loop devices and chroots." >&2
    exit 1
  fi
}

cleanup() {
  set +e
  if mountpoint -q "${ROOTFS_DIR}/dev"; then umount -R "${ROOTFS_DIR}/dev"; fi
  if mountpoint -q "${ROOTFS_DIR}/proc"; then umount -R "${ROOTFS_DIR}/proc"; fi
  if mountpoint -q "${ROOTFS_DIR}/sys"; then umount -R "${ROOTFS_DIR}/sys"; fi
  if mountpoint -q "${ROOTFS_DIR}"; then umount "${ROOTFS_DIR}"; fi
  if [ -n "${LOOP_DEV:-}" ]; then losetup -d "${LOOP_DEV}" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

download_alpine_rootfs() {
  local url="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}.0-${ARCH}.tar.gz"
  local archive="${BUILD_DIR}/alpine-minirootfs.tar.gz"

  if ! curl -fsSL "${url}" -o "${archive}"; then
    echo "Failed to download exact Alpine minirootfs ${ALPINE_VERSION}.0; looking up latest patch release." >&2
    local listing
    listing="$(curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/")"
    local latest
    latest="$(printf '%s' "${listing}" | grep -oE "alpine-minirootfs-${ALPINE_VERSION}\.[0-9]+-${ARCH}\.tar\.gz" | sort -V | tail -1)"
    if [ -z "${latest}" ]; then
      echo "Could not locate Alpine minirootfs for ${ALPINE_VERSION}/${ARCH}." >&2
      exit 1
    fi
    curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/${latest}" -o "${archive}"
  fi
}

create_disk() {
  truncate -s "${DISK_SIZE}" "${RAW_IMAGE}"
  parted -s "${RAW_IMAGE}" mklabel msdos
  parted -s "${RAW_IMAGE}" mkpart primary ext4 1MiB 100%
  parted -s "${RAW_IMAGE}" set 1 boot on

  LOOP_DEV="$(losetup --find --partscan --show "${RAW_IMAGE}")"
  sleep 1
  mkfs.ext4 -F -L alpine-root "${LOOP_DEV}p1"
  mkdir -p "${ROOTFS_DIR}"
  mount "${LOOP_DEV}p1" "${ROOTFS_DIR}"
}

install_rootfs() {
  tar -xzf "${BUILD_DIR}/alpine-minirootfs.tar.gz" -C "${ROOTFS_DIR}"
  cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"
  cat >"${ROOTFS_DIR}/etc/apk/repositories" <<EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community
EOF

  mount --bind /dev "${ROOTFS_DIR}/dev"
  mount -t proc proc "${ROOTFS_DIR}/proc"
  mount -t sysfs sys "${ROOTFS_DIR}/sys"

  chroot "${ROOTFS_DIR}" /bin/sh -eux <<'CHROOT'
apk update
apk add --no-cache \
  alpine-base \
  alpine-conf \
  bash \
  bpftool \
  ca-certificates \
  curl \
  e2fsprogs \
  grub \
  grub-bios \
  iproute2 \
  iptables \
  linux-firmware-none \
  linux-lts \
  nftables \
  openrc \
  qemu-guest-agent \
  tar \
  xz

echo dae-gateway >/etc/hostname
setup-timezone -z Asia/Shanghai || true
rc-update add devfs sysinit
rc-update add dmesg sysinit
rc-update add mdev sysinit
rc-update add hwclock boot
rc-update add modules boot
rc-update add sysctl boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add networking boot
rc-update add qemu-guest-agent default
rc-update add local default
CHROOT
}

copy_overlay_and_install_apps() {
  rsync -a "${ROOT_DIR}/overlay/" "${ROOTFS_DIR}/"
  install -m 0755 "${ROOT_DIR}/scripts/install-dae.sh" "${ROOTFS_DIR}/tmp/install-dae.sh"
  install -m 0755 "${ROOT_DIR}/scripts/install-mini-ppdns.sh" "${ROOTFS_DIR}/tmp/install-mini-ppdns.sh"

  chroot "${ROOTFS_DIR}" /bin/sh -eux <<CHROOT
DAE_VERSION='${DAE_VERSION}' /tmp/install-dae.sh
MINI_PPDNS_REF='${MINI_PPDNS_REF}' /tmp/install-mini-ppdns.sh
rm -f /tmp/install-dae.sh /tmp/install-mini-ppdns.sh
chmod +x /usr/local/sbin/check-ebpf /usr/local/sbin/dae-gateway-manager
chmod +x /etc/init.d/check-ebpf /etc/init.d/dae /etc/init.d/mini-ppdns
rc-update add check-ebpf default
rc-update add mini-ppdns default
CHROOT
}

configure_boot() {
  cat >"${ROOTFS_DIR}/etc/fstab" <<'EOF'
LABEL=alpine-root / ext4 defaults,noatime 0 1
bpffs /sys/fs/bpf bpf defaults 0 0
cgroup2 /sys/fs/cgroup cgroup2 defaults 0 0
EOF

  cat >"${ROOTFS_DIR}/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

  cat >"${ROOTFS_DIR}/etc/sysctl.d/90-dae-gateway.conf" <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.core.default_qdisc=fq
EOF

  chroot "${ROOTFS_DIR}" /bin/sh -eux <<'CHROOT'
cat >/boot/grub/grub.cfg <<EOF
set timeout=2
set default=0

menuentry "Alpine dae gateway" {
    linux /boot/vmlinuz-lts root=LABEL=alpine-root modules=sd-mod,virtio_blk,virtio_pci,ext4 quiet
    initrd /boot/initramfs-lts
}
EOF
CHROOT

  grub-install --target=i386-pc --boot-directory="${ROOTFS_DIR}/boot" --modules="part_msdos ext2" "${LOOP_DEV}"
}

package_ova() {
  mkdir -p "${DIST_DIR}"
  local RAW_CAPACITY_BYTES
  RAW_CAPACITY_BYTES="$(stat -c '%s' "${RAW_IMAGE}")"
  qemu-img convert -f raw -O vmdk -o subformat=streamOptimized,adapter_type=lsilogic "${RAW_IMAGE}" "${VMDK_IMAGE}"
  bash "${ROOT_DIR}/scripts/render-ovf.sh" \
    "${IMAGE_NAME}" \
    "$(basename "${VMDK_IMAGE}")" \
    "${MEMORY_MB}" \
    "${CPU_COUNT}" \
    "${OVF_FILE}" \
    "${RAW_CAPACITY_BYTES}"

  (cd "${DIST_DIR}" && tar -cf "$(basename "${OVA_FILE}")" "$(basename "${OVF_FILE}")" "$(basename "${VMDK_IMAGE}")")
  sha256sum "${OVA_FILE}" "${VMDK_IMAGE}" "${OVF_FILE}" >"${DIST_DIR}/${IMAGE_NAME}.sha256"
}

main() {
  require_root
  rm -rf "${BUILD_DIR}" "${DIST_DIR}"
  mkdir -p "${BUILD_DIR}" "${DIST_DIR}"
  download_alpine_rootfs
  create_disk
  install_rootfs
  copy_overlay_and_install_apps
  configure_boot
  cleanup
  trap - EXIT
  package_ova
  echo "Built ${OVA_FILE}"
}

main "$@"

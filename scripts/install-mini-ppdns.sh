#!/usr/bin/env sh
set -eu

MINI_PPDNS_REF="${MINI_PPDNS_REF:-release}"
ARCH="$(uname -m)"

case "${ARCH}" in
  x86_64) ASSET="mini-ppdns_x86_64" ;;
  aarch64) ASSET="mini-ppdns_aarch64" ;;
  armv7l) ASSET="mini-ppdns_armv7l" ;;
  armv6l) ASSET="mini-ppdns_armv6l" ;;
  i686) ASSET="mini-ppdns_i686" ;;
  *) echo "Unsupported mini-ppdns architecture: ${ARCH}" >&2; exit 1 ;;
esac

URL="https://raw.githubusercontent.com/kkkgo/mini-ppdns/${MINI_PPDNS_REF}/${ASSET}"
curl -fsSL "${URL}" -o /usr/sbin/mini-ppdns
chmod 0755 /usr/sbin/mini-ppdns
mkdir -p /var/log/mini-ppdns

#!/usr/bin/env sh
set -eu

DAE_VERSION="${DAE_VERSION:-latest}"
ARCH="$(uname -m)"

case "${ARCH}" in
  x86_64) ASSET_ARCH="x86_64" ;;
  aarch64) ASSET_ARCH="arm64" ;;
  *) echo "Unsupported dae architecture: ${ARCH}" >&2; exit 1 ;;
esac

ASSET="dae-linux-${ASSET_ARCH}.tar.xz"
if [ "${DAE_VERSION}" = "latest" ]; then
  URL="https://github.com/daeuniverse/dae/releases/latest/download/${ASSET}"
else
  URL="https://github.com/daeuniverse/dae/releases/download/${DAE_VERSION}/${ASSET}"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL "${URL}" -o "${tmp}/${ASSET}"
tar -xJf "${tmp}/${ASSET}" -C "${tmp}"

bin="$(find "${tmp}" -type f -name dae -perm -u+x | head -1)"
if [ -z "${bin}" ]; then
  echo "dae binary not found in ${ASSET}." >&2
  exit 1
fi

install -D -m 0755 "${bin}" /usr/sbin/dae
mkdir -p /etc/dae /var/log/dae

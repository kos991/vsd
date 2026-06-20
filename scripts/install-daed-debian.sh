#!/usr/bin/env sh
set -eu

DAED_VERSION="${DAED_VERSION:-latest}"
ARCH="$(uname -m)"

case "${ARCH}" in
  x86_64) ASSET_ARCH="x86_64" ;;
  aarch64) ASSET_ARCH="arm64" ;;
  *) echo "Unsupported daed architecture: ${ARCH}" >&2; exit 1 ;;
esac

latest_daed_tag() {
  curl -fsSL 'https://api.github.com/repos/daeuniverse/daed/releases?per_page=20' \
    | awk '
      /"tag_name":/ {
        tag=$0
        sub(/^.*"tag_name":[[:space:]]*"/, "", tag)
        sub(/".*$/, "", tag)
      }
      /"name":[[:space:]]*"installer-daed-linux-/ {
        if (tag ~ /^v[0-9]/) {
          print tag
          exit
        }
      }'
}

if [ "${DAED_VERSION}" = "latest" ]; then
  DAED_VERSION="$(latest_daed_tag)"
fi

if [ -z "${DAED_VERSION}" ]; then
  echo "Unable to resolve latest daed release." >&2
  exit 1
fi

ASSET="installer-daed-linux-${ASSET_ARCH}.deb"
URL="https://github.com/daeuniverse/daed/releases/download/${DAED_VERSION}/${ASSET}"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL "${URL}" -o "${tmp}/${ASSET}"
dpkg -i "${tmp}/${ASSET}" || apt-get -f install -y
mkdir -p /etc/daed /var/log/daed
cat >/etc/daed/install.env <<EOF
DAED_VERSION='${DAED_VERSION}'
DAED_ASSET='${ASSET}'
EOF

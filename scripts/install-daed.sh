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
      /"name":[[:space:]]*"daed-linux-/ {
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

ASSET="daed-linux-${ASSET_ARCH}.zip"
URL="https://github.com/daeuniverse/daed/releases/download/${DAED_VERSION}/${ASSET}"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL "${URL}" -o "${tmp}/${ASSET}"
unzip -q "${tmp}/${ASSET}" -d "${tmp}"

bin="$(find "${tmp}" -type f -name "daed-linux-${ASSET_ARCH}" -perm -u+x | head -1)"
if [ -z "${bin}" ]; then
  echo "daed binary not found in ${ASSET}." >&2
  exit 1
fi

install -D -m 0755 "${bin}" /usr/bin/daed
mkdir -p /etc/daed /usr/share/daed /var/log/daed

for data in geoip.dat geosite.dat; do
  found="$(find "${tmp}" -type f -name "${data}" | head -1)"
  if [ -z "${found}" ]; then
    echo "${data} not found in ${ASSET}." >&2
    exit 1
  fi
  install -D -m 0644 "${found}" "/etc/daed/${data}"
  install -D -m 0644 "${found}" "/usr/share/daed/${data}"
done

cat >/etc/daed/install.env <<EOF
DAED_VERSION='${DAED_VERSION}'
DAED_ASSET='${ASSET}'
EOF

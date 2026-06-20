#!/usr/bin/env bash
set -u

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
DIST_DIR="${WORKSPACE}/dist"
LOG_FILE="/tmp/debian-ova-build.log"

cd "${WORKSPACE}"
mkdir -p "${DIST_DIR}"
status=0

export LIBGUESTFS_BACKEND=direct
sudo systemctl stop apparmor >/dev/null 2>&1 || true

sudo --preserve-env=DEBIAN_VERSION,DEBIAN_CODENAME,DAED_VERSION,PAOPAODNS_IMAGE,XANMOD_PACKAGE,DISK_SIZE,MEMORY_MB,CPU_COUNT,SKIP_PAOPAODNS_PRELOAD,LIBGUESTFS_BACKEND \
  bash scripts/build-debian-ova.sh 2>&1 | tee "${LOG_FILE}"
pipeline_status=("${PIPESTATUS[@]}")
build_status="${pipeline_status[0]:-1}"
tee_status="${pipeline_status[1]:-0}"
if [ "${build_status}" -ne 0 ]; then
  status="${build_status}"
elif [ "${tee_status}" -ne 0 ]; then
  status="${tee_status}"
fi

sudo mkdir -p "${DIST_DIR}"
sudo chown -R "$(id -u):$(id -g)" "${DIST_DIR}" || true
mkdir -p "${DIST_DIR}"
cp "${LOG_FILE}" "${DIST_DIR}/build.log" || echo 'build log was not created' >"${DIST_DIR}/build.log"
echo "${status}" >"${DIST_DIR}/build.status"
ls -la "${DIST_DIR}"

exit 0

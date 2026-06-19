#!/usr/bin/env bash
set -u

mkdir -p dist
status=0

sudo --preserve-env=ALPINE_VERSION,DAED_VERSION,MINI_PPDNS_REF,DISK_SIZE,MEMORY_MB,CPU_COUNT \
  bash scripts/build-alpine-ova.sh 2>&1 | tee /tmp/ova-build.log
pipeline_status=("${PIPESTATUS[@]}")
if [ "${pipeline_status[0]}" -ne 0 ]; then
  status="${pipeline_status[0]}"
elif [ "${pipeline_status[1]}" -ne 0 ]; then
  status="${pipeline_status[1]}"
fi

mkdir -p dist
cp /tmp/ova-build.log dist/build.log || echo 'build log was not created' >dist/build.log
echo "${status}" >dist/build.status
ls -la dist

exit 0

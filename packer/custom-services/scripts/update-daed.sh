#!/usr/bin/env bash
set -e

# 设置变量
DAED_BIN="/usr/local/bin/daed"
REPO="daeuniverse/daed"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Checking for latest daed release from GitHub..."

# 获取最新版本号
LATEST_VERSION=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    echo "Error: Failed to fetch the latest version."
    exit 1
fi

echo "Latest version found: ${LATEST_VERSION}"

# 检查当前版本
if command -v daed >/dev/null 2>&1; then
    CURRENT_VERSION=$(daed --version | awk '{print $3}')
    echo "Current installed version: ${CURRENT_VERSION}"
    if [ "${CURRENT_VERSION}" = "${LATEST_VERSION}" ]; then
        echo "You are already using the latest version of daed. No update needed."
        exit 0
    fi
else
    echo "daed not currently installed or not in PATH. Proceeding with installation."
fi

# 构造下载链接 (通常架构为 linux-x86_64)
# 具体名称需匹配 release 的 asset 名称，daed 的 asset 通常是 daed-linux-x86_64.zip
ASSET_NAME="daed-linux-x86_64.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST_VERSION}/${ASSET_NAME}"

echo "Downloading ${ASSET_NAME}..."
curl -L --progress-bar -o "${TMP_DIR}/${ASSET_NAME}" "${DOWNLOAD_URL}"

echo "Extracting..."
unzip -q "${TMP_DIR}/${ASSET_NAME}" -d "${TMP_DIR}"

# 由于 zip 包内可能直接是一个 `daed-linux-x86_64` 的二进制文件，或者是个目录，处理一下
# 适配 daed 的发行包结构
EXTRACTED_BIN=$(find "${TMP_DIR}" -type f -name "daed-linux-x86_64" | head -n 1)

if [ -z "${EXTRACTED_BIN}" ]; then
    echo "Error: Could not find the daed executable in the downloaded archive."
    exit 1
fi

echo "Installing to ${DAED_BIN}..."
sudo install -m 755 "${EXTRACTED_BIN}" "${DAED_BIN}"

# 重启服务
echo "Restarting daed.service..."
sudo systemctl restart daed.service

echo "Update successful! New version:"
daed --version

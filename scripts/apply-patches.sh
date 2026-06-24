#!/bin/bash
# Apply patches to vyos-build repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source build configuration
if [ -f "${PROJECT_ROOT}/build.conf" ]; then
    source "${PROJECT_ROOT}/build.conf"
fi

VYOS_BUILD_ROOT="${VYOS_BUILD_ROOT:-${PROJECT_ROOT}/vyos-build}"
PATCHES_DIR="${PROJECT_ROOT}/patches"

echo "================================================"
echo "Applying patches to VyOS build"
echo "================================================"

# Function to apply patch if enabled
apply_patch() {
    local patch_file="$1"
    local target_dir="$2"
    local description="$3"

    if [ -f "${patch_file}" ]; then
        echo "Applying: ${description}"
        if patch --dry-run -p1 -d "${target_dir}" < "${patch_file}" > /dev/null 2>&1; then
            patch --no-backup-if-mismatch -p1 -d "${target_dir}" < "${patch_file}"
            echo "  ✓ Applied successfully"
        else
            echo "  ⚠ Patch already applied or conflicts detected, skipping"
        fi
    else
        echo "  ✗ Patch file not found: ${patch_file}"
    fi
}

# Clone vyos-1x for patching (if needed for vyos-1x patches)
if [ "${ENABLE_PODMAN_FIX}" = "true" ] || [ "${ENABLE_MELLANOX_SUPPORT}" = "true" ]; then
    VYOS_1X_DIR="${VYOS_BUILD_ROOT}/packages/vyos-1x"

    if [ ! -d "${VYOS_1X_DIR}" ]; then
        echo "Cloning vyos-1x repository..."
        mkdir -p "${VYOS_BUILD_ROOT}/packages"
        git clone --recursive https://github.com/vyos/vyos-1x -b current --single-branch "${VYOS_1X_DIR}"
    fi

    # Apply vyos-1x patches
    if [ "${ENABLE_PODMAN_FIX}" = "true" ]; then
        apply_patch \
            "${PATCHES_DIR}/vyos-1x/001-fix-podman-memory-swap.patch" \
            "${VYOS_1X_DIR}" \
            "Podman memory-swap fix (prevents OCI runtime error)"
    fi

    if [ "${ENABLE_MELLANOX_SUPPORT}" = "true" ]; then
        apply_patch \
            "${PATCHES_DIR}/vyos-1x/002-add-mellanox-switch-support.patch" \
            "${VYOS_1X_DIR}" \
            "Mellanox switch support (mlxsw_spectrum interface naming)"
    fi
fi

# Apply vyos-build patches
if [ "${ENABLE_NEXTTRACE_REPO}" = "true" ]; then
    apply_patch \
        "${PATCHES_DIR}/vyos-build/001-add-nexttrace-repo.patch" \
        "${VYOS_BUILD_ROOT}" \
        "NextTrace repository for network diagnostics"
fi

# Apply kernel patches (only if building custom kernel)
if [ "${ENABLE_KERNEL_PATCHES}" = "true" ] && [ -n "${KERNEL_VERSION}" ]; then
    apply_patch \
        "${PATCHES_DIR}/kernel/001-enable-swap-zram-wifi6.patch" \
        "${VYOS_BUILD_ROOT}" \
        "Kernel config: Enable SWAP, ZRAM, WiFi 6/6E support"

    # Set custom kernel version
    if [ -n "${KERNEL_VERSION}" ]; then
        DEFAULTS_FILE="${VYOS_BUILD_ROOT}/data/defaults.toml"
        if [ -f "${DEFAULTS_FILE}" ]; then
            echo "Setting kernel version to ${KERNEL_VERSION}"
            sed -i.bak "s/^kernel_version = \".*\"/kernel_version = \"${KERNEL_VERSION}\"/" "${DEFAULTS_FILE}"
            echo "  ✓ Kernel version updated"
        fi
    fi
fi

echo "================================================"
echo "Patch application completed"
echo "================================================"

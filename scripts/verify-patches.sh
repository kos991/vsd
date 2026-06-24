#!/bin/bash
# Verify patch integrity and test application

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "================================================"
echo "VyOS Patch Verification Tool"
echo "================================================"
echo ""

PATCHES_DIR="${PROJECT_ROOT}/patches"
TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to verify patch file
verify_patch() {
    local patch_file="$1"
    local patch_name=$(basename "$patch_file")

    TOTAL=$((TOTAL + 1))

    echo -e "${BLUE}[$TOTAL] Checking: ${patch_name}${NC}"

    # Check if file exists and is readable
    if [ ! -f "${patch_file}" ] || [ ! -r "${patch_file}" ]; then
        echo -e "  ${RED}✗ File not found or not readable${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi

    # Check if file is empty
    if [ ! -s "${patch_file}" ]; then
        echo -e "  ${RED}✗ File is empty${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi

    # Verify patch format
    if ! grep -q "^diff --git" "${patch_file}"; then
        echo -e "  ${RED}✗ Invalid patch format (missing 'diff --git' header)${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi

    # Check for patch hunks
    if ! grep -q "^@@" "${patch_file}"; then
        echo -e "  ${YELLOW}⚠ No hunks found (may be a simple patch)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Count changes
    local additions=$(grep -c "^+" "${patch_file}" || true)
    local deletions=$(grep -c "^-" "${patch_file}" || true)
    local files_changed=$(grep -c "^diff --git" "${patch_file}" || true)

    echo -e "  ${GREEN}✓ Valid patch format${NC}"
    echo "    Files changed: ${files_changed}"
    echo "    Lines added: ${additions}"
    echo "    Lines removed: ${deletions}"

    # Extract and show what files are being patched
    echo "    Targets:"
    grep "^diff --git" "${patch_file}" | sed 's/^diff --git a\//      - /' | sed 's/ b\/.*//'

    PASSED=$((PASSED + 1))
    echo ""
}

# Function to verify directory structure
verify_structure() {
    echo -e "${BLUE}Verifying directory structure...${NC}"

    local required_dirs=("patches/vyos-1x" "patches/vyos-build" "patches/kernel")
    local missing=0

    for dir in "${required_dirs[@]}"; do
        if [ ! -d "${PROJECT_ROOT}/${dir}" ]; then
            echo -e "  ${RED}✗ Missing directory: ${dir}${NC}"
            missing=$((missing + 1))
        else
            echo -e "  ${GREEN}✓ Found: ${dir}${NC}"
        fi
    done

    echo ""
    return $missing
}

# Function to show patch summary
show_summary() {
    echo "================================================"
    echo "Verification Summary"
    echo "================================================"
    echo "Total patches: ${TOTAL}"
    echo -e "Passed: ${GREEN}${PASSED}${NC}"
    echo -e "Failed: ${RED}${FAILED}${NC}"
    echo -e "Warnings: ${YELLOW}${WARNINGS}${NC}"
    echo ""

    if [ ${FAILED} -eq 0 ]; then
        echo -e "${GREEN}✓ All patches verified successfully!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some patches failed verification${NC}"
        return 1
    fi
}

# Function to test patch application (dry-run)
test_patch_application() {
    local vyos_build_dir="$1"

    if [ ! -d "${vyos_build_dir}" ]; then
        echo -e "${YELLOW}⚠ VyOS build directory not found: ${vyos_build_dir}${NC}"
        echo "  Skipping patch application test"
        echo "  To test patch application, clone vyos-build first:"
        echo "    git clone -b sagitta https://github.com/vyos/vyos-build.git"
        return 0
    fi

    echo -e "${BLUE}Testing patch application (dry-run)...${NC}"
    echo ""

    # Test vyos-build patches
    for patch in "${PATCHES_DIR}"/vyos-build/*.patch; do
        if [ -f "$patch" ]; then
            local patch_name=$(basename "$patch")
            echo -n "  Testing ${patch_name}... "

            if patch --dry-run --silent -p1 -d "${vyos_build_dir}" < "$patch" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ OK${NC}"
            else
                echo -e "${YELLOW}⚠ Already applied or conflicts${NC}"
            fi
        fi
    done

    echo ""
}

# Main execution
main() {
    # Verify directory structure
    verify_structure

    # Find and verify all patches
    echo -e "${BLUE}Verifying patch files...${NC}"
    echo ""

    if [ -d "${PATCHES_DIR}" ]; then
        while IFS= read -r -d '' patch_file; do
            verify_patch "$patch_file"
        done < <(find "${PATCHES_DIR}" -type f -name "*.patch" -print0 | sort -z)
    else
        echo -e "${RED}✗ Patches directory not found: ${PATCHES_DIR}${NC}"
        exit 1
    fi

    # Test patch application if vyos-build exists
    if [ -d "${PROJECT_ROOT}/vyos-build" ]; then
        test_patch_application "${PROJECT_ROOT}/vyos-build"
    fi

    # Show summary
    show_summary
}

# Run main function
main "$@"

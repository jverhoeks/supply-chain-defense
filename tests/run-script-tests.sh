#!/usr/bin/env bash
# Run all install-script-blocking tests.
# Each sub-test is skipped if the required tool is not found in PATH.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
SKIPPED=()

run_if_available() {
    local tool="$1"
    local script="$2"
    if ! command -v "$tool" &>/dev/null; then
        SKIPPED+=("$script ($tool not found)")
        return
    fi
    bash "$SCRIPT_DIR/$script"
    # lib.sh exits non-zero on failure; capture exit status
    local rc=$?
    # Pass/fail counts are printed inside each script; we just track the exit.
    [[ $rc -ne 0 ]] && ((TOTAL_FAIL++)) || ((TOTAL_PASS++))
}

run_if_available npm   test-npm-scripts.sh
run_if_available pnpm  test-pnpm-v10-scripts.sh
run_if_available pnpm  test-pnpm-v11-scripts.sh
run_if_available yarn  test-yarn-scripts.sh
run_if_available bun   test-bun-scripts.sh
run_if_available uv    test-uv-scripts.sh

echo ""
echo "==============================="
echo "Total: $TOTAL_PASS suites passed, $TOTAL_FAIL suites failed"
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo "Skipped:"
    for s in "${SKIPPED[@]}"; do echo "  - $s"; done
fi
echo "==============================="
[[ $TOTAL_FAIL -eq 0 ]]

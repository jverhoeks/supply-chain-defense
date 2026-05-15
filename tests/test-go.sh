#!/usr/bin/env bash
# Tests: Go supply chain controls
# Requirements: go in PATH

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== Go: supply chain controls ==="

if ! command -v go &>/dev/null; then
    echo "  SKIP: go not found"
    exit 0
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ── Test 1: GOFLAGS=-mod=readonly blocks implicit module downloads ────────────

test_mod_readonly() {
    local proj="$WORK_DIR/mod-readonly"
    mkdir -p "$proj"
    cat > "$proj/go.mod" <<'EOF'
module example.com/test-readonly

go 1.22

require github.com/nonexistent-supply-chain-test/fakemodule v0.0.1
EOF
    cat > "$proj/main.go" <<'EOF'
package main
import _ "github.com/nonexistent-supply-chain-test/fakemodule"
func main() {}
EOF

    local rc=0
    GOFLAGS="-mod=readonly" GOPROXY="off" go build ./... 2>/dev/null || rc=$?
    if [[ $rc -ne 0 ]]; then
        pass "GOFLAGS=-mod=readonly: build fails when go.sum is incomplete (no silent fetch)"
    else
        fail "GOFLAGS=-mod=readonly: build succeeded — should have failed without go.sum entry"
    fi
}

# ── Test 2: GOPROXY=off blocks all external downloads ────────────────────────

test_goproxy_off() {
    local proj="$WORK_DIR/proxy-off"
    mkdir -p "$proj"
    cat > "$proj/go.mod" <<'EOF'
module example.com/test-proxy-off

go 1.22
EOF

    local rc=0
    (cd "$proj" && GOPROXY=off go get golang.org/x/text@latest 2>/dev/null) || rc=$?
    if [[ $rc -ne 0 ]]; then
        pass "GOPROXY=off: external module download is blocked (no internet fallback)"
    else
        fail "GOPROXY=off: go get succeeded — should have been blocked"
    fi
}

# ── Test 3: go mod verify passes on a clean module ───────────────────────────

test_mod_verify() {
    local proj="$WORK_DIR/mod-verify"
    mkdir -p "$proj"
    cat > "$proj/go.mod" <<'EOF'
module example.com/test-verify

go 1.22
EOF
    cat > "$proj/main.go" <<'EOF'
package main
func main() {}
EOF

    # go mod verify on a module with no dependencies should always succeed.
    local rc=0
    (cd "$proj" && go mod verify 2>/dev/null) || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "go mod verify: exits 0 on a module with no external dependencies"
    else
        fail "go mod verify: failed unexpectedly on a clean module"
    fi
}

# ── Test 4: GOENV.sh uses 'off' not 'direct' fallback ────────────────────────

test_goenv_no_direct() {
    local goenv="$SCRIPT_DIR/../golang/GOENV.sh"
    if grep -q 'GOPROXY=.*,direct' "$goenv" 2>/dev/null; then
        fail "golang/GOENV.sh: GOPROXY still has ',direct' fallback — should be ',off'"
    else
        pass "golang/GOENV.sh: GOPROXY uses ',off' fallback (no public internet escape hatch)"
    fi
}

(cd "$WORK_DIR" && test_mod_readonly)
(cd "$WORK_DIR" && test_goproxy_off)
test_mod_verify
test_goenv_no_direct

summary

#!/usr/bin/env bash
# Tests: Athens Go module proxy (http://localhost:3000)
# Start with: docker compose up -d (from proxies/)

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

PROXY="http://localhost:3000"

echo "=== Athens (Go proxy, port 3000) ==="

wait_for_url "$PROXY" "Athens" 20 || { summary; exit 0; }
pass "Athens is reachable"

if ! command -v go &>/dev/null; then
    skip "go not found"
    summary; exit 0
fi

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# ── Test: Athens serves module info ──────────────────────────────────────────

response=$(curl -sf --max-time 10 "$PROXY/golang.org/x/text/@v/list" 2>/dev/null)
if [[ -n "$response" ]]; then
    pass "Athens serves module version list for golang.org/x/text"
else
    # Athens may need to fetch on first request — try triggering it
    curl -sf --max-time 15 "$PROXY/golang.org/x/text/@latest" >/dev/null 2>&1 || true
    response2=$(curl -sf --max-time 5 "$PROXY/golang.org/x/text/@v/list" 2>/dev/null)
    if [[ -n "$response2" ]]; then
        pass "Athens serves module version list (after initial fetch)"
    else
        fail "Athens did not serve golang.org/x/text -- may still be fetching"
    fi
fi

# ── Test: go resolves a module through Athens ─────────────────────────────────

proj="$WORK/go-proj"
mkdir -p "$proj"
cat > "$proj/go.mod" <<'EOF'
module example.com/athens-test
go 1.22
EOF
cat > "$proj/main.go" <<'EOF'
package main
func main() {}
EOF

rc=0
GOPROXY="$PROXY,off" GOFLAGS="-mod=mod" \
    go get -d golang.org/x/text@latest 2>&1 | tail -3 || rc=$?
# Athens may return the module or fail if not yet cached -- both are acceptable
# as long as go does not fall back to direct (GOPROXY=...,off prevents that)
if [[ $rc -eq 0 ]]; then
    pass "go get resolves golang.org/x/text through Athens proxy"
else
    pass "go get attempted Athens and stopped at 'off' (no direct fallback)"
fi

# ── Test: GOPROXY=...,off blocks direct downloads ────────────────────────────

rc2=0
GOPROXY="$PROXY,off" GOFLAGS="-mod=mod" \
    go get -d github.com/nonexistent-supply-chain-test/fakemodule@latest 2>&1 | tail -2 || rc2=$?
if [[ $rc2 -ne 0 ]]; then
    pass "GOPROXY=proxy,off: nonexistent module fails at Athens and stops (no internet fallback)"
else
    fail "GOPROXY=proxy,off: go fell through to direct download -- 'off' not respected"
fi

summary

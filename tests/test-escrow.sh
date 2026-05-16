#!/usr/bin/env bash
# Tests npm, pip, and Go module fetch through a live escrow proxy.
#
# Usage:
#   bash tests/test-escrow.sh
#   ESCROW_DIR=/path/to/escrow/repo bash tests/test-escrow.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT=18979
PASS=0; FAIL=0
ESCROW_PID=""
BIN=""
CFG=""
TMPDIR_NPM=""
ESCROW_LOG=""

ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
fail(){ echo "  FAIL $1"; FAIL=$((FAIL+1)); }

cleanup() {
    [ -n "$ESCROW_PID" ] && kill "$ESCROW_PID" 2>/dev/null || true
    [ -n "$ESCROW_PID" ] && wait "$ESCROW_PID" 2>/dev/null || true
    [ -n "$BIN" ] && [[ "$BIN" == /tmp/* ]] && rm -f "$BIN"
    [ -n "$CFG" ] && rm -f "$CFG"
    [ -n "$TMPDIR_NPM" ] && rm -rf "$TMPDIR_NPM"
    [ -n "$ESCROW_LOG" ] && rm -f "$ESCROW_LOG"
}
trap cleanup EXIT

# ---- find or build escrow ----
find_or_build() {
    local out="/tmp/escrow-sc-$$"
    # Check $ESCROW_DIR first — prefer building from source so all handlers are present
    if [ -n "${ESCROW_DIR:-}" ] && [ -d "$ESCROW_DIR" ]; then
        if [ -f "$ESCROW_DIR/cmd/escrow/main.go" ]; then
            echo "Building escrow from $ESCROW_DIR..." >&2
            (cd "$ESCROW_DIR" && go build -o "$out" ./cmd/escrow) && echo "$out" && return
        fi
        # Fall back to pre-built binary if no source
        local arch os_name
        arch="$(uname -m)"
        os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
        local prebuilt="$ESCROW_DIR/escrow-${os_name}-${arch}"
        if [ -f "$prebuilt" ] && [ -x "$prebuilt" ]; then
            echo "$prebuilt"
            return
        fi
    fi
    # Try sibling directory
    for d in "$(dirname "$REPO_ROOT")/2026-05-16-escrow" "$REPO_ROOT/../2026-05-16-escrow"; do
        if [ -d "$d" ]; then
            if [ -f "$d/cmd/escrow/main.go" ]; then
                echo "Building escrow from $d..." >&2
                (cd "$d" && go build -o "$out" ./cmd/escrow) && echo "$out" && return
            fi
            local arch os_name
            arch="$(uname -m)"
            os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
            local prebuilt="$d/escrow-${os_name}-${arch}"
            if [ -f "$prebuilt" ] && [ -x "$prebuilt" ]; then
                echo "$prebuilt"
                return
            fi
        fi
    done
    # Check PATH
    if command -v escrow >/dev/null 2>&1; then command -v escrow; return; fi
    echo "ERROR: escrow not found. Set ESCROW_DIR=/path/to/escrow/repo" >&2
    exit 1
}

BIN="$(find_or_build)"
CFG="/tmp/escrow-sc-cfg-$$.toml"

start_escrow() {
    local extra="${1:-}"
    # Kill any existing escrow instance
    if [ -n "$ESCROW_PID" ]; then
        kill "$ESCROW_PID" 2>/dev/null || true
        wait "$ESCROW_PID" 2>/dev/null || true
        ESCROW_PID=""
    fi
    # Wait for port to be free
    for i in $(seq 1 20); do nc -z 127.0.0.1 $PORT 2>/dev/null || break; sleep 0.2; done

    cat > "$CFG" <<EOF
[server]
  host = "127.0.0.1"
  port = $PORT

[storage]
  backend = "memory"

[ecosystems]
  npm  = true
  pypi = true
  go   = true

$extra

[dashboard]
  enabled = false
EOF

    ESCROW_LOG="/tmp/escrow-sc-log-$$.txt"
    "$BIN" "$CFG" >"$ESCROW_LOG" 2>&1 &
    ESCROW_PID=$!
    # Wait up to 6s for healthz
    for i in $(seq 1 20); do
        if ! kill -0 "$ESCROW_PID" 2>/dev/null; then
            echo "ERROR: escrow exited early. Last output:" >&2
            cat "$ESCROW_LOG" >&2
            exit 1
        fi
        curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 && return 0
        sleep 0.3
    done
    echo "ERROR: escrow did not become healthy in time" >&2
    exit 1
}

# ==== Block-all (age gate = 99999 days) ====
echo "Starting escrow (block-all)..."
start_escrow '[policy.age]
  min_days = 99999
  action   = "block"'

echo ""
echo "=== npm (block-all) ==="

# npm: lodash manifest should have empty versions
resp=$(curl -sf "http://127.0.0.1:$PORT/lodash" || echo "{}")
cnt=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('versions',{})))" <<< "$resp" 2>/dev/null || echo "-1")
if [ "$cnt" -eq 0 ]; then
    ok "npm: lodash versions blocked by age gate"
else
    fail "npm: expected 0 versions, got $cnt"
fi

# npm install of a package should fail (no matching version)
TMPDIR_NPM=$(mktemp -d)
# Must cd into the dir; npm install --prefix does not read .npmrc from the prefix dir
(
    cd "$TMPDIR_NPM"
    cat > .npmrc <<NPMRC
ignore-scripts=true
NPMRC
    if npm install once --registry "http://127.0.0.1:$PORT" --silent 2>/dev/null; then
        echo "INSTALLED"
    else
        echo "BLOCKED"
    fi
) > /tmp/npm-block-result-$$ 2>/dev/null
if grep -q "BLOCKED" /tmp/npm-block-result-$$; then
    ok "npm install: blocked by age gate"
else
    fail "npm install: expected failure from age gate"
fi
rm -f /tmp/npm-block-result-$$
rm -rf "$TMPDIR_NPM"
TMPDIR_NPM=""

echo ""
echo "=== PyPI (block-all) ==="

resp=$(curl -sf "http://127.0.0.1:$PORT/pypi/requests/json" || echo "{}")
cnt=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('releases',{})))" <<< "$resp" 2>/dev/null || echo "-1")
if [ "$cnt" -lt 10 ]; then
    ok "pypi: requests releases blocked by age gate (only $cnt remaining)"
else
    fail "pypi: expected < 10 releases, got $cnt"
fi

echo ""
echo "=== Go (block-all) ==="

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/go/golang.org/x/text/@v/v0.3.0.info" 2>/dev/null)
if [ "$HTTP_CODE" = "403" ]; then
    ok "go: module blocked by age gate (403)"
else
    fail "go: expected 403, got $HTTP_CODE"
fi

# ==== Allow-all (no policy) ====
echo ""
echo "Starting escrow (allow-all)..."
start_escrow ""

echo ""
echo "=== npm (allow-all) ==="

# npm: once should install
TMPDIR_NPM=$(mktemp -d)
(
    cd "$TMPDIR_NPM"
    cat > .npmrc <<NPMRC
ignore-scripts=true
NPMRC
    if npm install once --registry "http://127.0.0.1:$PORT" --silent 2>/dev/null; then
        echo "INSTALLED"
    else
        echo "BLOCKED"
    fi
) > /tmp/npm-allow-result-$$ 2>/dev/null
if grep -q "INSTALLED" /tmp/npm-allow-result-$$; then
    ok "npm install: once installed via escrow"
else
    fail "npm install: failed to install once via escrow"
fi
rm -f /tmp/npm-allow-result-$$
rm -rf "$TMPDIR_NPM"
TMPDIR_NPM=""

echo ""
echo "=== PyPI (allow-all) ==="

cnt=$(curl -sf "http://127.0.0.1:$PORT/pypi/requests/json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('releases',{})))" 2>/dev/null || echo "0")
if [ "$cnt" -gt 0 ]; then
    ok "pypi: requests releases pass through ($cnt releases)"
else
    fail "pypi: expected releases to pass through, got $cnt"
fi

echo ""
echo "=== Go (allow-all) ==="

if curl -sf "http://127.0.0.1:$PORT/go/golang.org/x/text/@v/v0.3.0.info" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('Version')=='v0.3.0' else 1)" 2>/dev/null; then
    ok "go: module proxied successfully via escrow"
else
    fail "go: expected module proxy to succeed"
fi

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]

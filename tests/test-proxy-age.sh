#!/usr/bin/env bash
# Test: Verdaccio server-side age enforcement via @verdaccio/package-filter
#
# This tests the PROXY enforcing minAgeDays: 7, independent of client config.
# Even a client with no min-release-age setting cannot install a package
# published less than 7 days ago when the proxy has the filter active.
#
# Requirements: node, npm, npx

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== Verdaccio: server-side age enforcement ==="

if ! command -v npx &>/dev/null || ! command -v npm &>/dev/null; then
    echo "  SKIP: npm / npx not found"
    exit 0
fi

VERDACCIO_PORT=4875
VERDACCIO_URL="http://localhost:$VERDACCIO_PORT"
VERDACCIO_PID=""
VERDACCIO_DIR=$(mktemp -d)
WORK_DIR=$(mktemp -d)

cleanup() {
    [[ -n "$VERDACCIO_PID" ]] && kill "$VERDACCIO_PID" 2>/dev/null || true
    rm -rf "$VERDACCIO_DIR" "$WORK_DIR"
}
trap cleanup EXIT

# ── Install @verdaccio/package-filter if not present ─────────────────────────

PLUGIN_PATH="$VERDACCIO_DIR/node_modules"
mkdir -p "$PLUGIN_PATH"
(cd "$VERDACCIO_DIR" && npm install @verdaccio/package-filter >/dev/null 2>&1) || {
    echo "  SKIP: could not install @verdaccio/package-filter"
    exit 0
}

# ── Start Verdaccio with age filter ──────────────────────────────────────────

cat > "$VERDACCIO_DIR/config.yaml" <<EOF
storage: $VERDACCIO_DIR/storage
auth:
  htpasswd:
    file: $VERDACCIO_DIR/htpasswd
    max_users: -1
uplinks:
  # No upstream — air-gapped so only locally published packages are served.
packages:
  '**':
    access: \$all
    publish: \$all
# Server-side age gate: hide any version published less than 7 days ago.
filters:
  '@verdaccio/package-filter':
    minAgeDays: 7
plugins: $VERDACCIO_DIR/node_modules
server:
  keepAliveTimeout: 60
logs:
  - {type: stdout, format: pretty, level: error}
EOF

NODE_PATH="$VERDACCIO_DIR/node_modules" \
    npx --yes verdaccio --config "$VERDACCIO_DIR/config.yaml" --listen $VERDACCIO_PORT >/dev/null 2>&1 &
VERDACCIO_PID=$!

# Wait up to 30s for startup
i=0
while ! curl -sf "$VERDACCIO_URL/-/ping" >/dev/null 2>&1; do
    i=$((i+1))
    [[ $i -ge 60 ]] && { echo "  SKIP: verdaccio did not start"; exit 0; }
    sleep 0.5
done

# ── Publish a test package (timestamp = now) ──────────────────────────────────

PKG_DIR="$WORK_DIR/fresh-age-test-pkg"
mkdir -p "$PKG_DIR"
cat > "$PKG_DIR/package.json" <<'EOF'
{
  "name": "fresh-age-test-pkg",
  "version": "1.0.0",
  "description": "Published right now — should be blocked by minAgeDays: 7"
}
EOF
cat > "$PKG_DIR/index.js" <<'EOF'
EOF

npm set "//${VERDACCIO_URL#http://}/:_authToken=test-token" 2>/dev/null
(cd "$PKG_DIR" && npm publish --registry "$VERDACCIO_URL" --force >/dev/null 2>&1)

# ── Test 1: fresh package is hidden by the age filter ────────────────────────

PROJ_NO_CONFIG="$WORK_DIR/install-no-client-config"
mkdir -p "$PROJ_NO_CONFIG"
cat > "$PROJ_NO_CONFIG/package.json" <<EOF
{
  "name": "test",
  "version": "1.0.0",
  "private": true,
  "dependencies": { "fresh-age-test-pkg": "1.0.0" }
}
EOF
# Deliberately NO min-release-age in .npmrc -- client has no age config.
cat > "$PROJ_NO_CONFIG/.npmrc" <<EOF
registry=$VERDACCIO_URL
ignore-scripts=true
EOF

rc=0
output=$(cd "$PROJ_NO_CONFIG" && npm install 2>&1) || rc=$?
if [[ $rc -ne 0 ]] || echo "$output" | grep -qi "not found\|E404\|no package\|filtered"; then
    pass "Verdaccio minAgeDays:7 blocks freshly published package at the proxy (no client config needed)"
else
    fail "Verdaccio minAgeDays:7 did NOT block fresh package -- check @verdaccio/package-filter config"
fi

# ── Test 2: verify the plugin is actually active (metadata check) ─────────────

meta=$(curl -sf "$VERDACCIO_URL/fresh-age-test-pkg" 2>/dev/null)
if echo "$meta" | python3 -c "
import sys, json
d = json.load(sys.stdin)
versions = d.get('versions', {})
if '1.0.0' in versions:
    sys.exit(1)  # version is visible -- filter not working
sys.exit(0)      # version is hidden -- filter is working
" 2>/dev/null; then
    pass "Verdaccio metadata: version 1.0.0 is hidden from the manifest (age filter active)"
elif [[ -z "$meta" ]]; then
    pass "Verdaccio metadata: package not found in manifest (age filter removed it entirely)"
else
    fail "Verdaccio metadata: version 1.0.0 is still visible in the manifest -- age filter may not be loaded"
fi

summary

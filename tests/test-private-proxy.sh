#!/usr/bin/env bash
# Test: package managers are locked to the internal proxy and cannot fall back to the public registry.
#
# Strategy: spin up a local Verdaccio with NO upstream proxy (air-gap simulation).
# Try to install a package that only exists on the public internet.
# Assert the install FAILS — proving the package manager can't bypass the proxy.
#
# This is the key property of a private proxy: packages not approved in the proxy
# are simply unavailable, regardless of what the public registry has.
#
# Requirements: npx (for verdaccio), npm (and optionally pnpm, yarn, uv)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

VERDACCIO_PORT=4874   # different port from test-minimum-age.sh to avoid conflicts
VERDACCIO_URL="http://localhost:$VERDACCIO_PORT"
VERDACCIO_PID=""
VERDACCIO_DIR=$(mktemp -d)
WORK_DIR=$(mktemp -d)

cleanup() {
    [[ -n "$VERDACCIO_PID" ]] && kill "$VERDACCIO_PID" 2>/dev/null || true
    rm -rf "$VERDACCIO_DIR" "$WORK_DIR"
}
trap cleanup EXIT

echo "=== Private proxy: registry isolation ==="

# ── Start Verdaccio with no upstream ─────────────────────────────────────────

if ! command -v npx &>/dev/null; then
    echo "  SKIP: npx not found"
    exit 0
fi

cat > "$VERDACCIO_DIR/config.yaml" <<EOF
storage: $VERDACCIO_DIR/storage
# No auth section — anonymous access and publish allowed for test purposes.
# No uplinks section — intentionally air-gapped, no fallback to public registries.
packages:
  '@*/*':
    access: \$all
    publish: \$all
  '**':
    access: \$all
    publish: \$all
security:
  api:
    legacy: true
server:
  keepAliveTimeout: 60
logs:
  - {type: stdout, format: pretty, level: error}
EOF

npx --yes verdaccio --config "$VERDACCIO_DIR/config.yaml" --listen $VERDACCIO_PORT >/dev/null 2>&1 &
VERDACCIO_PID=$!

# Wait up to 30s (npx may need to download verdaccio on first run)
i=0
while ! curl -sf "$VERDACCIO_URL/-/ping" >/dev/null 2>&1; do
    i=$((i+1))
    [[ $i -ge 60 ]] && { echo "  SKIP: verdaccio did not start in time"; exit 0; }
    sleep 0.5
done

# ── npm: registry locked to proxy, public package unavailable ─────────────────

test_npm_proxy_isolation() {
    if ! command -v npm &>/dev/null; then echo "  SKIP: npm not found"; return; fi

    local proj="$WORK_DIR/npm-proxy"
    mkdir -p "$proj"
    cat > "$proj/.npmrc" <<EOF
registry=$VERDACCIO_URL
ignore-scripts=true
EOF
    cat > "$proj/package.json" <<'EOF'
{
  "name": "proxy-test",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "lodash": "4.17.21"
  }
}
EOF
    local output rc=0
    output=$((cd "$proj" && npm install) 2>&1) || rc=$?
    if [[ $rc -ne 0 ]]; then
        pass "npm: public package (lodash) unavailable when proxy has no upstream"
    else
        fail "npm: lodash installed despite proxy having no upstream — registry is not locked"
    fi
}

# ── pnpm: same isolation check ────────────────────────────────────────────────

test_pnpm_proxy_isolation() {
    if ! command -v pnpm &>/dev/null; then echo "  SKIP: pnpm not found"; return; fi

    local proj="$WORK_DIR/pnpm-proxy"
    mkdir -p "$proj"
    cat > "$proj/.npmrc" <<EOF
registry=$VERDACCIO_URL
minimumReleaseAge=10080
ignore-scripts=true
EOF
    cat > "$proj/package.json" <<'EOF'
{
  "name": "proxy-test-pnpm",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "lodash": "4.17.21"
  }
}
EOF
    local output rc=0
    output=$((cd "$proj" && pnpm install) 2>&1) || rc=$?
    if [[ $rc -ne 0 ]]; then
        pass "pnpm: public package (lodash) unavailable when proxy has no upstream"
    else
        fail "pnpm: lodash installed despite proxy having no upstream — registry is not locked"
    fi
}

# ── yarn: same isolation check ────────────────────────────────────────────────

test_yarn_proxy_isolation() {
    if ! command -v yarn &>/dev/null; then echo "  SKIP: yarn not found"; return; fi

    local proj="$WORK_DIR/yarn-proxy"
    mkdir -p "$proj"
    cat > "$proj/.yarnrc.yml" <<EOF
npmRegistryServer: "$VERDACCIO_URL"
enableScripts: false
nodeLinker: node-modules
EOF
    cat > "$proj/package.json" <<'EOF'
{
  "name": "proxy-test-yarn",
  "version": "1.0.0",
  "private": true,
  "packageManager": "yarn@4.0.0",
  "dependencies": {
    "lodash": "4.17.21"
  }
}
EOF
    (cd "$proj" && yarn set version berry 2>/dev/null || true)

    local rc=0
    (cd "$proj" && yarn install 2>&1 | tail -5) || rc=$?
    if [[ $rc -ne 0 ]]; then
        pass "yarn: public package (lodash) unavailable when proxy has no upstream"
    else
        fail "yarn: lodash installed despite proxy having no upstream — registry is not locked"
    fi
}

# ── Verify an approved package IS available ───────────────────────────────────
# Publish a known-good package to the proxy, then install it — proves the proxy
# itself works and the block is specifically about upstream fallback.

test_approved_package_available() {
    if ! command -v npm &>/dev/null; then return; fi

    # Publish a minimal approved package to our proxy
    local pkg_dir="$WORK_DIR/approved-pkg"
    mkdir -p "$pkg_dir"
    cat > "$pkg_dir/package.json" <<'EOF'
{
  "name": "approved-internal-pkg",
  "version": "1.0.0"
}
EOF
    cat > "$pkg_dir/index.js" <<'EOF'
EOF
    # Set a dummy token — Verdaccio with legacy auth accepts any non-empty token.
    (cd "$pkg_dir" && \
        npm set "//${VERDACCIO_URL#http://}/:_authToken=test-token" && \
        npm publish --registry "$VERDACCIO_URL" --force 2>&1 | tail -2)

    local proj="$WORK_DIR/npm-approved"
    mkdir -p "$proj"
    cat > "$proj/.npmrc" <<EOF
registry=$VERDACCIO_URL
ignore-scripts=true
EOF
    cat > "$proj/package.json" <<'EOF'
{
  "name": "proxy-test-approved",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "approved-internal-pkg": "1.0.0"
  }
}
EOF
    local rc=0
    (cd "$proj" && npm install 2>&1 | tail -3) || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "npm: approved package (published to proxy) installs successfully"
    else
        fail "npm: approved package failed to install from proxy (proxy may be misconfigured)"
    fi
}

test_npm_proxy_isolation
test_pnpm_proxy_isolation
test_yarn_proxy_isolation
test_approved_package_available

summary

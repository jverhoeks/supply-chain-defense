#!/usr/bin/env bash
# Test: npm blocks install scripts when ignore-scripts=true
# Requirements: npm >= 11.10, node in PATH

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== npm: install script blocking ==="

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL=$(make_evil_pkg "$WORK_DIR")

# Project under test: uses our .npmrc (ignore-scripts=true)
PROJ_DIR="$WORK_DIR/project"
mkdir -p "$PROJ_DIR"
cp "$SCRIPT_DIR/../nodejs-npm/.npmrc" "$PROJ_DIR/.npmrc"
cat > "$PROJ_DIR/package.json" <<EOF
{
  "name": "test-project",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "evil-test-pkg": "$TARBALL"
  }
}
EOF

# Sanity check first: scripts DO run when explicitly enabled (override any global config).
PROJ_ENABLED="$WORK_DIR/project-scripts-enabled"
mkdir -p "$PROJ_ENABLED"
cat > "$PROJ_ENABLED/package.json" <<EOF
{
  "name": "test-project-enabled",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "evil-test-pkg": "$TARBALL"
  }
}
EOF
rm -f "$SENTINEL"
(cd "$PROJ_ENABLED" && npm install --ignore-scripts=false 2>&1 | tail -5)
assert_script_ran "npm baseline (--ignore-scripts=false — scripts run)"

# Main assertion: our config (.npmrc with ignore-scripts=true) blocks the script.
rm -f "$SENTINEL"
(cd "$PROJ_DIR" && npm install 2>&1 | tail -5)
assert_script_blocked "npm ignore-scripts=true"

summary

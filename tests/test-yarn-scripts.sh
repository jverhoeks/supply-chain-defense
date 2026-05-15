#!/usr/bin/env bash
# Test: Yarn Berry blocks install scripts when enableScripts: false
# Requirements: yarn >= 4.0, node in PATH

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== yarn berry: install script blocking ==="

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL=$(make_evil_pkg "$WORK_DIR")

PROJ_DIR="$WORK_DIR/project"
mkdir -p "$PROJ_DIR"
cp "$SCRIPT_DIR/../nodejs-yarn/.yarnrc.yml" "$PROJ_DIR/.yarnrc.yml"
cat > "$PROJ_DIR/package.json" <<EOF
{
  "name": "test-project",
  "version": "1.0.0",
  "private": true,
  "packageManager": "yarn@4.0.0",
  "dependencies": {
    "evil-test-pkg": "$TARBALL"
  }
}
EOF

# Yarn Berry needs to be initialised in the project dir.
(cd "$PROJ_DIR" && yarn set version berry 2>/dev/null || true)

rm -f "$SENTINEL"
(cd "$PROJ_DIR" && yarn install 2>&1 | tail -5) || true
assert_script_blocked "yarn berry enableScripts: false"

summary

#!/usr/bin/env bash
# Test: pnpm v10 blocks install scripts when ignore-scripts=true
# Requirements: pnpm >= 10.16 < 11, node in PATH

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== pnpm v10: install script blocking ==="

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL=$(make_evil_pkg "$WORK_DIR")

PROJ_DIR="$WORK_DIR/project"
mkdir -p "$PROJ_DIR"
cp "$SCRIPT_DIR/../nodejs-pnpm-v10/.npmrc" "$PROJ_DIR/.npmrc"
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

rm -f "$SENTINEL"
(cd "$PROJ_DIR" && pnpm install 2>&1 | tail -5)
assert_script_blocked "pnpm v10 ignore-scripts=true"

summary

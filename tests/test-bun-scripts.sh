#!/usr/bin/env bash
# Test: bun blocks install scripts when ignore-scripts = true in bunfig.toml
# Requirements: bun >= 1.3

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== bun: install script blocking ==="

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL=$(make_evil_pkg "$WORK_DIR")

PROJ_DIR="$WORK_DIR/project"
mkdir -p "$PROJ_DIR"
cp "$SCRIPT_DIR/../nodejs-bun/bunfig.toml" "$PROJ_DIR/bunfig.toml"
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
(cd "$PROJ_DIR" && bun install 2>&1 | tail -5)
assert_script_blocked "bun ignore-scripts = true"

summary

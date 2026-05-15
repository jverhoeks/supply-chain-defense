#!/usr/bin/env bash
# Test: pnpm v11 blocks install scripts via allowBuilds: {} in pnpm-workspace.yaml
# Requirements: pnpm >= 11.0, node in PATH

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== pnpm v11: install script blocking ==="

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL=$(make_evil_pkg "$WORK_DIR")

PROJ_DIR="$WORK_DIR/project"
mkdir -p "$PROJ_DIR"
cp "$SCRIPT_DIR/../nodejs-pnpm-v11/.npmrc" "$PROJ_DIR/.npmrc"
# pnpm-workspace.yaml carries the build policy in v11
cp "$SCRIPT_DIR/../nodejs-pnpm-v11/pnpm-workspace.yaml" "$PROJ_DIR/pnpm-workspace.yaml"
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
# pnpm v11 with strictDepBuilds=true will error on unlisted build deps.
# We expect a non-zero exit; the script should NOT have run.
(cd "$PROJ_DIR" && pnpm install 2>&1 | tail -10) || true
assert_script_blocked "pnpm v11 allowBuilds: {} + strictDepBuilds: true"

summary

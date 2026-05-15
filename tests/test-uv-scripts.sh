#!/usr/bin/env bash
# Test: uv blocks source distributions (setup.py execution) via only-binary = [":all:"]
# Requirements: uv in PATH

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== uv: source distribution blocking (only-binary) ==="

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Build a minimal sdist-only package (no wheel, has setup.py that writes sentinel).
EVIL_DIR="$WORK_DIR/evil-sdist-pkg"
mkdir -p "$EVIL_DIR/evil_sdist_pkg"
cat > "$EVIL_DIR/setup.py" <<'EOF'
import os, setuptools
open("/tmp/supply_chain_script_ran", "w").close()
setuptools.setup(name="evil-sdist-pkg", version="1.0.0")
EOF
cat > "$EVIL_DIR/evil_sdist_pkg/__init__.py" <<'EOF'
EOF
(cd "$EVIL_DIR" && python3 setup.py sdist --quiet 2>/dev/null) || true
EVIL_SDIST=$(ls "$EVIL_DIR/dist/"*.tar.gz 2>/dev/null | head -1)

if [[ -z "$EVIL_SDIST" ]]; then
    echo "  SKIP: could not build test sdist (python3/setuptools missing?)"
    exit 0
fi

PROJ_DIR="$WORK_DIR/project"
mkdir -p "$PROJ_DIR"
cp "$SCRIPT_DIR/../python-uv/uv.toml" "$PROJ_DIR/uv.toml"

rm -f "$SENTINEL"
# uv pip install with only-binary=:all: should refuse the sdist
uv pip install --python python3 \
    --config-file "$PROJ_DIR/uv.toml" \
    "$EVIL_SDIST" 2>&1 | tail -5 || true
assert_script_blocked "uv only-binary=:all: blocks setup.py sdist"

summary

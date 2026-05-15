#!/usr/bin/env bash
# Shared helpers for supply chain tests.

SENTINEL=/tmp/supply_chain_script_ran
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_script_blocked() {
    local label="$1"
    if [[ -f "$SENTINEL" ]]; then
        fail "$label — postinstall script RAN (sentinel file found)"
        rm -f "$SENTINEL"
    else
        pass "$label — postinstall script was blocked"
    fi
}

assert_script_ran() {
    local label="$1"
    if [[ -f "$SENTINEL" ]]; then
        pass "$label — postinstall script ran as expected"
        rm -f "$SENTINEL"
    else
        fail "$label — postinstall script did NOT run (expected it to)"
    fi
}

# Creates a minimal npm-compatible package with a postinstall that writes the sentinel,
# packs it as a .tgz (file: symlinks don't trigger lifecycle scripts in npm 11+),
# and echoes the path to the tarball.
# Usage: TARBALL=$(make_evil_pkg <workdir>)
make_evil_pkg() {
    local workdir="$1"
    local dir="$workdir/evil-test-pkg-src"
    mkdir -p "$dir"
    cat > "$dir/package.json" <<'EOF'
{
  "name": "evil-test-pkg",
  "version": "1.0.0",
  "scripts": {
    "postinstall": "node -e \"require('fs').writeFileSync('/tmp/supply_chain_script_ran','1')\""
  }
}
EOF
    cat > "$dir/index.js" <<'EOF'
EOF
    (cd "$dir" && npm pack --quiet >/dev/null 2>&1)
    echo "$dir/evil-test-pkg-1.0.0.tgz"
}

summary() {
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    [[ $FAIL -eq 0 ]]
}

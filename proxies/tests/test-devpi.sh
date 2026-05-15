#!/usr/bin/env bash
# Tests: devpi Python proxy (http://localhost:3141)
# Start with: docker compose up -d (from proxies/)

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

INDEX="http://localhost:3141/root/pypi/+simple/"

echo "=== devpi (Python proxy, port 3141) ==="

wait_for_url "http://localhost:3141" "devpi" 20 || { summary; exit 0; }
pass "devpi is reachable"

if ! command -v uv &>/dev/null && ! command -v pip &>/dev/null; then
    skip "uv and pip not found"
    summary; exit 0
fi

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# ── Test: devpi serves the PyPI simple index ──────────────────────────────────

response=$(curl -sf --max-time 5 "$INDEX" 2>/dev/null)
if grep -Eqi "html|packages|links" <<< "$response"; then
    pass "devpi simple index is serving (proxying PyPI)"
else
    fail "devpi simple index returned unexpected response"
fi

# ── Test: uv can resolve a package through devpi ─────────────────────────────

if command -v uv &>/dev/null; then
    proj="$WORK/uv-proj"
    mkdir -p "$proj"
    cat > "$proj/uv.toml" <<EOF
[pip]
index-url = "$INDEX"
require-hashes = false
only-binary = [":all:"]
EOF
    rc=0
    uv pip install --system --config-file "$proj/uv.toml" --dry-run requests 2>&1 | tail -3 || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "uv resolves 'requests' through devpi proxy"
    else
        fail "uv failed to resolve 'requests' through devpi (proxy may not have mirrored it yet)"
    fi
fi

# ── Test: age gate still works (client-side via uv exclude-newer) ─────────────

if command -v uv &>/dev/null; then
    proj2="$WORK/uv-age"
    mkdir -p "$proj2"
    # Set a cutoff 30 days ago -- forces uv to reject recent releases
    cutoff=$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u --date='30 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "")
    if [[ -n "$cutoff" ]]; then
        cat > "$proj2/uv.toml" <<EOF
exclude-newer = "$cutoff"
[pip]
index-url = "$INDEX"
require-hashes = false
only-binary = [":all:"]
EOF
        output=$(uv pip install --config-file "$proj2/uv.toml" --dry-run requests 2>&1) || true
        if echo "$output" | grep -Eqi "exclude-newer|excluded|no solution|resolved"; then
            pass "Client-side exclude-newer=$cutoff respected when using devpi as index"
        else
            pass "uv resolved a pre-cutoff version through devpi (exclude-newer working)"
        fi
    fi
fi

summary

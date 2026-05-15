#!/usr/bin/env bash
# Tests: Verdaccio proxy (http://localhost:4873)
# Start with: docker compose up -d (from proxies/)

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

REGISTRY="http://localhost:4873"

echo "=== Verdaccio (npm proxy, port 4873) ==="

wait_for_url "$REGISTRY/-/ping" "Verdaccio" 20 || { summary; exit 0; }
pass "Verdaccio is reachable"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# ── Test: proxy forwards a known package metadata ─────────────────────────────

meta=$(curl -sf "$REGISTRY/lodash" 2>/dev/null)
if echo "$meta" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'versions' in d" 2>/dev/null; then
    pass "Verdaccio proxies lodash metadata from npmjs"
else
    fail "Verdaccio did not return lodash metadata (proxy upstream may be misconfigured)"
fi

# ── Test: age filter is active (minAgeDays: 7) ───────────────────────────────
# The filter only applies to packages fetched from UPSTREAM (proxied packages),
# not to packages published directly into this Verdaccio instance.
# We fetch @types/bun from the npmjs upstream and check that recently-published
# versions are hidden while older ones remain visible.

meta2=$(curl -sf "$REGISTRY/@types%2fbun" 2>/dev/null)
filter_check=$(echo "$meta2" | python3 -c "
import sys, json, datetime
raw = sys.stdin.read()
if not raw: sys.exit(2)
d = json.loads(raw)
versions = d.get('versions', {})
times = d.get('time', {})
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7)
recent = [v for v in versions if v in times and datetime.datetime.fromisoformat(times[v]) > cutoff]
old    = [v for v in versions if v in times and datetime.datetime.fromisoformat(times[v]) <= cutoff]
if len(recent) == 0 and len(old) > 0:
    print(f'{len(old)} old versions visible, recent ones hidden')
    sys.exit(0)
else:
    print(f'{len(recent)} recent versions still visible (not filtered)')
    sys.exit(1)
" 2>/dev/null)
fc_rc=$?
if [[ $fc_rc -eq 0 ]]; then
    pass "Age filter: $filter_check (minAgeDays:7 active on upstream packages)"
else
    fail "Age filter: $filter_check -- @verdaccio/package-filter not filtering upstream packages"
fi

# ── Test: install through proxy works for an older package ───────────────────
# We publish a package with a backdated time field and assert it IS visible.
# Verdaccio does not let us set the publish time, so instead we just check
# that lodash (years old) resolves through the proxy.

proj="$WORK/install-proj"
mkdir -p "$proj"
cat > "$proj/package.json" <<EOF
{"name":"test","version":"1.0.0","private":true,"dependencies":{"lodash":"4.17.21"}}
EOF
cat > "$proj/.npmrc" <<EOF
registry=$REGISTRY
ignore-scripts=true
EOF
rc=0
(cd "$proj" && npm install 2>&1 | tail -3) || rc=$?
if [[ $rc -eq 0 ]]; then
    pass "Install works for lodash 4.17.21 (years old, passes age filter)"
else
    fail "Install failed for lodash through Verdaccio proxy"
fi

summary

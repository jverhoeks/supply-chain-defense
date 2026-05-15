#!/usr/bin/env bash
# Shared helpers for proxy tests.
# Assumes proxies are running via: docker compose up -d (from proxies/)

PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP+1)); }

wait_for_url() {
    local url="$1" label="$2" timeout="${3:-15}"
    local i=0
    while ! curl -sf --max-time 2 "$url" >/dev/null 2>&1; do
        i=$((i+1))
        [[ $i -ge $timeout ]] && { skip "$label not reachable at $url"; return 1; }
        sleep 1
    done
    return 0
}

summary() {
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    [[ $FAIL -eq 0 ]]
}

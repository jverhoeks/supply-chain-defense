#!/usr/bin/env bash
# Run all proxy tests.
# Requires: docker compose up -d (from proxies/)

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

PASS=0; FAIL=0

run() {
    bash "$DIR/$1" 2>&1
    [[ $? -eq 0 ]] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
    echo
}

run test-verdaccio.sh
run test-devpi.sh
run test-athens.sh
run test-reposilite.sh
run test-bagetter.sh
run test-nexus.sh

echo "==============================="
echo "Suites: $PASS passed, $FAIL failed"
echo "==============================="
[[ $FAIL -eq 0 ]]

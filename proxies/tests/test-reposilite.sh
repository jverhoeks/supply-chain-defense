#!/usr/bin/env bash
# Tests: Reposilite Maven/Gradle proxy (http://localhost:8080)
# Start with: docker compose up -d (from proxies/)

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

BASE="http://localhost:8080"

echo "=== Reposilite (Maven/Gradle proxy, port 8080) ==="

wait_for_url "$BASE/api/maven/details/releases/" "Reposilite" 20 || { summary; exit 0; }
pass "Reposilite is reachable"

# ── Test: API responds with repository list ───────────────────────────────────

response=$(curl -sf --max-time 5 "$BASE/api/maven/details/releases/" 2>/dev/null)
if echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'name' in d" 2>/dev/null; then
    pass "Reposilite releases repository is serving"
else
    fail "Reposilite did not respond at /api/maven/details/releases/"
fi

# ── Ensure 'central' proxied repository exists (idempotent) ──────────────────
# Reposilite v3 stores repository config in SQLite; the .groovy DSL is ignored.
# Use the settings API to add 'central' if it is not already present.

existing=$(curl -sf -u admin:admin_secret "$BASE/api/settings/domain/maven" 2>/dev/null)
if ! echo "$existing" | python3 -c "import sys,json; d=json.load(sys.stdin); ids=[r['id'] for r in d.get('repositories',[])]; assert 'central' in ids" 2>/dev/null; then
    # Merge 'central' into the existing repository list
    updated=$(echo "$existing" | python3 -c "
import sys, json
d = json.load(sys.stdin)
central = {
    'id': 'central', 'visibility': 'PUBLIC', 'redeployment': False,
    'preserveSnapshots': False,
    'storageProvider': {'type': 'fs', 'quota': '100%', 'mount': '', 'maxResourceLockLifetimeInSeconds': 60},
    'storagePolicy': 'PRIORITIZE_UPSTREAM_METADATA', 'metadataMaxAge': 0,
    'proxied': [{'reference': 'https://repo1.maven.org/maven2/', 'store': True,
                 'connectTimeout': 5, 'readTimeout': 15, 'allowedGroups': [],
                 'allowRedirects': False, 'authorization': None, 'disableSSL': False}]
}
d['repositories'].append(central)
print(json.dumps(d))
")
    curl -sf -X PUT -u admin:admin_secret \
        -H "Content-Type: application/json" \
        "$BASE/api/settings/domain/maven" \
        -d "$updated" 2>/dev/null > /dev/null
fi

# ── Test: proxy serves Maven Central artifact ─────────────────────────────────

pom=$(curl -sf --max-time 15 \
    "$BASE/central/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.pom" \
    2>/dev/null)
if echo "$pom" | grep -q "artifactId"; then
    pass "Reposilite proxies Maven Central: commons-lang3 POM fetched"
else
    fail "Reposilite did not return commons-lang3 POM (proxy may not be configured or central not mirrored yet)"
fi

# ── Test: Maven settings.xml checksumPolicy=fail is set ──────────────────────
# Not a runtime proxy test -- validates the client-side config is in place.

settings="$DIR/../../java-maven/settings.xml"
if grep -q '<checksumPolicy>fail</checksumPolicy>' "$settings" 2>/dev/null; then
    pass "settings.xml: checksumPolicy=fail (tampered artifacts will break the build)"
else
    fail "settings.xml: checksumPolicy not set to fail"
fi

summary

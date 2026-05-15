#!/usr/bin/env bash
set -uo pipefail

NEXUS="${NEXUS_URL:-http://localhost:8081}"
ADMIN_PASS="admin123"
CONTAINER="${NEXUS_CONTAINER:-proxies-nexus-1}"

# ---------------------------------------------------------------------------
# 1. Wait for Nexus to become writable
# ---------------------------------------------------------------------------
echo "Waiting for Nexus at $NEXUS ..."
tries=0
until curl -sf "$NEXUS/service/rest/v1/status/writable" > /dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -ge 120 ]; then
    echo "ERROR: Nexus did not become writable after 360 seconds. Aborting." >&2
    exit 1
  fi
  sleep 3
done
echo "Nexus is ready (after $((tries * 3))s)."

# ---------------------------------------------------------------------------
# 2. Read auto-generated admin password (or fall back to $ADMIN_PASS)
# ---------------------------------------------------------------------------
INITIAL_PASS="$(docker exec "$CONTAINER" cat /nexus-data/admin.password 2>/dev/null || true)"

if [ -z "$INITIAL_PASS" ]; then
  echo "admin.password file not found in container; using fallback ADMIN_PASS."
  INITIAL_PASS="$ADMIN_PASS"
fi

# ---------------------------------------------------------------------------
# 3. Change admin password to admin123
# ---------------------------------------------------------------------------
echo "Setting admin password ..."
http_code=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT "$NEXUS/service/rest/v1/security/users/admin/change-password" \
  -u "admin:$INITIAL_PASS" \
  -H "Content-Type: text/plain" \
  --data-raw "admin123")

if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
  echo "  Password changed successfully."
  ADMIN_PASS="admin123"
elif [ "$http_code" = "401" ] && [ "$INITIAL_PASS" != "admin123" ]; then
  echo "  Password change returned 401 — password may already be admin123, continuing."
  ADMIN_PASS="admin123"
else
  echo "  WARNING: Password change returned HTTP $http_code." >&2
fi

# ---------------------------------------------------------------------------
# 4. Enable anonymous read access
# ---------------------------------------------------------------------------
echo "Enabling anonymous read access ..."
http_code=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT "$NEXUS/service/rest/v1/security/anonymous" \
  -u "admin:$ADMIN_PASS" \
  -H "Content-Type: application/json" \
  --data-raw '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}')

if [ "$http_code" = "200" ]; then
  echo "  Anonymous access enabled."
else
  echo "  WARNING: Anonymous access returned HTTP $http_code." >&2
fi

# ---------------------------------------------------------------------------
# 5. Accept EULA (required by Nexus CE 3.70+ before proxying is allowed)
# ---------------------------------------------------------------------------
echo "Accepting Nexus EULA ..."
eula_state=$(curl -sf "$NEXUS/service/rest/v1/system/eula" \
  -u "admin:$ADMIN_PASS" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('accepted','?'))" 2>/dev/null || echo "unknown")
if [ "$eula_state" = "True" ] || [ "$eula_state" = "true" ]; then
  echo "  EULA already accepted."
else
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$NEXUS/service/rest/v1/system/eula" \
    -u "admin:$ADMIN_PASS" \
    -H "Content-Type: application/json" \
    --data-raw '{"accepted":true}')
  [ "$http_code" = "204" ] || [ "$http_code" = "200" ] \
    && echo "  EULA accepted." \
    || echo "  WARNING: EULA acceptance returned HTTP $http_code." >&2
fi

# ---------------------------------------------------------------------------
# 6-a. Helper: create a proxy repository (idempotent)
# ---------------------------------------------------------------------------
create_repo() {
  local format="$1"
  local name="$2"
  local payload="$3"

  # Check if it already exists
  if curl -sf "$NEXUS/service/rest/v1/repositories/$name" \
       -u "admin:$ADMIN_PASS" > /dev/null 2>&1; then
    echo "  $name: already exists, skipping."
    return
  fi

  # Create it
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$NEXUS/service/rest/v1/repositories/$format/proxy" \
    -u "admin:$ADMIN_PASS" \
    -H "Content-Type: application/json" \
    --data-raw "$payload")

  local rc=$?
  if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
    echo "  $name: created."
  else
    echo "  $name: FAILED (exit $rc, HTTP $http_code)" >&2
  fi
}

# ---------------------------------------------------------------------------
# 6-b. Create the six proxy repositories
# ---------------------------------------------------------------------------
echo "Creating proxy repositories ..."

create_repo npm npm-proxy \
  '{"name":"npm-proxy","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},"negativeCache":{"enabled":true,"timeToLive":1440},"httpClient":{"blocked":false,"autoBlock":true}}'

create_repo pypi pypi-proxy \
  '{"name":"pypi-proxy","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"proxy":{"remoteUrl":"https://pypi.org","contentMaxAge":1440,"metadataMaxAge":1440},"negativeCache":{"enabled":true,"timeToLive":1440},"httpClient":{"blocked":false,"autoBlock":true}}'

create_repo go go-proxy \
  '{"name":"go-proxy","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"proxy":{"remoteUrl":"https://proxy.golang.org","contentMaxAge":1440,"metadataMaxAge":1440},"negativeCache":{"enabled":true,"timeToLive":1440},"httpClient":{"blocked":false,"autoBlock":true}}'

create_repo maven2 maven-central \
  '{"name":"maven-central","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":1440,"metadataMaxAge":1440},"negativeCache":{"enabled":true,"timeToLive":1440},"httpClient":{"blocked":false,"autoBlock":true},"maven":{"versionPolicy":"MIXED","layoutPolicy":"STRICT","contentDisposition":"ATTACHMENT"}}'

create_repo nuget nuget-proxy \
  '{"name":"nuget-proxy","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"proxy":{"remoteUrl":"https://api.nuget.org/v3/index.json","contentMaxAge":1440,"metadataMaxAge":1440},"negativeCache":{"enabled":true,"timeToLive":1440},"httpClient":{"blocked":false,"autoBlock":true},"nugetProxy":{"v3ServiceUrl":"https://api.nuget.org/v3/index.json","queryCacheItemMaxAge":3600,"nugetVersion":"V3"}}'

create_repo composer composer-proxy \
  '{"name":"composer-proxy","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"proxy":{"remoteUrl":"https://packagist.org","contentMaxAge":1440,"metadataMaxAge":1440},"negativeCache":{"enabled":true,"timeToLive":1440},"httpClient":{"blocked":false,"autoBlock":true}}'

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------
echo ""
echo "Nexus proxy repositories:"
echo "  npm-proxy      : $NEXUS/repository/npm-proxy/"
echo "  pypi-proxy     : $NEXUS/repository/pypi-proxy/simple/"
echo "  go-proxy       : $NEXUS/repository/go-proxy/"
echo "  maven-central  : $NEXUS/repository/maven-central/"
echo "  nuget-proxy    : $NEXUS/repository/nuget-proxy/index.json"
echo "  composer-proxy : $NEXUS/repository/composer-proxy/"

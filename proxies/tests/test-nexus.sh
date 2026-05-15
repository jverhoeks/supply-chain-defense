#!/usr/bin/env bash
# Tests: Nexus proxy (http://localhost:8081)
# Start with: docker compose up -d (from proxies/)

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

NEXUS="http://localhost:8081"

echo "=== Nexus (multi-ecosystem proxy, port 8081) ==="

wait_for_url "$NEXUS/service/rest/v1/status" "Nexus" 30 || { summary; exit 0; }
pass "Nexus is reachable"

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ── Repo existence checks ─────────────────────────────────────────────────────

for repo in npm-proxy pypi-proxy go-proxy maven-central nuget-proxy; do
    if curl -sf --max-time 5 "$NEXUS/service/rest/v1/repositories/$repo" \
            -u "admin:admin123" >/dev/null 2>&1; then
        pass "Repository '$repo' exists"
    else
        fail "Repository '$repo' missing — run: bash nexus/setup.sh"
    fi
done

# ── npm caching test ──────────────────────────────────────────────────────────

if command -v npm >/dev/null 2>&1; then
    proj="$WORK/npm-proj"
    mkdir -p "$proj"
    cat > "$proj/package.json" <<EOF
{"name":"test","version":"1.0.0","private":true,"dependencies":{"lodash":"4.17.21"}}
EOF
    cat > "$proj/.npmrc" <<EOF
registry=$NEXUS/repository/npm-proxy/
ignore-scripts=true
EOF
    rc=0
    (cd "$proj" && npm install 2>&1 | tail -5) || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "npm: lodash 4.17.21 installs through Nexus npm-proxy"
    else
        fail "npm: lodash 4.17.21 installs through Nexus npm-proxy"
    fi
fi

# ── uv PyPI caching test ──────────────────────────────────────────────────────

if command -v uv >/dev/null 2>&1; then
    proj="$WORK/uv-proj"
    mkdir -p "$proj"
    cat > "$proj/uv.toml" <<EOF
[pip]
index-url = "$NEXUS/repository/pypi-proxy/simple/"
require-hashes = false
only-binary = [":all:"]
EOF
    rc=0
    uv pip install --system --config-file "$proj/uv.toml" --dry-run requests 2>&1 | tail -5 || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "uv: 'requests' resolves through Nexus pypi-proxy"
    else
        fail "uv: 'requests' resolves through Nexus pypi-proxy"
    fi
fi

# ── Go caching test ───────────────────────────────────────────────────────────

if command -v go >/dev/null 2>&1; then
    proj="$WORK/go-proj"
    mkdir -p "$proj"
    cat > "$proj/go.mod" <<EOF
module supplychain/nexustest

go 1.21

require golang.org/x/text v0.14.0
EOF
    rc=0
    (cd "$proj" && GOPROXY="$NEXUS/repository/go-proxy,off" \
        GONOSUMDB="*" \
        GOFLAGS="-mod=mod" \
        go mod download golang.org/x/text@v0.14.0 2>&1 | tail -5) || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "go: golang.org/x/text@v0.14.0 downloads through Nexus go-proxy"
    else
        fail "go: golang.org/x/text@v0.14.0 downloads through Nexus go-proxy"
    fi
fi

# ── Maven caching test ────────────────────────────────────────────────────────

pom_body=$(curl -sf --max-time 15 \
    "$NEXUS/repository/maven-central/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.pom" \
    2>/dev/null || true)
if grep -q "artifactId" <<< "$pom_body"; then
    pass "Maven: commons-lang3 POM fetches through Nexus maven-central"
else
    fail "Maven: commons-lang3 POM fetches through Nexus maven-central"
fi

# ── NuGet caching test ────────────────────────────────────────────────────────

if command -v dotnet >/dev/null 2>&1; then
    proj="$WORK/nuget-proj"
    mkdir -p "$proj"
    cat > "$proj/test.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
  </ItemGroup>
</Project>
EOF
    cat > "$proj/NuGet.Config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nexus-nuget" value="$NEXUS/repository/nuget-proxy/index.json" allowInsecureConnections="true" />
  </packageSources>
</configuration>
EOF
    rc=0
    (cd "$proj" && dotnet restore --nologo -q 2>&1 | tail -5) || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "dotnet: Newtonsoft.Json 13.0.3 restores through Nexus nuget-proxy"
    else
        fail "dotnet: Newtonsoft.Json 13.0.3 restores through Nexus nuget-proxy"
    fi
fi

# ── npm age gate test ─────────────────────────────────────────────────────────

if command -v npm >/dev/null 2>&1; then
    proj="$WORK/npm-age-proj"
    mkdir -p "$proj"
    cat > "$proj/package.json" <<EOF
{"name":"test","version":"1.0.0","private":true,"dependencies":{"lodash":"4.17.21"}}
EOF
    cat > "$proj/.npmrc" <<EOF
registry=$NEXUS/repository/npm-proxy/
min-release-age=9999
ignore-scripts=true
EOF
    rc=0
    (cd "$proj" && npm install 2>&1 | tail -5) || rc=$?
    if [[ $rc -ne 0 ]]; then
        pass "npm: client-side min-release-age=9999 blocks packages even through Nexus proxy"
    else
        fail "npm: min-release-age=9999 did NOT block — age gate bypassed by proxy?"
    fi
fi

summary

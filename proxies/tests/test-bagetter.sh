#!/usr/bin/env bash
# Tests: BaGetter NuGet proxy (http://localhost:5555)
# Start with: docker compose up -d (from proxies/)

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

BASE="http://localhost:5555"

echo "=== BaGetter (NuGet proxy, port 5555) ==="

wait_for_url "$BASE/v3/index.json" "BaGetter" 20 || { summary; exit 0; }
pass "BaGetter is reachable"

# ── Test: v3 index responds correctly ────────────────────────────────────────

index=$(curl -sf --max-time 5 "$BASE/v3/index.json" 2>/dev/null)
if echo "$index" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'resources' in d" 2>/dev/null; then
    pass "BaGetter v3/index.json is valid NuGet service index"
else
    fail "BaGetter v3/index.json is missing or malformed"
fi

# ── Test: package search endpoint works ──────────────────────────────────────

search=$(curl -sf --max-time 10 "$BASE/v3/search?q=newtonsoft&take=1" 2>/dev/null)
if echo "$search" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'data' in d" 2>/dev/null; then
    pass "BaGetter search returns results (proxying nuget.org)"
else
    fail "BaGetter search returned no results -- upstream proxy may not be configured"
fi

# ── Test: package metadata reachable ─────────────────────────────────────────

meta=$(curl -sf --max-time 10 \
    "$BASE/v3/registration/newtonsoft.json/index.json" 2>/dev/null)
if [[ -n "$meta" ]]; then
    pass "BaGetter serves Newtonsoft.Json registration metadata"
else
    fail "BaGetter did not return Newtonsoft.Json metadata"
fi

# ── Test: dotnet can restore through BaGetter ────────────────────────────────

if ! command -v dotnet &>/dev/null; then
    skip "dotnet not found"
    summary; exit 0
fi

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/test.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
  </ItemGroup>
</Project>
EOF

cat > "$WORK/NuGet.Config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local-bagetter" value="$BASE/v3/index.json" allowInsecureConnections="true" />
  </packageSources>
</configuration>
EOF

rc=0
dotnet restore "$WORK/test.csproj" --nologo -q 2>&1 | tail -3 || rc=$?
if [[ $rc -eq 0 ]]; then
    pass "dotnet restore resolves Newtonsoft.Json 13.0.3 through BaGetter proxy"
else
    fail "dotnet restore failed through BaGetter (proxy may still be caching from nuget.org)"
fi

summary

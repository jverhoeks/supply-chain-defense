#!/usr/bin/env bash
# Tests: .NET/NuGet supply chain controls
# Requirements: dotnet in PATH

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== .NET: supply chain controls ==="

NUGET_DIR="$SCRIPT_DIR/../dotnet-nuget"

if ! command -v dotnet &>/dev/null; then
    echo "  SKIP: dotnet not found"
    exit 0
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ── Test 1: restore and locked-mode work on reference project ─────────────────

test_locked_restore() {
    local proj="$WORK_DIR/restore-test"
    mkdir -p "$proj"
    cp "$NUGET_DIR/nuget.config" "$proj/"
    cp "$NUGET_DIR/SupplyChainTest.csproj" "$proj/Program.csproj"
    cp "$NUGET_DIR/Directory.Packages.props" "$proj/" 2>/dev/null || true

    # First restore generates packages.lock.json (RestorePackagesWithLockFile=true)
    local rc=0
    dotnet restore "$proj/Program.csproj" -s https://api.nuget.org/v3/index.json --nologo -q 2>&1 | tail -3 || rc=$?
    if [[ $rc -ne 0 ]]; then
        fail "dotnet restore: failed on reference project"
        return
    fi
    pass "dotnet restore: succeeds on reference project"

    # Locked mode should now pass since we just generated the lock file
    rc=0
    dotnet restore "$proj/Program.csproj" --locked-mode --nologo -q 2>&1 | tail -3 || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "dotnet restore --locked-mode: passes after lock file is generated"
    else
        fail "dotnet restore --locked-mode: failed — lock file was not generated or is stale"
    fi
}

# ── Test 2: Central Package Management config is present ─────────────────────

test_cpm_present() {
    local props="$NUGET_DIR/Directory.Packages.props"
    if [[ ! -f "$props" ]]; then
        fail "Directory.Packages.props missing — Central Package Management not configured"
        return
    fi
    if grep -q 'ManagePackageVersionsCentrally.*true' "$props"; then
        pass "Directory.Packages.props: ManagePackageVersionsCentrally=true"
    else
        fail "Directory.Packages.props: ManagePackageVersionsCentrally not enabled"
    fi
}

# ── Test 3: NuGetAudit is enabled in csproj ──────────────────────────────────

test_nuget_audit_enabled() {
    local csproj="$NUGET_DIR/SupplyChainTest.csproj"
    if grep -q '<NuGetAudit>true</NuGetAudit>' "$csproj" 2>/dev/null; then
        pass "SupplyChainTest.csproj: NuGetAudit=true (vulnerability check on restore)"
    else
        fail "SupplyChainTest.csproj: NuGetAudit is not enabled"
    fi
}

# ── Test 4: RestoreLockedMode is enabled in csproj ───────────────────────────

test_locked_mode_config() {
    local csproj="$NUGET_DIR/SupplyChainTest.csproj"
    if grep -q '<RestoreLockedMode>true</RestoreLockedMode>' "$csproj" 2>/dev/null; then
        pass "SupplyChainTest.csproj: RestoreLockedMode=true"
    else
        fail "SupplyChainTest.csproj: RestoreLockedMode not enabled"
    fi
}

# ── Test 5: source mapping is configured in nuget.config ─────────────────────

test_source_mapping() {
    local config="$NUGET_DIR/nuget.config"
    if grep -q 'packageSourceMapping' "$config" 2>/dev/null; then
        pass "nuget.config: packageSourceMapping configured (prevents dependency confusion)"
    else
        fail "nuget.config: no packageSourceMapping — packages can resolve from unexpected sources"
    fi
}

test_locked_restore
test_cpm_present
test_nuget_audit_enabled
test_locked_mode_config
test_source_mapping

summary

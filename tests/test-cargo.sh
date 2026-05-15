#!/usr/bin/env bash
# Tests: Rust/Cargo supply chain controls
# Requirements: cargo, cargo-deny in PATH

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== Rust: supply chain controls ==="

CARGO_DIR="$SCRIPT_DIR/../rust-cargo"

# ── Test 1: cargo deny check passes on the reference config ──────────────────

test_cargo_deny() {
    if ! command -v cargo-deny &>/dev/null && ! cargo deny --version &>/dev/null 2>&1; then
        echo "  SKIP: cargo-deny not found (install: cargo install cargo-deny)"
        return
    fi
    if ! command -v cargo &>/dev/null; then
        echo "  SKIP: cargo not found"
        return
    fi

    # Run individual checks: licenses needs real deps to avoid "unmatched allowance" errors,
    # so we check advisories, bans, and sources — the checks that work on an empty project.
    local rc=0
    (cd "$CARGO_DIR" && cargo deny check advisories bans sources 2>&1 | tail -5) || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "cargo deny check (advisories+bans+sources): passes on reference config"
    else
        fail "cargo deny check: failed — check deny.toml or add suppressions for false positives"
    fi
}

# ── Test 2: cargo deny check advisories specifically ─────────────────────────

test_cargo_deny_advisories() {
    if ! command -v cargo-deny &>/dev/null && ! cargo deny --version &>/dev/null 2>&1; then
        echo "  SKIP: cargo-deny not found"
        return
    fi

    local rc=0
    (cd "$CARGO_DIR" && cargo deny check advisories 2>&1 | tail -3) || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "cargo deny check advisories: no known CVEs in current dependencies"
    else
        fail "cargo deny check advisories: known vulnerability found — update or add suppression"
    fi
}

# ── Test 3: supply-chain/audits.toml exists (required for cargo-vet) ─────────

test_cargo_vet_files() {
    local audits="$CARGO_DIR/supply-chain/audits.toml"
    local config="$CARGO_DIR/supply-chain/config.toml"
    if [[ -f "$audits" ]] && [[ -f "$config" ]]; then
        pass "cargo-vet: supply-chain/audits.toml and config.toml both present"
    elif [[ ! -f "$audits" ]]; then
        fail "cargo-vet: supply-chain/audits.toml missing — cargo vet will not run"
    else
        fail "cargo-vet: supply-chain/config.toml missing"
    fi
}

# ── Test 4: deny.toml unknown-git = "deny" (no arbitrary git deps) ───────────

test_deny_git_policy() {
    local deny_toml="$CARGO_DIR/deny.toml"
    if grep -q 'unknown-git.*=.*"deny"' "$deny_toml" 2>/dev/null; then
        pass "deny.toml: unknown-git = \"deny\" (arbitrary git sources blocked)"
    else
        fail "deny.toml: unknown-git is not set to deny — git dependencies are unrestricted"
    fi
}

test_cargo_deny
test_cargo_deny_advisories
test_cargo_vet_files
test_deny_git_policy

summary

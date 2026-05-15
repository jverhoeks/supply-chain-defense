#!/usr/bin/env bash
# Tests: Java supply chain controls (Maven + Gradle)
# Requirements: mvn and/or gradle in PATH

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== Java: supply chain controls ==="

MAVEN_DIR="$SCRIPT_DIR/../java-maven"
GRADLE_DIR="$SCRIPT_DIR/../java-gradle"

# ── Maven tests ───────────────────────────────────────────────────────────────

test_maven_enforcer() {
    if ! command -v mvn &>/dev/null; then
        echo "  SKIP: mvn not found"
        return
    fi

    # Run validate phase which triggers the enforcer execution bound to it.
    # (mvn enforcer:enforce without -Drules= requires a lifecycle invocation)
    local rc=0
    (cd "$MAVEN_DIR" && mvn validate -f pom.xml -q 2>&1 | tail -5) || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "Maven Enforcer: passes on reference pom.xml (no duplicate classes, version constraints met)"
    else
        fail "Maven Enforcer: failed — check pom.xml enforcer rules"
    fi
}

test_maven_checksum_policy() {
    local settings="$MAVEN_DIR/settings.xml"
    if grep -q '<checksumPolicy>fail</checksumPolicy>' "$settings" 2>/dev/null; then
        pass "Maven settings.xml: checksumPolicy=fail (tampered artifacts break the build)"
    else
        fail "Maven settings.xml: checksumPolicy is not set to fail — default is warn, tampered artifacts pass silently"
    fi
}

test_maven_update_policy() {
    local settings="$MAVEN_DIR/settings.xml"
    if grep -q '<updatePolicy>never</updatePolicy>' "$settings" 2>/dev/null; then
        pass "Maven settings.xml: updatePolicy=never (release artifacts are not re-fetched)"
    else
        fail "Maven settings.xml: updatePolicy not set to never — release re-checking is a SNAPSHOT poisoning vector"
    fi
}

# ── Gradle tests ──────────────────────────────────────────────────────────────

test_gradle_verification_enabled() {
    local props="$GRADLE_DIR/gradle.properties"
    if grep -q '^org.gradle.dependency.verification=strict' "$props" 2>/dev/null; then
        pass "gradle.properties: dependency verification is enabled in strict mode"
    else
        fail "gradle.properties: dependency verification is not enabled — JAR content is not verified"
    fi
}

test_gradle_lock_mode() {
    local build="$GRADLE_DIR/build.gradle.kts"
    if grep -q 'LockMode.STRICT\|lockMode.*STRICT' "$build" 2>/dev/null; then
        pass "build.gradle.kts: dependency locking uses STRICT mode"
    else
        fail "build.gradle.kts: dependency lock mode is not STRICT"
    fi
}

test_gradle_syntax() {
    if ! command -v gradle &>/dev/null && [[ ! -f "$GRADLE_DIR/gradlew" ]]; then
        echo "  SKIP: gradle / gradlew not found"
        return
    fi
    local gradle_cmd="gradle"
    [[ -f "$GRADLE_DIR/gradlew" ]] && gradle_cmd="./gradlew"

    local rc=0
    # --dry-run parses the build script without executing tasks
    (cd "$GRADLE_DIR" && $gradle_cmd help --dry-run -q 2>&1 | tail -5) || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "build.gradle.kts: parses without errors"
    else
        fail "build.gradle.kts: syntax or configuration error"
    fi
}

test_maven_enforcer
test_maven_checksum_policy
test_maven_update_policy
test_gradle_verification_enabled
test_gradle_lock_mode
test_gradle_syntax

summary

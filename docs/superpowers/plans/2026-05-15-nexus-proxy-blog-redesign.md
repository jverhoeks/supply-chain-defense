# Nexus Proxy + Blog Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Nexus Repository OSS as a sixth proxy service, write tests for all five ecosystems through it, and restructure the blog post to lead with Nexus + a protection matrix.

**Architecture:** Nexus service added to existing `docker-compose.yml`; a one-shot `nexus/setup.sh` configures five proxy repos via REST API; `tests/test-nexus.sh` covers caching per ecosystem and verifies the npm client-side age gate still fires through a proxy; the blog gets a protection matrix and Nexus section inserted before the per-ecosystem configs.

**Tech Stack:** Nexus Repository OSS 3 (sonatype/nexus3), Bash, curl, existing test helpers (lib.sh), npm/uv/go/Maven/dotnet for ecosystem tests.

---

### Task 1: Add Nexus service to docker-compose.yml

**Files:**
- Modify: `proxies/docker-compose.yml`

- [ ] **Step 1: Add the nexus service block and nexus-data volume**

Open `proxies/docker-compose.yml`. Replace the `volumes:` block at the bottom with the updated version that includes `nexus-data:`, and add the nexus service before the volumes section:

```yaml
  # ── All ecosystems (npm, PyPI, Go, Maven, NuGet) ─────────────────────────
  # Port 8081. Single proxy replacing all five specialized proxies above.
  # Run: bash nexus/setup.sh  (once, after docker compose up -d)
  # RAM: ~1.5 GB at rest — heavier than all five specialized proxies combined.
  nexus:
    image: sonatype/nexus3:latest
    ports:
      - "8081:8081"
    volumes:
      - nexus-data:/nexus-data
    restart: unless-stopped
```

Add `nexus-data:` to the `volumes:` section:

```yaml
volumes:
  verdaccio-storage:
  devpi-data:
  athens-storage:
  reposilite-data:
  bagetter-data:
  nexus-data:
```

- [ ] **Step 2: Verify the compose file parses cleanly**

```bash
docker compose -f proxies/docker-compose.yml config --quiet
```
Expected: no output (valid YAML, no errors).

- [ ] **Step 3: Commit**

```bash
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage add proxies/docker-compose.yml
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage commit -m "feat: add Nexus service to docker-compose"
```

---

### Task 2: Write proxies/nexus/setup.sh

**Files:**
- Create: `proxies/nexus/setup.sh`

- [ ] **Step 1: Create the setup script**

```bash
mkdir -p /Users/jjverhoeks/src/tries/2026-05-13-minimalage/proxies/nexus
```

Write `proxies/nexus/setup.sh`:

```bash
#!/usr/bin/env bash
# Configure Nexus proxy repos for npm, PyPI, Go, Maven, NuGet.
# Run once after: docker compose up -d
# Safe to re-run — skips repos that already exist.

set -uo pipefail

NEXUS="${NEXUS_URL:-http://localhost:8081}"
ADMIN_PASS="admin123"
CONTAINER="${NEXUS_CONTAINER:-proxies-nexus-1}"

# ── Wait for Nexus ────────────────────────────────────────────────────────────
echo "Waiting for Nexus to start (may take 1–2 min)..."
i=0
until curl -sf "$NEXUS/service/rest/v1/status/writable" > /dev/null 2>&1; do
    i=$((i+1))
    [[ $i -ge 120 ]] && { echo "ERROR: Nexus did not start in 6 min"; exit 1; }
    sleep 3
done
echo "Nexus is up."

# ── Read and change initial admin password ────────────────────────────────────
INIT_PASS=$(docker exec "$CONTAINER" cat /nexus-data/admin.password 2>/dev/null || echo "")
if [[ -z "$INIT_PASS" ]]; then
    echo "No admin.password file found — assuming password already changed."
    INIT_PASS="$ADMIN_PASS"
fi

curl -sf -X PUT "$NEXUS/service/rest/v1/security/users/admin/change-password" \
    -u "admin:$INIT_PASS" \
    -H "Content-Type: text/plain" \
    -d "$ADMIN_PASS" > /dev/null 2>&1 \
    && echo "Admin password set to '$ADMIN_PASS'." \
    || echo "Password already set (idempotent)."

# ── Enable anonymous read ─────────────────────────────────────────────────────
curl -sf -X PUT "$NEXUS/service/rest/v1/security/anonymous" \
    -u "admin:$ADMIN_PASS" \
    -H "Content-Type: application/json" \
    -d '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' > /dev/null
echo "Anonymous read access enabled."

# ── Helper: create a proxy repo if it does not already exist ─────────────────
create_repo() {
    local format="$1"
    local name="$2"
    local payload="$3"
    if curl -sf "$NEXUS/service/rest/v1/repositories/$name" \
            -u "admin:$ADMIN_PASS" > /dev/null 2>&1; then
        echo "  $name: already exists, skipping."
        return
    fi
    local rc=0
    curl -sf -X POST "$NEXUS/service/rest/v1/repositories/$format/proxy" \
        -u "admin:$ADMIN_PASS" \
        -H "Content-Type: application/json" \
        -d "$payload" > /dev/null || rc=$?
    [[ $rc -eq 0 ]] \
        && echo "  $name: created." \
        || echo "  $name: FAILED (exit $rc)"
}

echo "Creating proxy repositories..."

create_repo npm npm-proxy '{
  "name":"npm-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true}
}'

create_repo pypi pypi-proxy '{
  "name":"pypi-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://pypi.org","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true}
}'

create_repo go go-proxy '{
  "name":"go-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://proxy.golang.org","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true}
}'

create_repo maven2 maven-central '{
  "name":"maven-central","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},
  "proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "maven":{"versionPolicy":"MIXED","layoutPolicy":"STRICT","contentDisposition":"ATTACHMENT"}
}'

create_repo nuget nuget-proxy '{
  "name":"nuget-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://api.nuget.org/v3/index.json","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "nugetProxy":{"v3ServiceUrl":"","queryCacheItemMaxAge":3600}
}'

echo ""
echo "Nexus setup complete. Repo URLs:"
echo "  npm:   $NEXUS/repository/npm-proxy/"
echo "  PyPI:  $NEXUS/repository/pypi-proxy/simple/"
echo "  Go:    $NEXUS/repository/go-proxy/"
echo "  Maven: $NEXUS/repository/maven-central/"
echo "  NuGet: $NEXUS/repository/nuget-proxy/index.json"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x /Users/jjverhoeks/src/tries/2026-05-13-minimalage/proxies/nexus/setup.sh
```

- [ ] **Step 3: Commit**

```bash
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage add proxies/nexus/setup.sh
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage commit -m "feat: add Nexus setup script"
```

---

### Task 3: Start Nexus and run setup.sh

**Files:** none (verification only)

- [ ] **Step 1: Start the Nexus container**

```bash
docker compose -f /Users/jjverhoeks/src/tries/2026-05-13-minimalage/proxies/docker-compose.yml \
    up -d nexus
```

Expected output includes: `Container proxies-nexus-1 Started`

- [ ] **Step 2: Run setup.sh and verify all repos are created**

```bash
bash /Users/jjverhoeks/src/tries/2026-05-13-minimalage/proxies/nexus/setup.sh
```

Expected output (abbreviated):
```
Waiting for Nexus to start (may take 1–2 min)...
Nexus is up.
Admin password set to 'admin123'.
Anonymous read access enabled.
Creating proxy repositories...
  npm-proxy: created.
  pypi-proxy: created.
  go-proxy: created.
  maven-central: created.
  nuget-proxy: created.

Nexus setup complete. Repo URLs:
  npm:   http://localhost:8081/repository/npm-proxy/
  ...
```

- [ ] **Step 3: Verify each repo responds to a curl request**

```bash
for repo in npm-proxy pypi-proxy go-proxy maven-central nuget-proxy; do
    code=$(curl -so /dev/null -w "%{http_code}" \
        "http://localhost:8081/repository/$repo/" 2>/dev/null)
    echo "$code  $repo"
done
```

Expected: `200` for all five repos.

---

### Task 4: Write proxies/tests/test-nexus.sh

**Files:**
- Create: `proxies/tests/test-nexus.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# Tests: Nexus all-ecosystem proxy (http://localhost:8081)
# Start with: docker compose up -d nexus && bash nexus/setup.sh

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

NEXUS="http://localhost:8081"

echo "=== Nexus (all-ecosystem proxy, port 8081) ==="

wait_for_url "$NEXUS/service/rest/v1/status" "Nexus" 30 || { summary; exit 0; }
pass "Nexus is reachable"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# ── Test: all proxy repos exist ───────────────────────────────────────────────

for repo in npm-proxy pypi-proxy go-proxy maven-central nuget-proxy; do
    if curl -sf "$NEXUS/service/rest/v1/repositories/$repo" \
            -u "admin:admin123" > /dev/null 2>&1; then
        pass "Repository '$repo' exists"
    else
        fail "Repository '$repo' missing — run: bash nexus/setup.sh"
    fi
done

# ── Test: npm installs through Nexus ─────────────────────────────────────────

if command -v npm &>/dev/null; then
    proj="$WORK/npm-proj"
    mkdir -p "$proj"
    cat > "$proj/package.json" <<'EOF'
{"name":"test","version":"1.0.0","private":true,"dependencies":{"lodash":"4.17.21"}}
EOF
    cat > "$proj/.npmrc" <<EOF
registry=$NEXUS/repository/npm-proxy/
ignore-scripts=true
EOF
    rc=0
    (cd "$proj" && npm install 2>&1 | tail -3) || rc=$?
    [[ $rc -eq 0 ]] \
        && pass "npm: lodash 4.17.21 installs through Nexus npm-proxy" \
        || fail "npm: install through Nexus npm-proxy failed"
fi

# ── Test: uv resolves PyPI through Nexus ─────────────────────────────────────

if command -v uv &>/dev/null; then
    proj="$WORK/pypi-proj"
    mkdir -p "$proj"
    cat > "$proj/uv.toml" <<EOF
[pip]
index-url = "$NEXUS/repository/pypi-proxy/simple/"
require-hashes = false
only-binary = [":all:"]
EOF
    rc=0
    uv pip install --config-file "$proj/uv.toml" --dry-run requests \
        2>&1 | tail -2 || rc=$?
    [[ $rc -eq 0 ]] \
        && pass "uv: 'requests' resolves through Nexus pypi-proxy" \
        || fail "uv: PyPI resolution through Nexus pypi-proxy failed"
fi

# ── Test: Go downloads module through Nexus ───────────────────────────────────

if command -v go &>/dev/null; then
    proj="$WORK/go-proj"
    mkdir -p "$proj"
    cat > "$proj/go.mod" <<'EOF'
module supplychain/nexustest
go 1.21
require golang.org/x/text v0.14.0
EOF
    rc=0
    (cd "$proj" && GOPROXY="$NEXUS/repository/go-proxy,off" \
        GONOSUMDB="*" GOFLAGS="-mod=mod" \
        go mod download golang.org/x/text@v0.14.0 2>&1 | tail -3) || rc=$?
    [[ $rc -eq 0 ]] \
        && pass "go: golang.org/x/text@v0.14.0 downloads through Nexus go-proxy" \
        || fail "go: module download through Nexus go-proxy failed"
fi

# ── Test: Maven fetches POM through Nexus ────────────────────────────────────

pom=$(curl -sf --max-time 15 \
    "$NEXUS/repository/maven-central/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.pom" \
    2>/dev/null)
if echo "$pom" | grep -q "artifactId"; then
    pass "Maven: commons-lang3 POM fetches through Nexus maven-central"
else
    fail "Maven: POM fetch through Nexus maven-central failed"
fi

# ── Test: dotnet restores NuGet package through Nexus ────────────────────────

if command -v dotnet &>/dev/null; then
    proj="$WORK/nuget-proj"
    mkdir -p "$proj"
    cat > "$proj/test.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net9.0</TargetFramework></PropertyGroup>
  <ItemGroup><PackageReference Include="Newtonsoft.Json" Version="13.0.3" /></ItemGroup>
</Project>
EOF
    cat > "$proj/NuGet.Config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nexus-nuget" value="$NEXUS/repository/nuget-proxy/index.json"
         allowInsecureConnections="true" />
  </packageSources>
</configuration>
EOF
    rc=0
    dotnet restore "$proj/test.csproj" --nologo -q 2>&1 | tail -3 || rc=$?
    [[ $rc -eq 0 ]] \
        && pass "dotnet: Newtonsoft.Json 13.0.3 restores through Nexus nuget-proxy" \
        || fail "dotnet: restore through Nexus nuget-proxy failed"
fi

# ── Test: client-side age gate still fires when routed through Nexus ─────────
# min-release-age=9999 (days) blocks all packages — none are 27 years old.
# This proves the age gate config is respected even when a proxy is in the path.

if command -v npm &>/dev/null; then
    proj="$WORK/npm-age-proj"
    mkdir -p "$proj"
    cat > "$proj/package.json" <<'EOF'
{"name":"test","version":"1.0.0","private":true,"dependencies":{"lodash":"4.17.21"}}
EOF
    cat > "$proj/.npmrc" <<EOF
registry=$NEXUS/repository/npm-proxy/
min-release-age=9999
ignore-scripts=true
EOF
    rc=0
    (cd "$proj" && npm install 2>&1 | tail -3) || rc=$?
    [[ $rc -ne 0 ]] \
        && pass "npm: client-side min-release-age=9999 blocks packages even through Nexus proxy" \
        || fail "npm: min-release-age=9999 did NOT block — age gate bypassed by proxy?"
fi

summary
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x /Users/jjverhoeks/src/tries/2026-05-13-minimalage/proxies/tests/test-nexus.sh
```

- [ ] **Step 3: Run the test against the live Nexus**

```bash
cd /Users/jjverhoeks/src/tries/2026-05-13-minimalage && \
    bash proxies/tests/test-nexus.sh 2>&1
```

Expected: all available tool tests pass (npm, uv, go, maven curl, dotnet — skipped gracefully if tool not installed); age gate test passes.

- [ ] **Step 4: Commit**

```bash
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage add proxies/tests/test-nexus.sh
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage commit -m "test: add Nexus all-ecosystem proxy test suite"
```

---

### Task 5: Add test-nexus.sh to run-all.sh

**Files:**
- Modify: `proxies/tests/run-all.sh`

- [ ] **Step 1: Add test-nexus.sh as a sixth suite**

The current `run-all.sh` content:
```bash
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

echo "==============================="
echo "Suites: $PASS passed, $FAIL failed"
echo "==============================="
[[ $FAIL -eq 0 ]]
```

Add `run test-nexus.sh` after `run test-bagetter.sh`:

```bash
run test-nexus.sh
```

- [ ] **Step 2: Run the full suite and verify all six pass**

```bash
cd /Users/jjverhoeks/src/tries/2026-05-13-minimalage && \
    bash proxies/tests/run-all.sh 2>&1
```

Expected final line: `Suites: 6 passed, 0 failed`

- [ ] **Step 3: Commit**

```bash
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage add proxies/tests/run-all.sh
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage commit -m "test: add Nexus to proxy test suite runner"
```

---

### Task 6: Insert protection matrix + Nexus section into blog

**Files:**
- Modify: `2026-05-14-npm-install-shouldnt-run-your-code.md` (lines 52–54)

The current text around the insertion point:
```markdown
Units: npm uses **days**. pnpm, yarn, and bun use **minutes** (10080 min = 7 days).

---

## Per-Ecosystem Config
```

Replace with this entire block (matrix + Nexus section + reframed per-ecosystem header):

```markdown
Units: npm uses **days**. pnpm, yarn, and bun use **minutes** (10080 min = 7 days).

---

## What Each Ecosystem Can and Cannot Enforce

Not every ecosystem supports the same controls. This table shows the ceiling — what is achievable even with perfect configuration.

| Ecosystem | Release-age gate | Script blocking | Proxy / mirror | Integrity check |
|-----------|:----------------:|:---------------:|:--------------:|:---------------:|
| npm / pnpm / yarn / bun | ✓ client-side<br>**✓ server-side (Verdaccio)** | ✓ | ✓ | ✓ |
| Python (pip / uv) | ✓ uv only, client-side | ✓ `only-binary` | ✓ | ✓ |
| Go | — | n/a | ✓ | ✓ (GOSUMDB) |
| Maven / Gradle | — | n/a | ✓ | ✓ |
| NuGet | — | n/a | ✓ | ✓ |
| Rust / Cargo | — | — (build.rs) | — (no OSS proxy) | ✓ cargo-deny + vet |

**Rust is the weakest ecosystem.** There is no open-source Cargo proxy, no way to globally disable `build.rs`, and no quarantine window. Policy tools (`cargo-deny`, `cargo-vet`) are the only mitigations.

**pip has no built-in age gate.** The `exclude-newer` setting exists only in uv. pip users need a proxy that enforces the quarantine window server-side, or should switch to uv.

**Verdaccio is the only open-source proxy with server-side age enforcement.** Every other proxy enforces the age gate at the client only.

---

## One Proxy for Everything: Nexus

Running one proxy instead of five simplifies configuration significantly: every ecosystem gets a single URL, one set of credentials, and one place to look when something breaks.

**Nexus Repository OSS** is free, Apache-licensed, and proxies npm, PyPI, Go modules, Maven/Gradle, NuGet, and a dozen other formats from a single container. It does not support Cargo — that is a Nexus Pro feature only.

```bash
# Start Nexus alongside the other proxies
docker compose up -d nexus
# First-time setup: creates npm, PyPI, Go, Maven, NuGet proxy repos (~1-2 min)
bash nexus/setup.sh
```

`setup.sh` is idempotent — safe to re-run if interrupted.

### Proxy URLs

Point each tool at the matching Nexus repository:

| Tool | Setting | Value |
|------|---------|-------|
| npm / pnpm / bun | `.npmrc` → `registry` | `http://localhost:8081/repository/npm-proxy/` |
| yarn | `.yarnrc.yml` → `npmRegistryServer` | `http://localhost:8081/repository/npm-proxy/` |
| pip | `pip.conf` → `index-url` | `http://localhost:8081/repository/pypi-proxy/simple/` |
| uv | `uv.toml` → `[pip] index-url` | `http://localhost:8081/repository/pypi-proxy/simple/` |
| Go | `GOPROXY` env | `http://localhost:8081/repository/go-proxy,off` |
| Maven | `settings.xml` mirror `<url>` | `http://localhost:8081/repository/maven-central/` |
| NuGet | `nuget.config` source `value` | `http://localhost:8081/repository/nuget-proxy/index.json` |

### Age gate through Nexus

Nexus caches and air-gaps every ecosystem. The release-age gate stays client-side regardless of which proxy you use — the per-ecosystem configs below apply unchanged.

One exception: only Verdaccio enforces the npm age gate server-side. If you need that guarantee at the org level without running both proxies, point Verdaccio's upstream at Nexus's npm-proxy repo instead of public npmjs.

### What Nexus does not protect

Nexus does not disable install scripts. The `ignore-scripts`, `allowBuilds`, and `only-binary` settings in the per-ecosystem configs below are still necessary — they are client-side controls that Nexus cannot replace.

> **RAM:** Nexus uses ~1.5 GB at rest. For resource-constrained environments, the five purpose-built lightweight proxies total ~150 MB combined — see [Lightweight Proxies (Alternative to Nexus)](#lightweight-proxies-alternative-to-nexus).

---

## Per-Ecosystem Config

If you are running Nexus, combine these age-gate and script-blocking configs with the Nexus URLs above. If you are not running a central proxy, these configs work against the public registries directly.

```

- [ ] **Step 2: Verify the section renders correctly (visual check)**

Open the blog file and confirm:
- Protection matrix table appears after Quick Reference
- Nexus section appears before Per-Ecosystem Config
- Per-Ecosystem Config has the new framing paragraph

- [ ] **Step 3: Commit**

```bash
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage \
    add "2026-05-14-npm-install-shouldnt-run-your-code.md"
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage \
    commit -m "docs: add protection matrix and Nexus section to blog"
```

---

### Task 7: Restructure the Private Proxy section

**Files:**
- Modify: `2026-05-14-npm-install-shouldnt-run-your-code.md` (lines ~384–435)

The current section header and opening paragraphs:
```markdown
## Private Proxy / Internal Mirror

The per-project configs above harden individual machines and CI pipelines. A private proxy hardens the organisation.

Instead of each developer pulling from the public registry, they pull from an internal mirror (Artifactory, Nexus, Azure Artifacts, AWS CodeArtifact, or self-hosted Verdaccio). The proxy is the only entity that talks to the public internet. Before a package is served, the proxy can:

- Enforce release age centrally: no per-project config needed, no developer can accidentally disable it
- Block install scripts before the tarball reaches developers
- Scan for vulnerabilities (Xray, Snyk, Socket.dev integrations) and quarantine malicious packages
- Cache approved versions so a yanked or compromised version cannot be pulled even if a developer pins to it

The per-project configs above are still worth having as defence in depth, but a private proxy means a misconfigured `.npmrc` on one developer's machine does not become an incident.

### Pointing each package manager at the proxy

**npm / pnpm / bun** - one line in `.npmrc`:
```ini
registry=https://npm.internal.company.com/
```

**yarn**:
```yaml
npmRegistryServer: "https://npm.internal.company.com"
```

**uv / pip**:
```toml
# uv.toml
[pip]
index-url = "https://pypi.internal.company.com/simple/"
```

**Go** - set GOPROXY to your Athens or JFrog instance:
```bash
export GOPROXY="https://go.internal.company.com,off"
```

**Maven** - set the mirror in `settings.xml` (already shown above).

**NuGet** - set the source in `nuget.config` (already shown above).

Do not add a second index as a fallback. Additional indexes are a dependency confusion risk: the package manager picks the highest version across all sources, so an attacker can register a public package with a higher version than your internal one.
```

Replace with:

```markdown
## Lightweight Proxies (Alternative to Nexus)

If RAM is constrained or you prefer purpose-built tooling, five specialized proxies cover the same ground as Nexus at a fraction of the cost: ~150 MB combined vs ~1.5 GB for Nexus.

Each proxy is a drop-in registry replacement for one ecosystem. Verdaccio is the only option in this stack with server-side release-age enforcement.

| Proxy | Ecosystem | Port | Age enforcement |
|-------|-----------|------|-----------------|
| Verdaccio | npm / pnpm / yarn / bun | 4873 | **Server-side** (`minAgeDays: 7`) |
| devpi | pip / uv | 3141 | Client-side only |
| Athens | Go modules | 3000 | Client-side only |
| Reposilite | Maven / Gradle | 8080 | Client-side only |
| BaGetter | NuGet | 5555 | Client-side only |

```bash
cd proxies/
docker compose up -d
```

Point each tool at the local port:

**npm / pnpm / bun** — `.npmrc`:
```ini
registry=http://localhost:4873/
```

**yarn** — `.yarnrc.yml`:
```yaml
npmRegistryServer: "http://localhost:4873"
```

**uv / pip** — `uv.toml`:
```toml
[pip]
index-url = "http://localhost:3141/root/pypi/+simple/"
```

**Go**:
```bash
export GOPROXY="http://localhost:3000,off"
```

**Maven** — `settings.xml`:
```xml
<mirror>
  <id>local-reposilite</id>
  <mirrorOf>*</mirrorOf>
  <url>http://localhost:8080/central</url>
  <checksumPolicy>fail</checksumPolicy>
</mirror>
```

**NuGet** — `nuget.config`:
```xml
<packageSources>
  <clear />
  <add key="local" value="http://localhost:5555/v3/index.json"
       allowInsecureConnections="true" />
</packageSources>
```

Do not add a second index as a fallback. Additional indexes are a dependency confusion risk: the package manager picks the highest version across all sources, so an attacker can register a public package with a higher version than your internal one.
```

- [ ] **Step 2: Verify the section renders correctly**

Confirm the old "Private Proxy / Internal Mirror" header is gone and replaced with "Lightweight Proxies (Alternative to Nexus)".

- [ ] **Step 3: Commit**

```bash
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage \
    add "2026-05-14-npm-install-shouldnt-run-your-code.md"
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage \
    commit -m "docs: rename Private Proxy section to Lightweight Proxies"
```

---

### Task 8: Update proxies/README.md

**Files:**
- Modify: `proxies/README.md`

- [ ] **Step 1: Update the What runs where table**

Current table:
```markdown
| Proxy | Ecosystem | Port | Age enforcement | Cache |
|-------|-----------|------|----------------|-------|
| Verdaccio | npm / pnpm / yarn / bun | 4873 | **Server-side** via `@verdaccio/package-filter` `minAgeDays: 7` | yes |
| devpi | pip / uv | 3141 | Client-side only (`exclude-newer = "P7D"` in uv.toml) | yes |
| Athens | Go modules | 3000 | Client-side only (`GOPROXY=http://localhost:3000,off`) | yes (immutable) |
| Reposilite | Maven / Gradle | 8080 | Client-side only (`checksumPolicy=fail` in settings.xml) | yes |
| BaGetter | NuGet | 5555 | Client-side only (`RestoreLockedMode` + `NuGetAudit`) | yes |

Verdaccio is the only open source proxy with native release-age gating.
All other ecosystems enforce the age gate at the client (configs in this repo).
```

Replace with:

```markdown
### Nexus (single proxy, all ecosystems)

| Ecosystem | Port | Age enforcement |
|-----------|------|-----------------|
| npm / PyPI / Go / Maven / NuGet | 8081 | Client-side only (all ecosystems) |

```bash
docker compose up -d nexus
bash nexus/setup.sh  # first time only; idempotent
```

Nexus RAM: ~1.5 GB at rest.

### Lightweight proxies (specialized, lower RAM)

| Proxy | Ecosystem | Port | Age enforcement | Cache |
|-------|-----------|------|----------------|-------|
| Verdaccio | npm / pnpm / yarn / bun | 4873 | **Server-side** via `@verdaccio/package-filter` `minAgeDays: 7` | yes |
| devpi | pip / uv | 3141 | Client-side only (`exclude-newer = "P7D"` in uv.toml) | yes |
| Athens | Go modules | 3000 | Client-side only (`GOPROXY=http://localhost:3000,off`) | yes (immutable) |
| Reposilite | Maven / Gradle | 8080 | Client-side only (`checksumPolicy=fail` in settings.xml) | yes |
| BaGetter | NuGet | 5555 | Client-side only (`RestoreLockedMode` + `NuGetAudit`) | yes |

Total RAM: ~150 MB. Verdaccio is the only open source proxy with native release-age gating.
```

- [ ] **Step 2: Update Point your tools section to include Nexus URLs**

Add a "Nexus" subsection at the top of "Point your tools at the proxies":

```markdown
## Point your tools at the proxies

### Option A: Nexus (single URL per ecosystem)

| Tool | Config | Value |
|------|--------|-------|
| npm / pnpm / bun | `.npmrc` registry | `http://localhost:8081/repository/npm-proxy/` |
| yarn | `.yarnrc.yml` npmRegistryServer | `http://localhost:8081/repository/npm-proxy/` |
| pip | `pip.conf` index-url | `http://localhost:8081/repository/pypi-proxy/simple/` |
| uv | `uv.toml` [pip] index-url | `http://localhost:8081/repository/pypi-proxy/simple/` |
| Go | `GOPROXY` env | `http://localhost:8081/repository/go-proxy,off` |
| Maven | `settings.xml` mirror url | `http://localhost:8081/repository/maven-central/` |
| NuGet | `nuget.config` source | `http://localhost:8081/repository/nuget-proxy/index.json` |

### Option B: Lightweight proxies (per-ecosystem ports)
```

- [ ] **Step 3: Commit**

```bash
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage add proxies/README.md
git -C /Users/jjverhoeks/src/tries/2026-05-13-minimalage commit -m "docs: update proxies README with Nexus setup"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| Nexus service in docker-compose.yml | Task 1 |
| nexus/setup.sh with all 5 repos, idempotent | Task 2 |
| Smoke test Nexus starts + repos created | Task 3 |
| test-nexus.sh: caching for all ecosystems | Task 4 |
| test-nexus.sh: npm age gate through proxy | Task 4 |
| test-nexus.sh added to run-all.sh | Task 5 |
| Blog: protection matrix | Task 6 |
| Blog: Nexus section with URLs + age gate note | Task 6 |
| Blog: per-ecosystem section reframed | Task 6 |
| Blog: Nexus section age gate note (A+B) | Task 6 |
| Blog: Lightweight Proxies section rename | Task 7 |
| README updated | Task 8 |

**No gaps found.**

**Placeholder scan:** No TBDs, TODOs, or "similar to Task N" references. All code blocks are complete.

**Type consistency:** `create_repo` function signature used consistently in setup.sh. Test helper `wait_for_url` / `pass` / `fail` / `summary` match existing `lib.sh` interface. Repo names (`npm-proxy`, `pypi-proxy`, `go-proxy`, `maven-central`, `nuget-proxy`) consistent across setup.sh, test-nexus.sh, blog, and README.

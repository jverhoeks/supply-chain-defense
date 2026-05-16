---
title: "Supply Chain Attacks Hit Every Ecosystem. Here's How to Defend Yours."
description: "Supply chain attacks on package registries are surging across npm, PyPI, Go, Maven, NuGet, and Cargo. Two controls block the majority: a quarantine window and disabled install scripts. Here's the exact config for every ecosystem, a one-command Nexus proxy, and shell tests you can run today."
pubDate: "2026-05-14"
author: "Jacob Verhoeks"
tags:
  - "security"
  - "supply-chain"
  - "npm"
  - "python"
  - "go"
  - "java"
  - "dotnet"
  - "rust"
  - "php"
  - "package-manager"
  - "devops"
---

# Supply Chain Attacks Hit Every Ecosystem. Here's How to Defend Yours.

Supply chain attacks on package registries are no longer an npm problem. In March 2026, axios was compromised via a stolen maintainer token — two poisoned versions published, a cross-platform RAT phoning home within two seconds of `npm install`. The same attack pattern has hit PyPI, RubyGems, and Maven Central. The install step is the attack surface, and it exists in every language.

The good news: two controls block the majority of these attacks regardless of ecosystem. This post covers the exact config for npm, pnpm, yarn, bun, pip, uv, Go, Maven, Gradle, NuGet, Cargo, and PHP/Composer — plus a one-command proxy setup that enforces these controls org-wide, and shell tests you can run today to verify your config actually works.

---

## The Two Controls That Matter Most

### 1. Minimum release age (quarantine period)

The pattern of most supply chain attacks: compromise a package, publish a malicious version, and hope developers install it before it is pulled. A quarantine window breaks this. If your toolchain refuses packages published in the last 7 days, the attacker has to maintain an undetected compromise for a week — long enough for the community to notice and the registry to yank the version.

This control is available in npm, pnpm, yarn, bun, and uv. Go, Maven, Gradle, NuGet, and Cargo have no native quarantine setting; for those, a private proxy is the equivalent control.

### 2. Block install scripts (postinstall RCE prevention)

`postinstall` hooks execute arbitrary code the moment you run an install command. This is the delivery mechanism for most supply chain payloads — the malicious code runs before you even import the package. Disabling install scripts globally, with explicit opt-in for the handful of packages that legitimately need them (native compilers, binary fetchers), eliminates this vector.

This control exists in npm, pnpm, yarn, bun, and uv (`only-binary`). Go, Maven, Gradle, and NuGet have no install scripts by design. Rust is the exception: `build.rs` runs arbitrary code at compile time and cannot be globally disabled.

---

## Quick Reference

| Ecosystem | Tool | Config file | Min age (7 days) | Block scripts |
|-----------|------|-------------|-----------------|---------------|
| Node.js | npm >= 11.10 | `.npmrc` | `min-release-age=7` | `ignore-scripts=true` |
| Node.js | pnpm v10 >= 10.16 | `.npmrc` | `minimumReleaseAge=10080` | `ignore-scripts=true` |
| Node.js | pnpm v11 | `.npmrc` + `pnpm-workspace.yaml` | `minimumReleaseAge=10080` | `allowBuilds: {}` |
| Node.js | yarn >= 4.10 | `.yarnrc.yml` | `npmMinimalAgeGate: 10080` | `enableScripts: false` |
| Node.js | bun >= 1.3 | `bunfig.toml` | `minimumReleaseAge = 10080` | `ignore-scripts = true` |
| Python | uv | `uv.toml` | `exclude-newer = "P7D"` | `only-binary = [":all:"]` |
| Python | pip | `pip.conf` | none (use private proxy) | `only-binary = :all:` |
| Go | go | `GOENV` / CI env | none (use private proxy) | no install scripts by design |
| Rust | cargo | `deny.toml` + `supply-chain/` | none (use private proxy) | no off switch; use cargo-vet + cargo-deny |
| Java | Maven | `pom.xml` + `settings.xml` | none (use private proxy) | plugins run at build, not install; declared explicitly in pom.xml |
| Java | Gradle | `build.gradle.kts` + `gradle.properties` | none (use private proxy) | plugins run at build, not install; declared explicitly in build.gradle |
| .NET | NuGet | `nuget.config` + `*.csproj` | none (use private proxy) | no install scripts; MSBuild targets run at build; IL weaving is the threat |
| PHP | Composer | `composer.json` | none (use private proxy) | `--no-scripts` flag + `allow-plugins: {}` |

Units: npm uses **days**. pnpm, yarn, and bun use **minutes** (10080 min = 7 days).

---

## What Each Ecosystem Can and Cannot Enforce

Not every ecosystem supports the same controls. This table shows the ceiling — what is achievable even with perfect configuration.

| Ecosystem | Runs code on install | Release-age gate | Script blocking | Proxy / mirror | Integrity check |
|-----------|:-------------------:|:----------------:|:---------------:|:--------------:|:---------------:|
| npm / pnpm / yarn / bun | ✓ postinstall | ✓ client-side<br>**✓ server-side (Verdaccio, escrow)** | ✓ | ✓ | ✓ |
| Python (pip / uv) | ✓ sdist only | ✓ uv only, client-side<br>**✓ server-side (escrow)** | ✓ `only-binary` | ✓ | ✓ |
| PHP / Composer | ✓ post-install-cmd | — | ✓ `--no-scripts` | Partial (Satis/Nexus) | ✓ |
| Go | — | **✓ server-side (escrow)** | n/a | ✓ | ✓ (GOSUMDB) |
| Maven / Gradle | — (build only¹) | — | n/a | ✓ | ✓ |
| NuGet | — (build only²) | — | n/a | ✓ | ✓ |
| Rust / Cargo | ✓ build.rs | — | — (no off switch) | — (no OSS proxy) | ✓ cargo-deny + vet |

¹ Maven/Gradle plugins run during `mvn install` / `gradle build` but only those explicitly declared in your `pom.xml` / `build.gradle`. Transitive dependencies cannot silently inject build code.

² NuGet MSBuild `.targets` and IL weavers activate at `dotnet build`, not `dotnet restore`.

**Rust is the weakest ecosystem.** There is no open-source Cargo proxy, `build.rs` cannot be globally disabled, and there is no quarantine window. Policy tools (`cargo-deny`, `cargo-vet`) are the only mitigations.

**pip has no built-in age gate.** The `exclude-newer` setting exists only in uv. pip users need a proxy that enforces the quarantine window server-side, or should switch to uv.

**PHP/Composer has no native age gate.** Use a private Packagist mirror (Satis or Nexus) for org-wide enforcement.

**Verdaccio and [escrow](https://github.com/jverhoeks/escrow) are the only open-source proxies with server-side age enforcement.** escrow covers npm, PyPI, and Go modules in a single binary. Every other proxy enforces the age gate at the client only.

---

## One Proxy for Everything: Nexus

Running one proxy instead of five simplifies configuration significantly: every ecosystem gets a single URL, one set of credentials, and one place to look when something breaks.

**Nexus Repository OSS** is free, Apache-licensed, and proxies npm, PyPI, Go modules, Maven/Gradle, NuGet, PHP/Composer, and a dozen other formats from a single container. It does not support Cargo — that is a Nexus Pro feature only.

```bash
# Start Nexus alongside the other proxies
docker compose up -d nexus
# First-time setup: creates npm, PyPI, Go, Maven, NuGet, Composer proxy repos (~1-2 min)
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
| Composer | `composer.json` → `repositories[0].url` | `http://localhost:8081/repository/composer-proxy/` |

### Age gate through Nexus

Nexus caches and air-gaps every ecosystem. The release-age gate stays client-side regardless of which proxy you use — the per-ecosystem configs below apply unchanged.

One exception: only Verdaccio enforces the npm age gate server-side. If you need that guarantee at the org level without running both proxies, point Verdaccio's upstream at Nexus's npm-proxy repo instead of public npmjs.

### What Nexus does not protect

Nexus does not disable install scripts. The `ignore-scripts`, `allowBuilds`, and `only-binary` settings in the per-ecosystem configs below are still necessary — they are client-side controls that Nexus cannot replace.

> **RAM:** Nexus uses ~1.5 GB at rest. For resource-constrained environments, the five purpose-built lightweight proxies total ~150 MB combined — see [Lightweight Proxies (Alternative to Nexus)](#lightweight-proxies-alternative-to-nexus).

---

## Per-Ecosystem Config

If you are running Nexus, combine these age-gate and script-blocking configs with the Nexus URLs above. If you are not running a central proxy, these configs work against the public registries directly.

### npm (>= 11.10)

```ini
# .npmrc
min-release-age=7       # days - npm uses DAYS, not minutes
ignore-scripts=true
allow-git=false         # requires npm >= 11.10; blocks git dependency execution
registry=https://registry.npmjs.org/
```

> **Unit gotcha**: npm uses **days**. pnpm and yarn use **minutes** (10080 = 7 days). Easy to mix up.

> **`ignore-scripts` does not block git dependencies.** npm calls the system `git` binary directly to fetch git-hosted packages — this happens outside the lifecycle hook system, so `ignore-scripts=true` has no effect on it. Worse, a malicious package can include its own `.npmrc` that overrides which binary npm treats as `git`, turning a git dependency install into arbitrary code execution. `allow-git=false` shuts this off entirely by blocking all git-protocol dependencies. Requires npm >= 11.10. See [I thought ignore-scripts made npm installs safe. It doesn't.](https://thinkingthroughcode.medium.com/i-thought-ignore-scripts-made-npm-installs-safe-it-doesnt-f409b852e7c5)

CI command: `npm ci`

---

### pnpm v10 (>= 10.16)

```ini
# .npmrc
minimumReleaseAge=10080   # minutes = 7 days
ignore-scripts=true
blockExoticSubdeps=true
registry=https://registry.npmjs.org/
```

CI command: `pnpm install --frozen-lockfile`

---

### pnpm v11 -- breaking change

pnpm 11 moved build policy out of `.npmrc`. **If you put `allowBuilds` or `strictDepBuilds` in `.npmrc`, they are silently ignored.**

```ini
# .npmrc -- auth and registry ONLY in v11
minimumReleaseAge=10080
registry=https://registry.npmjs.org/
```

```yaml
# pnpm-workspace.yaml -- build policy lives here
minimumReleaseAge: 10080   # default in v11 is 1440 (1 day); set explicitly for clarity

allowBuilds: {}            # empty = no package may run build scripts
strictDepBuilds: true      # unlisted packages are an error, not a warning
blockExoticSubdeps: true
```

To allow a specific package (e.g. esbuild's native binary fetcher):
```yaml
allowBuilds:
  esbuild: true
```

CI command: `pnpm install --frozen-lockfile`

---

### Yarn Berry (>= 4.10)

```yaml
# .yarnrc.yml
npmMinimalAgeGate: 10080   # minutes = 7 days; requires yarn >= 4.10
enableScripts: false        # blocks postinstall globally
enableHardenedMode: true    # validates yarn.lock against registry at install time
checksumBehavior: throw
nodeLinker: node-modules
npmRegistryServer: "https://registry.npmjs.org"
```

To allow scripts for a specific package:
```json
"dependenciesMeta": {
  "esbuild": { "built": true }
}
```

CI command: `yarn install --immutable`

---

### Bun (>= 1.3)

```toml
# bunfig.toml
[install]
minimumReleaseAge = 10080   # minutes = 7 days
ignore-scripts = true
registry = "https://registry.npmjs.org/"
```

To allow scripts for a specific package: add `"trustedDependencies": ["esbuild"]` in `package.json`.

CI command: `bun install --frozen-lockfile`

---

### uv (Python)

```toml
# uv.toml
exclude-newer = "P7D"   # ISO 8601 duration; also accepts "7 days" or an RFC 3339 timestamp

[pip]
require-hashes = true
only-binary = [":all:"]   # never run setup.py; blocks install-time RCE entirely
```

> **`setup.py` is RCE.** Installing a source distribution runs arbitrary Python at install time. `only-binary = [":all:"]` is the only complete mitigation.

CI command: `uv sync --frozen`

---

### pip

```ini
# pip.conf  (~/.config/pip/pip.conf or $PIP_CONFIG_FILE)
[global]
require-hashes = true
only-binary = :all:
index-url = https://pypi.org/simple/
```

pip has no native quarantine setting. Use a private proxy (Artifactory, Nexus) that enforces release-age policy server-side.

---

### Go

Go has no native minimum release age setting, but it has strong integrity controls built in.

```bash
# Source this in CI or run: go env -w GOFLAGS="-mod=readonly"
export GOFLAGS="-mod=readonly"

# Use 'off' not 'direct' as the fallback.
# 'direct' falls back to VCS source if the proxy is unreachable, bypassing all proxy controls.
# 'off' fails the build instead.
export GOPROXY="https://proxy.golang.org,off"

# Checksum database: every download is verified against this transparent log.
# Never set to "off" in production.
export GOSUMDB="sum.golang.org"

# For private modules that should not go through the public proxy:
# export GOPRIVATE="github.com/myorg/*"
```

Key CI commands:
```bash
go mod verify          # verify all cached modules match go.sum
GOFLAGS=-mod=readonly go build ./...   # fail if go.sum is incomplete
govulncheck ./...      # vulnerability scan
```

> **`GOPROXY=...,direct` is a trap.** If the proxy is unavailable, `direct` silently downloads from the original VCS. That bypasses everything. Use `off` so the build fails loudly instead.

---

### Rust / Cargo

Cargo has no `ignore-scripts` equivalent. `build.rs` files run with full filesystem and network access and cannot be globally disabled. The mitigations are policy tools.

```toml
# deny.toml (cargo-deny >= 0.16 schema)
[advisories]
db-urls = ["https://github.com/rustsec/advisory-db"]
ignore = []   # document suppressions with a reason

[licenses]
# Only listed licenses are allowed. Copyleft is blocked by omission.
allow = ["MIT", "Apache-2.0", "Apache-2.0 WITH LLVM-exception",
         "BSD-2-Clause", "BSD-3-Clause", "ISC"]
confidence-threshold = 0.8

[bans]
multiple-versions = "warn"

[sources]
unknown-registry = "deny"
unknown-git = "deny"
allow-registry = ["https://github.com/rust-lang/crates.io-index"]
```

```toml
# supply-chain/config.toml (cargo-vet)
imports = [
    { name = "mozilla", url = "https://raw.githubusercontent.com/mozilla/cargo-vet/main/supply-chain/audits.toml" },
    { name = "google",  url = "https://raw.githubusercontent.com/google/cargo-vet/main/supply-chain/audits.toml" },
]
```

Key CI commands:
```bash
cargo build --locked       # fail if Cargo.lock is outdated
cargo audit                # vulnerability scan (RustSec)
cargo deny check advisories bans sources   # policy check
cargo vet                  # audit check (requires supply-chain/audits.toml)
```

> **cargo-deny schema changed in 0.16.** The old `vulnerability = "deny"`, `unlicensed = "deny"`, and `deny = [...]` fields were removed. Upgrade your deny.toml or `cargo deny check` will fail silently.

---

### Java / Maven

```xml
<!-- settings.xml mirror block -->
<mirror>
  <id>internal-mirror</id>
  <mirrorOf>*</mirrorOf>
  <url>https://nexus.internal.company.com/repository/maven-public/</url>
  <!-- Default checksumPolicy is 'warn' - tampered artifacts pass silently.
       'fail' breaks the build on any mismatch. -->
  <checksumPolicy>fail</checksumPolicy>
  <releases>
    <!-- 'never' prevents Maven from re-checking for updated release artifacts,
         closing a SNAPSHOT-style poisoning window. -->
    <updatePolicy>never</updatePolicy>
  </releases>
</mirror>
```

```xml
<!-- pom.xml - enforcer + extra-enforcer-rules -->
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-enforcer-plugin</artifactId>
  <version>3.4.1</version>
  <dependencies>
    <!-- banDuplicateClasses is not built in; requires extra-enforcer-rules -->
    <dependency>
      <groupId>org.codehaus.mojo</groupId>
      <artifactId>extra-enforcer-rules</artifactId>
      <version>1.8.0</version>
    </dependency>
  </dependencies>
  <executions>
    <execution>
      <goals><goal>enforce</goal></goals>
      <configuration>
        <rules>
          <banDuplicateClasses><findAllDuplicates>true</findAllDuplicates></banDuplicateClasses>
          <requireMavenVersion><version>[3.8.0,)</version></requireMavenVersion>
        </rules>
      </configuration>
    </execution>
  </executions>
</plugin>
```

Key CI commands:
```bash
mvn validate                    # runs enforcer
mvn dependency-check:check      # OWASP vulnerability scan
```

> **`checksumPolicy` defaults to `warn`.** Most Maven setups never set this explicitly. A tampered artifact produces a warning in the build log and then installs. Set it to `fail`.

> **Plugins are not the same threat as npm postinstall.** Maven plugins run during `mvn install`, but only those you explicitly declare in `pom.xml`. A transitive dependency cannot silently inject a plugin into your build — unlike npm's `postinstall`, which can be added by any package in your dependency tree without your knowledge.

---

### Java / Gradle

```kotlin
// build.gradle.kts
dependencyLocking {
    lockAllConfigurations()
    lockMode.set(LockMode.STRICT)   // fail if lock file is missing or outdated
}
```

```properties
# gradle.properties
# Verifies actual JAR content hashes, not just version pins.
# Generate the metadata file first: ./gradlew --write-verification-metadata sha256 dependencies
# Then commit gradle/verification-metadata.xml
org.gradle.dependency.verification=strict
```

Key CI commands:
```bash
./gradlew dependencies --write-locks          # generate lock files
./gradlew build --dependency-verification=strict
./gradlew dependencyCheckAnalyze              # OWASP scan
```

> **Dependency locking and dependency verification are different things.** Locking pins versions. Verification checks that the downloaded JAR matches a known SHA256. Both are needed. Verification requires `gradle/verification-metadata.xml` to be committed.

---

### .NET / NuGet

```xml
<!-- SupplyChainTest.csproj -->
<PropertyGroup>
  <RestoreLockedMode>true</RestoreLockedMode>
  <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
  <NuGetAudit>true</NuGetAudit>
  <NuGetAuditMode>all</NuGetAuditMode>
  <NuGetAuditLevel>low</NuGetAuditLevel>
</PropertyGroup>
```

```xml
<!-- Directory.Packages.props - Central Package Management -->
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
    <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
  </PropertyGroup>
  <ItemGroup>
    <!-- Declare all versions here once. csproj files use PackageReference with no Version. -->
    <!-- <PackageVersion Include="Newtonsoft.Json" Version="13.0.3" /> -->
  </ItemGroup>
</Project>
```

Key CI commands:
```bash
dotnet restore /p:RestoreLockedMode=true    # fail if packages.lock.json is stale
dotnet list package --vulnerable --include-transitive
```

> **Central Package Management prevents version drift.** Without it, individual csproj files can use version ranges like `>= 1.0`, which can silently upgrade to a malicious version. With CPM, all versions are declared once and enforced repo-wide.

---

### PHP / Composer

```json
// composer.json
{
  "config": {
    "preferred-install": "dist",
    "allow-plugins": {}
  }
}
```

`allow-plugins: {}` (empty map) prevents all Composer plugins from activating — this is a separate code-execution vector from scripts.

`preferred-install: dist` downloads release archives instead of VCS clones, avoiding `.git` hook exposure.

Always run with `--no-scripts` in CI:
```bash
composer install --no-scripts --prefer-dist --no-interaction
```

`--no-scripts` prevents all scripts in the `scripts` block of any package's `composer.json` from running, including `post-install-cmd`, `pre-install-cmd`, and `post-update-cmd`. Re-enable per-invocation only when you have reviewed the scripts involved.

To point Composer at a private mirror (Satis or Nexus):
```json
{
  "repositories": [
    {"type": "composer", "url": "https://packagist.internal.company.com"},
    {"packagist.org": false}
  ]
}
```

`{"packagist.org": false}` disables the public Packagist fallback, preventing packages not in your mirror from being installed — the Composer equivalent of `GOPROXY=...,off`.

> **No native age gate.** Composer has no minimum release age setting. A private mirror is the only way to enforce a quarantine window.

CI command: `composer install --no-scripts --prefer-dist --no-interaction`

---

## Lightweight Proxies (Alternative to Nexus)

If RAM is constrained or you prefer purpose-built tooling, five specialized proxies cover the same ground as Nexus at a fraction of the cost: ~150 MB combined vs ~1.5 GB for Nexus.

Each proxy is a drop-in registry replacement for one ecosystem. Verdaccio is the only option in this stack with server-side release-age enforcement.

| Proxy | Ecosystem | Port | Age enforcement |
|-------|-----------|------|-----------------|
| [escrow](https://github.com/jverhoeks/escrow) | npm / PyPI / Go modules | 8888 | **Server-side** (`min_days: 7`) |
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

### escrow — npm, PyPI, and Go in a single binary

[escrow](https://github.com/jverhoeks/escrow) is a purpose-built supply-chain proxy that enforces age gates, OSV vulnerability checks, and publisher-account-age policy server-side — blocking packages before they reach the package manager. It replaces three separate proxies (Verdaccio, devpi, Athens) with one binary and adds server-side age enforcement to PyPI and Go, which have no equivalent in the single-proxy stack.

```bash
# Docker
docker run -p 8888:8888 ghcr.io/jverhoeks/escrow:latest

# Build from source
cd /path/to/escrow && go build -o escrow ./cmd/escrow && ./escrow
```

Policy in `sentinel.toml`:
```toml
[policy.age]
  min_days = 7     # block packages published fewer than 7 days ago
  action   = "block"
```

Point each tool at escrow (default port 8888):

**npm / pnpm / bun** — `.npmrc`:
```ini
registry=http://localhost:8888/
```

**uv / pip** — `uv.toml`:
```toml
[pip]
index-url = "http://localhost:8888/pypi/simple/"
```

**Go**:
```bash
export GOPROXY="http://localhost:8888/go,off"
```

Test results (2026-05-16, block-all and allow-all modes, 7/7 passed):
```
npm  block-all:  lodash manifest versions blocked           PASS
npm  block-all:  npm install blocked                        PASS
PyPI block-all:  requests releases filtered (163 → 3)       PASS
Go   block-all:  module blocked (403)                       PASS
npm  allow-all:  once installed via escrow                  PASS
PyPI allow-all:  163 releases proxied through               PASS
Go   allow-all:  module proxied successfully                PASS
```

```bash
bash tests/test-escrow.sh
# Auto-discovers ../2026-05-16-escrow or set ESCROW_DIR=/path/to/escrow
```

### Testing proxy isolation

The test spins up a local Verdaccio instance with no upstream (air-gapped), points the package manager at it, and tries to install a well-known public package (`lodash`). The install must fail, proving the package manager has no public internet fallback. A second assertion publishes an approved package to the proxy and confirms it installs successfully.

```bash
bash tests/test-private-proxy.sh
# Requires: npx (for verdaccio)
```

---

## Testing That Your Config Actually Works

Config typos are silent. Run these tests to verify the settings actually do what they claim.

### Test 1: install script blocking

Creates a package with a `postinstall` that writes a sentinel file, installs it, asserts the file was not created.

```bash
bash tests/run-script-tests.sh
# Covers: npm, pnpm v10, pnpm v11, yarn, bun, uv
```

### Test 2: minimum release age (npm / pnpm / yarn / uv)

Uses a local Verdaccio registry to publish a test package timestamped right now, asserts the package manager blocks it.

```bash
bash tests/test-minimum-age.sh
# Requires: npx (for verdaccio)
```

### Test 3: private proxy isolation

Runs an air-gapped Verdaccio (no upstream), asserts that public packages cannot be fetched, then asserts that an internally approved package can.

```bash
bash tests/test-private-proxy.sh
# Requires: npx (for verdaccio)
```

### Test 4: Go controls

Asserts that `-mod=readonly` blocks silent fetches, `GOPROXY=off` blocks external downloads, and `go mod verify` passes on a clean module.

```bash
bash tests/test-go.sh
```

### Test 5: Rust controls

Asserts that `cargo deny check` passes on the reference config and that the cargo-vet supply-chain files are present.

```bash
bash tests/test-cargo.sh
# Requires: cargo-deny (cargo install cargo-deny)
```

### Test 6: Java controls

Asserts Maven Enforcer passes, `checksumPolicy=fail` is set, `updatePolicy=never` is set, and Gradle dependency verification is enabled in strict mode.

```bash
bash tests/test-java.sh
# Requires: mvn
```

### Test 7: .NET controls

Asserts `dotnet restore` works, locked mode passes, Central Package Management is configured, and NuGetAudit is enabled.

```bash
bash tests/test-dotnet.sh
# Requires: dotnet
```

### Test 8: escrow proxy integration (npm, PyPI, Go)

Builds escrow from source, starts it in block-all mode (age = 99999 days), asserts npm manifests are filtered to zero versions, PyPI releases are pruned, and Go modules return 403. Then restarts with no policy and asserts all three ecosystems proxy through successfully.

```bash
bash tests/test-escrow.sh
# Auto-discovers ../2026-05-16-escrow or set ESCROW_DIR=/path/to/escrow
```

---

## Things Most Teams Miss

**Maven and Gradle plugins are not the same threat as npm postinstall.**
A common assumption is that "Maven plugins run code, so Maven is as dangerous as npm." This is wrong in a meaningful way. npm's `postinstall` can be injected by any package in `node_modules` without explicit project consent. Maven and Gradle plugins only execute what you explicitly declare in `pom.xml` or `build.gradle` — a transitive dependency cannot silently add a plugin to your build. The threat model is: *your* build config runs code from plugins; those plugins are fetched from Maven Central. So you still need to vet the plugins you declare and use a proxy with `checksumPolicy=fail`, but the attack surface is narrower than npm.

**Composer scripts run on install exactly like npm postinstall — but fewer teams know this.**
`composer install` executes `post-install-cmd` and `pre-install-cmd` scripts from any package's `composer.json`. This is the same attack surface as npm's `postinstall` hook. Always run `composer install --no-scripts` in CI. Unlike npm, there is no persistent config key to disable scripts globally — it must be a flag on every invocation.

**`ignore-scripts=true` does not block git dependencies.**
npm calls the system `git` binary to fetch git-hosted packages, bypassing the lifecycle hook system entirely. A malicious package can include its own `.npmrc` overriding which binary npm treats as `git` — turning a git dependency install into arbitrary code execution even with `ignore-scripts=true`. The fix: add `allow-git=false` to `.npmrc` (requires npm >= 11.10). Safety flags only protect the layer they actually control. ([source](https://thinkingthroughcode.medium.com/i-thought-ignore-scripts-made-npm-installs-safe-it-doesnt-f409b852e7c5))

**pnpm v11 moved build policy to `pnpm-workspace.yaml`.**
Settings in `.npmrc` are silently ignored. Run `pnpm approve-builds` to populate the allowlist interactively. If you upgraded from v10 and kept `allowBuilds` in `.npmrc`, your build policy is doing nothing.

**npm uses days, not minutes.**
`min-release-age=7` in npm means 7 days. `minimumReleaseAge=7` in pnpm means 7 minutes. The config key and unit are both different. Always double-check.

**`GOPROXY=...,direct` is not a safe default.**
The official Go docs show `direct` as the fallback, so most teams leave it. But `direct` means Go silently downloads from the original VCS when the proxy is unreachable. Use `off` so you find out about proxy issues rather than bypassing them.

**Maven `checksumPolicy` defaults to `warn`.**
Maven validates checksums by default, but only warns on mismatch. The build continues. A tampered artifact gets installed with a warning in the log that most people never read. Set `checksumPolicy=fail`.

**Gradle dependency locking is not the same as dependency verification.**
Locking pins which version is resolved. Verification checks that the downloaded JAR matches a known SHA256. You can have locking without verification, which means you know you got version 1.2.3 but not whether the JAR for 1.2.3 has been tampered with. Both are needed.

**cargo-deny's schema changed in 0.16.**
`vulnerability = "deny"`, `unmaintained = "warn"`, `unlicensed = "deny"`, and the `deny = [...]` list in `[licenses]` were all removed. If you have an old `deny.toml`, running `cargo deny check` will fail with deprecation errors. The new schema uses `allow = [...]` in licenses (anything not listed is rejected) and a plain `ignore = []` in advisories.

**`--extra-index-url` in pip is a dependency confusion vector.**
pip checks all indexes and picks the highest version across all of them. Attackers register public packages with higher versions than your internal ones. Use `--index-url` (replace, not add) or route everything through a single internal proxy.

**NuGet `RestoreLockedMode` has no effect without `packages.lock.json`.**
The setting is present but harmless until you run `dotnet restore` once to generate the lock file and commit it. Without the committed lock file, locked mode always succeeds because there is nothing to check against.

**Cargo `build.rs` has no global off switch.**
Rust build scripts run with full filesystem and network access during compilation. `cargo vet` and `cargo deny` are the only mitigations short of sandboxed builds. Both should be in CI.

**Nexus CE 3.70+ requires EULA acceptance before proxying works.**
If your Go or Maven fetches return 403 immediately after spinning up Nexus, the EULA has not been accepted. Run `setup.sh` — it handles this automatically. Doing it manually: `POST /service/rest/v1/system/eula` with `{"accepted":true}`.

**A proxy does not replace client-side script blocking.**
Nexus, Verdaccio, and every other proxy cache and air-gap packages. None of them strip `postinstall` hooks or enforce `only-binary` before handing a tarball to your package manager. The `ignore-scripts`, `allowBuilds`, and `only-binary` settings must still be in every project's config even when a proxy is in the path.

---

## What This Does Not Cover

- **Dependency confusion attacks**: An attacker registers a public package with the same name as your internal package at a higher version. The package manager silently installs the public one. Mitigation: scoped packages (`@myorg/`), single index only (never `--extra-index-url`), and a private proxy as the sole source. See the "Do not add a second index as a fallback" note in the proxy section.
- **Typosquatting**: Attackers register `lodash` → `1odash` (one, not L). The quarantine window reduces the risk window but does not eliminate it. Lockfiles are the main mitigation — pin exact versions and commit the lockfile.
- **SBOM generation**: `mvn cyclonedx:makeAggregateBom`, `./gradlew cyclonedxBom`, `cargo cyclonedx`, `dotnet sbom-tool`. Generates a software bill of materials for auditing and compliance.
- **Lockfile integrity in CI**: Use `npm ci`, `pnpm install --frozen-lockfile`, `uv sync --frozen`, `cargo build --locked`, `dotnet restore /p:RestoreLockedMode=true`. Never use the plain install command in a pipeline.
- **Vulnerability scanning**: `npm audit`, `pip-audit`, `cargo audit`, `govulncheck`, `mvn dependency-check:check`.
- **SLSA and Sigstore**: Provenance attestation for verifying that a package was built from the claimed source. See `cross-ecosystem/slsa-sigstore.md`.

---

## References

- [I thought ignore-scripts made npm installs safe. It doesn't.](https://thinkingthroughcode.medium.com/i-thought-ignore-scripts-made-npm-installs-safe-it-doesnt-f409b852e7c5) — The `allow-git=false` bypass and why safety flags only protect the layer they actually control.

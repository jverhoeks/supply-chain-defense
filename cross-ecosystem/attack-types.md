# Supply Chain Attack Taxonomy (2024-2026)

## 1. Typosquatting
Attacker registers a package with a name similar to a popular one.
- `requests` → `reqests`, `request`, `requets`
- `express` → `expresss`, `expres`

**Mitigations:**
- `minimumReleaseAge` (npm/pnpm/yarn) — blocks brand-new packages
- Socket.dev behavioral scanning
- npm/PyPI anti-typosquatting heuristics (built-in)
- Allowlist approach: only install packages you've explicitly reviewed

## 2. Dependency Confusion
Attacker publishes a public package with the same name as your private internal package.
npm/pip/cargo will prefer the higher version number → downloads malicious public package.

**Real incidents:** Apple, Microsoft, Tesla, Uber (2021 — Alex Birsan research)

**Mitigations:**
- Scoped packages: `@myorg/internal-lib` (npm) — cannot be confused with public packages
- Python: use private-first index configuration (not `--extra-index-url`)
- Pin exact versions with hashes
- pnpm v11: `blockExoticSubdeps=true`

## 3. Account Takeover / Maintainer Hijack
Attacker gains access to a legitimate maintainer's account and publishes malicious version.
- Weak/reused passwords
- Phishing
- Social engineering ("I'm taking over this abandoned package")

**Real incidents:** ua-parser-js (2021), event-source-polyfill (2022)

**Mitigations:**
- `minimumReleaseAge` — gives time to detect before wide adoption
- npm: require 2FA for popular packages (enforced for top-500 npm packages since 2022)
- Monitor dependencies for unexpected version bumps (Dependabot alerts)
- Socket.dev detects behavioral changes between versions

## 4. Abandoned Package Takeover
Maintainer abandons a package, attacker claims it via registry support.

**Mitigations:**
- Monitor for abandoned/unmaintained packages: `cargo deny` (unmaintained = "warn"), `bundler-audit`
- Vendor critical abandoned dependencies
- Periodically review direct dependencies for maintenance activity

## 5. Install Script Attacks (npm/pip/composer)
Malicious code runs `postinstall` / `setup.py` / `post-install-cmd` during package installation.
Provides immediate RCE on the developer's/CI machine.

**Real incidents:** LiteLLM PyPI attack (2026), dozens of npm postinstall attacks

**Mitigations (per ecosystem):**

| Ecosystem | Mitigation |
|-----------|-----------|
| npm | `ignore-scripts=true` in `.npmrc` |
| pnpm v11 | `allowBuilds={}` (empty = all blocked, explicit whitelist) |
| yarn berry | `enableScripts: false` in `.yarnrc.yml` |
| pip | `--only-binary :all:` (blocks `setup.py` execution) |
| composer | `composer install --no-scripts` |
| cargo | No global disable; use `cargo deny` to ban crates with known-bad build.rs |
| go | No install scripts by design |
| maven | No install scripts by design (Maven plugins run at build-time, not install-time) |
| nuget | No install scripts; but IL weaving attacks inject code into compiled binaries |
| bundler | Ruby gems cannot execute postinstall scripts by design |

## 6. Slopsquatting (2025+)
AI coding assistants hallucinate package names. Attackers register those hallucinated names
and wait for AI-assisted developers to install them.

**Mitigations:**
- Verify all AI-suggested package names exist before installing
- Check download counts and publication date before adding new deps
- Socket.dev flags new packages with 0 downloads

## 7. Build Tool Compromise (XZ-style)
Long-term attacker becomes legitimate maintainer, introduces backdoor over time.
XZ Utils (2024): 2-year infiltration, SSH daemon backdoor.

**Mitigations:**
- `cargo vet` / supply chain auditing tools
- Review diffs on all dependency version bumps (not just CVEs)
- Use multiple maintainer trust signals before adopting dependencies
- Vendor critical dependencies to freeze the code

## 8. Registry/Proxy Cache Poisoning
Attacker publishes malicious version to a public registry.
Even after deletion, proxy caches (proxy.golang.org, npm CDN) may serve stale content.

**Real incident:** Go module proxy caching attack (2026 — socket.dev research)

**Mitigations:**
- Private proxy with filtering and audit logging
- Go: `go mod verify` detects cached module tampering
- Use sum databases (`GOSUMDB`) which are append-only transparency logs

## 9. IL Weaving / JIT Hooking (.NET specific)
Malicious NuGet packages inject code into .NET IL during build, or hook JIT at runtime.
2024-2025 incidents targeted ASP.NET Identity and industrial control systems.

**Mitigations:**
- `NuGetAudit=true` + private proxy
- SBOM analysis + static analysis for obfuscated code
- Monitor for unexpected dependency additions to `.csproj` files

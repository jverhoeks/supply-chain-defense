# Composer Supply Chain Protection

## Key Controls

### 1. Exact version pinning
In `composer.json`, use exact versions instead of ranges:
```json
"symfony/http-foundation": "7.0.6"   ✓
"symfony/http-foundation": "^7.0"    ✗ (resolves to latest compatible)
```

### 2. Lockfile — always commit `composer.lock`
- Contains exact versions + SHA checksums for all packages.
- CI: `composer install --no-update` (never `composer update` in CI).

### 3. Block install scripts (untrusted environments)
```bash
composer install --no-scripts
```
Disables `post-install-cmd`, `post-update-cmd`, `pre-install-cmd` hooks.
Use in CI after reviewing which scripts are actually needed.

### 4. Vulnerability scanning (Composer 2.4+)
```bash
composer audit                    # Scan against PHP Security Advisories DB
composer audit --format=json      # Machine-readable output for CI
```
`composer audit` is also called automatically on `composer require` and `composer update`.

### 5. `preferred-install: dist`
In `composer.json` config: `"preferred-install": "dist"`
Downloads prebuilt `.zip` archives from Packagist instead of cloning git repos.
Faster and slightly safer (no git history or extra files).

### 6. Private Packagist / Satis
For corporate environments, proxy through:
- **Private Packagist** (packagist.com) — hosted private registry with vulnerability scanning.
- **Satis** (open source) — self-hosted static Packagist mirror.
- **JFrog Artifactory** — enterprise repository manager.

Add private repository to `composer.json`:
```json
"repositories": [
    { "type": "composer", "url": "https://packages.internal.company.com" },
    { "packagist.org": false }  ← block public Packagist entirely
]
```

### 7. Known attack vectors
- **CVE-2021-29472**: Composer ≤ 1.10.22 / 2.0.13 — shell injection via malicious repository URLs.
- **Abandoned package takeover**: Monitor packages.seld.be/packages/abandoned for abandoned packages.
- **GitHub repository compromise**: Direct `git` type repositories bypass Packagist validation.

### 8. CI pipeline integration
```yaml
# GitHub Actions example
- name: Install dependencies (frozen)
  run: composer install --no-update --no-scripts --prefer-dist
- name: Security audit
  run: composer audit
```

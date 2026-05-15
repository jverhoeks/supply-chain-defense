# Nexus Proxy + Blog Redesign

**Date:** 2026-05-15  
**Status:** Approved

---

## Goal

Add Nexus Repository OSS as the recommended "one proxy for everything" option alongside the existing five specialized proxies. Restructure the blog post to lead with Nexus, add a protection matrix, and clarify per-ecosystem coverage gaps.

---

## Infrastructure

### Nexus service

Add a sixth service to `proxies/docker-compose.yml`:

- Image: `sonatype/nexus3:latest`
- Port: `8081:8081`
- Volume: `nexus-data:/nexus-data`
- No special environment variables needed at startup

### `proxies/nexus/setup.sh`

Runs once after `docker compose up -d` to configure Nexus via REST API. Steps:

1. Poll `GET /service/rest/v1/status/writable` until 200 (Nexus can take 1–2 min to start)
2. Read auto-generated password from `/nexus-data/admin.password` via `docker exec`
3. Change admin password to `admin123` via `PUT /service/rest/v1/security/users/admin/change-password`
4. Enable anonymous read via `PUT /service/rest/v1/security/anonymous`
5. Create five proxy repositories (idempotent — skip if already exists):
   - `npm-proxy` → `https://registry.npmjs.org`
   - `pypi-proxy` → `https://pypi.org` (format: `pypi`)
   - `go-proxy` → `https://proxy.golang.org` (format: `go`)
   - `maven-central` → `https://repo1.maven.org/maven2/` (format: `maven2`)
   - `nuget-proxy` → `https://api.nuget.org/v3/index.json` (format: `nuget`)

Setup is idempotent. Re-running after repos exist is safe (409 Conflict is ignored).

---

## Tests

### `proxies/tests/test-nexus.sh`

Suite structure:

**Setup check**
- Nexus is reachable at `http://localhost:8081`
- All five proxy repos exist (checked via `GET /service/rest/v1/repositories`)

**Caching tests** — one per ecosystem, verifies the proxy actually serves packages:
- npm → `npm install lodash@4.17.21 --registry http://localhost:8081/repository/npm-proxy/`
- PyPI → `uv pip install --dry-run requests` with `index-url = http://localhost:8081/repository/pypi-proxy/simple/`
- Go → `GOPROXY=http://localhost:8081/repository/go-proxy,off go list -m golang.org/x/text@latest`
- Maven → fetch `commons-lang3-3.14.0.pom` from `http://localhost:8081/repository/maven-central/`
- NuGet → `dotnet restore` with `allowInsecureConnections="true"` pointing at `http://localhost:8081/repository/nuget-proxy/`

**Age gate test (npm client-side through Nexus)**
- Point npm at Nexus npm-proxy with `min-release-age=1` (1 day)
- Attempt to install a package published within the last 24h
- Assert the install is blocked — proves client-side age gate survives a proxy in the path
- Note in output: age gate is client-side; Nexus does not enforce it server-side

**`proxies/tests/run-all.sh`** — add `test-nexus.sh` as a sixth suite with the same skip-if-not-up pattern.

---

## Blog Restructure

### New section order

1. **Intro** — unchanged (axios attack, two controls)
2. **Quick Reference table** — unchanged
3. **Protection Matrix** — NEW, immediately after quick reference
4. **One Proxy for Everything: Nexus** — NEW, recommended for teams
5. **Per-Ecosystem Config** — existing content, reframed
6. **Lightweight Proxies (Alternative)** — existing five-proxy section, now clearly the alternative
7. **Testing / Things Most Teams Miss / What This Doesn't Cover** — unchanged

### Protection Matrix (section 3)

Table showing ecosystem × control coverage:

| Ecosystem | Release-age gate | Script blocking | Proxy available | Integrity |
|-----------|:---:|:---:|:---:|:---:|
| npm / pnpm / yarn / bun | ✓ client + **✓ server (Verdaccio only)** | ✓ | ✓ | ✓ |
| Python (pip / uv) | ✓ uv only, client-side | ✓ (only-binary) | ✓ | ✓ |
| Go | ✗ | n/a | ✓ | ✓ (GOSUMDB) |
| Maven / Gradle | ✗ | n/a | ✓ | ✓ |
| NuGet | ✗ | n/a | ✓ | ✓ |
| Rust / Cargo | ✗ | ✗ (build.rs) | ✗ (no OSS proxy) | ✓ (cargo-deny/vet) |

Footnotes:
- Rust is the weakest ecosystem: no proxy, no script blocking, no age gate — policy tools only
- Nexus OSS does not support Cargo (Nexus Pro only)
- pip has no native age gate; use uv or a proxy with server-side enforcement
- Verdaccio is the only open-source proxy with server-side age enforcement

### Nexus section (section 4)

Content:
- What Nexus gives you: one URL per ecosystem, org-wide enforcement, no per-project config
- `docker compose up -d && bash nexus/setup.sh`
- Table of Nexus repo URLs for each tool (npm, pnpm, uv, pip, Go, Maven, NuGet)
- Age gate note: *"Nexus caches and air-gaps every ecosystem. The release-age gate stays client-side for all ecosystems — the per-ecosystem configs below apply unchanged. Exception: for server-side npm age enforcement, run Verdaccio in front of Nexus's npm proxy (point Verdaccio's upstream at `http://nexus:8081/repository/npm-proxy/`)."*
- RAM note: ~1.5 GB at rest; use the lightweight proxies below if RAM is constrained

### Per-ecosystem section (section 5)

Add short header:
*"If you're running Nexus, combine these age-gate and script-blocking configs with the Nexus URLs above. If you're running without a central proxy, these configs work against the public registries directly."*

Content otherwise unchanged.

### Lightweight proxies section (section 6)

Retitle from "Private Proxy / Internal Mirror" to "Lightweight Proxies (Alternative to Nexus)".

Add intro:
*"Each proxy is purpose-built for one ecosystem, uses 20–30 MB RAM, and has no JVM startup time. Combined stack: ~150 MB vs Nexus's ~1.5 GB. Verdaccio is the only option here with server-side release-age enforcement."*

---

## What is NOT changing

- All existing per-ecosystem configs (`.npmrc`, `uv.toml`, `deny.toml`, etc.)
- All existing test scripts (run-script-tests, test-minimum-age, test-private-proxy, etc.)
- Five-proxy docker-compose setup — it stays, now labelled as the alternative
- "Things Most Teams Miss" and "What This Doesn't Cover" sections

---

## Open questions resolved

- Rust/Cargo: acknowledge the gap explicitly in the matrix; no proxy added (none available in OSS)
- Age gate through Nexus: verified client-side config still works (test-nexus.sh age gate test)
- Nexus Cargo support: explicitly noted as Nexus Pro only

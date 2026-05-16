# Sentinel: Multi-Ecosystem Package Proxy with Age Gate & Trust Scoring

**Date:** 2026-05-16  
**Status:** Approved for implementation

---

## Goal

A single Go binary (`sentinel`) that proxies npm and PyPI package registries, enforces a minimum release age, scans for known vulnerabilities, and scores packages against trust signals — blocking or warning based on operator-configured policy. No existing open-source tool does all of this across multiple ecosystems.

## Problem Statement

Every open-source proxy today is ecosystem-specific and lacks server-side age enforcement (except Verdaccio for npm only). Nexus Repository OSS covers multiple ecosystems but has no age gate and uses ~1.5 GB RAM. Teams wanting a lightweight, multi-ecosystem proxy with quarantine window enforcement have to run 5+ specialized proxies and accept client-side-only enforcement for most ecosystems.

---

## Architecture

Six components with clear boundaries:

```
Client (npm/pip/uv)
       │
       ▼
┌─────────────────────────────────────────┐
│   HTTP Server (chi router)              │
│   Routes by URL pattern to handler      │
└──────────────┬──────────────────────────┘
               │
       ┌───────┴───────┐
       │               │
┌──────▼──────┐ ┌──────▼──────┐
│  npm Handler│ │ PyPI Handler│   Protocol layer: speaks native registry API
│             │ │             │   npm: registry.npmjs.org protocol
│             │ │             │   PyPI: simple index + JSON API
└──────┬──────┘ └──────┬──────┘
       └───────┬───────┘
               │
┌──────────────▼──────────────────────────┐
│           Trust Engine                  │
│  ┌─────────┐ ┌─────────┐               │
│  │   Age   │ │   OSV   │               │
│  │ Checker │ │ Scanner │               │
│  └─────────┘ └─────────┘               │
│  ┌───────────┐ ┌────────────────────┐  │
│  │ Publisher │ │ Popularity Checker │  │
│  │ Checker   │ │ (where available)  │  │
│  └───────────┘ └────────────────────┘  │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│           Policy Engine                 │
│  Maps signal results → block|warn|allow │
│  Per-signal configurable action         │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│           Cache Layer                   │
│  Backends: disk (default) | s3 | memory │
│  metadata/: JSON, short TTL             │
│  blobs/: tarballs/wheels, permanent     │
└─────────────────────────────────────────┘
```

---

## Components

### HTTP Server

- Go standard library `net/http` with `chi` router
- Routes npm requests by matching `/:package`, `/:scope/:package`, `/:package/-/:tarball` patterns
- Routes PyPI requests by matching `/pypi/simple/`, `/pypi/packages/`, `/pypi/<pkg>/json`
- All unmatched routes: 404

### Protocol Handlers

**npm handler:**
- `GET /:package` → fetch and filter manifest (run trust engine per version; strip blocked versions)
- `GET /:scope/:package` → scoped package manifest
- `GET /:package/-/:tarball` → proxy tarball (trust engine runs; cache on pass)
- Preserves npm `dist-tags` — if `latest` points to a blocked version, reassign to newest passing version or omit

**PyPI handler:**
- `GET /simple/<package>/` → simple index HTML (filter out files for blocked versions)
- `GET /pypi/<package>/json` → full JSON metadata (filter blocked versions)
- `GET /packages/<path>` → proxy wheel/sdist tarball (trust engine runs; cache on pass)
- `only-binary` enforcement: configurable option to reject sdist files (`.tar.gz`, `.zip`) regardless of trust score — eliminates `setup.py` execution risk entirely

### Trust Engine

Runs four independent signals against a `(ecosystem, package, version, metadata)` tuple. Each signal returns `(result: SignalResult, reason: string)`.

#### Age Checker
- Source: publish timestamp from upstream registry metadata
  - npm: `time[version]` field in package manifest
  - PyPI: `releases[version][0].upload_time` field in JSON API
- Computes: `age_days = (now - publish_time).Days()`
- Returns: `FAIL` if `age_days < policy.age.min_days`, else `PASS`

#### OSV Scanner
- Queries `https://api.osv.dev/v1/query` with `{version, package: {name, ecosystem}}`
- Ecosystem strings: `"npm"` for npm, `"PyPI"` for PyPI
- Filters response by severity threshold (`CVSS >= threshold` or `severity in [LOW, MEDIUM, HIGH, CRITICAL]`)
- Cache: 24h TTL per (package, version) tuple
- Returns: `FAIL` with CVE list if any vulnerability ≥ configured severity, else `PASS`

#### Publisher Checker
- npm: `GET https://registry.npmjs.org/-/user/org.couchdb.user/<maintainer>` — extracts `created` field. Also checks if this is the first package published by this account.
- PyPI: `GET https://pypi.org/pypi/<package>/json` — checks if `info.version` is the only key in `releases` (first-ever release), and inspects release history depth.
- Returns: `WARN` if account age < `policy.publisher.max_account_age_days` OR if this is the account's first-ever published package

#### Popularity Checker
- npm: `GET https://api.npmjs.org/downloads/point/last-week/<package>` — compare against stored baseline (previous week's count, cached on disk/s3/memory)
- PyPI: `GET https://pypistats.org/api/packages/<package>/recent` — same baseline comparison
- Spike detection: if `(current_week / baseline_week) > policy.popularity.spike_factor` AND baseline was near-zero (< 100 downloads/week), flag as suspicious
- Returns: `WARN` if spike detected; `SKIP` if insufficient history (< 2 weeks of data)

### Policy Engine

Maps signal results to actions. Configuration is explicit — no config means no enforcement.

**Config (`sentinel.toml`):**
```toml
[policy]
  [policy.age]
    min_days = 7
    action   = "block"   # block | warn | allow

  [policy.osv]
    min_severity = "MEDIUM"   # LOW | MEDIUM | HIGH | CRITICAL
    action       = "block"

  [policy.publisher]
    max_account_age_days = 30
    action               = "warn"

  [policy.popularity]
    spike_factor = 10.0
    action       = "warn"
```

**Startup behaviour:**
- No `[policy]` block present → print `WARN: no policy configured — sentinel is proxying without age gate, OSV scanning, or trust checks` and start
- `[storage] backend = "memory"` → print `WARN: storage backend is 'memory' — no packages will be cached between restarts`
- No `sentinel.toml` → same warning as no policy block

**Response on block:**
- HTTP 403 with JSON body: `{"blocked": true, "signal": "age", "reason": "package published 2 days ago (min: 7)", "package": "lodash", "version": "4.17.22"}`
- npm and pip both surface this message in their error output

### Cache Layer

**Layout (disk and S3):**
```
cache/
  meta/
    npm/<package>/<version>.json        # manifest fragment
    pypi/<package>/<version>.json       # PyPI metadata
    osv/<ecosystem>/<package>/<version>.json   # OSV response, 24h TTL
    pub/<ecosystem>/<account>.json      # publisher info, 1h TTL
    pop/<ecosystem>/<package>/baseline.json    # download baseline, 7d TTL
  blobs/
    npm/<package>/-/<tarball>           # .tgz files
    pypi/<package>/<filename>           # .whl, .tar.gz files
```

**Backends:**
- `disk` (default): files on local filesystem at configured `path`
- `s3`: same layout, same paths as S3 object keys; AWS SDK v2; endpoint configurable for MinIO
- `memory`: in-process LRU map for metadata + OS temp dir for blobs, cleaned on shutdown

**TTLs:**
- Registry metadata: 10 minutes
- OSV results: 24 hours
- Publisher info: 1 hour
- Popularity baseline: 7 days (rolling)
- Blobs: permanent (disk/s3); process-lifetime (memory)

---

## Configuration

Full `sentinel.toml` reference:
```toml
[server]
  host = "0.0.0.0"
  port = 8888
  log_level = "info"   # debug | info | warn | error

[ecosystems]
  npm  = true
  pypi = true

[storage]
  backend = "disk"   # disk | s3 | memory

  [storage.disk]
    path = "./sentinel-cache"

  [storage.s3]
    bucket   = ""
    region   = "eu-west-1"
    endpoint = ""   # blank = AWS; set for MinIO

[policy]
  [policy.age]
    min_days = 7
    action   = "block"

  [policy.osv]
    min_severity = "MEDIUM"
    action       = "block"

  [policy.publisher]
    max_account_age_days = 30
    action               = "warn"

  [policy.popularity]
    spike_factor = 10.0
    action       = "warn"

  [policy.pypi]
    block_sdist = false   # true = reject source distributions entirely

[alerts]
  webhook_url = ""   # POST JSON on block; blank = disabled
```

---

## Observability

**Structured JSON logs** (zerolog): every request emits a log entry with fields:
`ecosystem`, `package`, `version`, `cache_hit`, `signals`, `action`, `upstream_ms`, `error`

**`GET /healthz`**: JSON with uptime, cache backend, cache size, upstream reachability per ecosystem

**`GET /metrics`**: Prometheus exposition format with counters:
- `sentinel_requests_total{ecosystem, action}` — requests by ecosystem and outcome
- `sentinel_blocks_total{ecosystem, signal}` — blocks by signal type
- `sentinel_cache_hits_total{ecosystem, type}` — metadata vs blob cache hits
- `sentinel_osv_query_duration_seconds` — OSV API latency histogram

**Webhook** (optional): `POST webhook_url` with JSON body on any block action. Payload includes package, version, signal, reason, timestamp.

---

## File Layout (new repo: `sentinel`)

```
sentinel/
  cmd/sentinel/main.go          # binary entry point, config loading, server start
  internal/
    server/server.go            # HTTP server, router setup
    handler/
      npm/handler.go            # npm protocol handler
      pypi/handler.go           # PyPI protocol handler
    trust/
      engine.go                 # orchestrates all signals, returns TrustResult
      age.go                    # age signal
      osv.go                    # OSV signal
      publisher.go              # publisher signal
      popularity.go             # popularity signal
    policy/policy.go            # maps TrustResult → Action per config
    cache/
      cache.go                  # Cache interface
      disk.go                   # disk backend
      s3.go                     # S3 backend
      memory.go                 # in-process backend
    config/config.go            # TOML parsing, validation, startup warnings
    upstream/client.go          # shared HTTP client for upstream registries
  config.example.toml
  Dockerfile
  go.mod
  README.md
```

---

## Out of Scope for V1

- Maven, NuGet, Go modules, Composer, Cargo (V2+)
- Web UI / admin dashboard
- Package allowlist management UI (allowlist via config only)
- Multi-instance coordination (each sentinel instance is independent)
- Authentication / access control (assumes internal network deployment)

---

## Success Criteria

- `npm install` and `pip install` / `uv pip install` work transparently when pointing at sentinel
- Packages published < 7 days ago are blocked with a readable error message
- Known CVEs at MEDIUM+ severity are blocked
- New publisher accounts and popularity spikes generate warnings in logs and optionally to webhook
- Single binary, no runtime dependencies, starts in < 1 second
- `docker run ghcr.io/jverhoeks/sentinel:latest` works with zero config (with startup warning)

# Local Protective Proxies

One command starts all proxies:

```bash
cd proxies/
docker compose up -d
docker compose logs -f   # watch startup
```

## What runs where

### Nexus (single proxy, all ecosystems)

| Ecosystem | Port | Age enforcement |
|-----------|------|-----------------|
| npm / PyPI / Go / Maven / NuGet | 8081 | Client-side only (all ecosystems) |

```bash
docker compose up -d nexus
bash nexus/setup.sh  # first time only; idempotent
```

RAM: ~1.5 GB at rest.

### Lightweight proxies (specialized, lower RAM)

| Proxy | Ecosystem | Port | Age enforcement | Cache |
|-------|-----------|------|----------------|-------|
| Verdaccio | npm / pnpm / yarn / bun | 4873 | **Server-side** via `@verdaccio/package-filter` `minAgeDays: 7` | yes |
| devpi | pip / uv | 3141 | Client-side only (`exclude-newer = "P7D"` in uv.toml) | yes |
| Athens | Go modules | 3000 | Client-side only (`GOPROXY=http://localhost:3000,off`) | yes (immutable) |
| Reposilite | Maven / Gradle | 8080 | Client-side only (`checksumPolicy=fail` in settings.xml) | yes |
| BaGetter | NuGet | 5555 | Client-side only (`RestoreLockedMode` + `NuGetAudit`) | yes |

Total RAM: ~150 MB. Verdaccio is the only open source proxy with native release-age gating.

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

**npm / pnpm / bun** -- add to `.npmrc`:
```ini
registry=http://localhost:4873/
```

**yarn** -- add to `.yarnrc.yml`:
```yaml
npmRegistryServer: "http://localhost:4873"
```

**pip** -- add to `pip.conf`:
```ini
[global]
index-url = http://localhost:3141/root/pypi/+simple/
```

**uv** -- add to `uv.toml`:
```toml
[pip]
index-url = "http://localhost:3141/root/pypi/+simple/"
```

**Go** -- set env:
```bash
export GOPROXY="http://localhost:3000,off"
```

**Maven** -- add to `settings.xml`:
```xml
<mirror>
  <id>local-reposilite</id>
  <mirrorOf>*</mirrorOf>
  <url>http://localhost:8080/releases</url>
  <checksumPolicy>fail</checksumPolicy>
</mirror>
```

**NuGet** -- add to `nuget.config`:
```xml
<packageSources>
  <clear />
  <add key="local" value="http://localhost:5555/v3/index.json" />
</packageSources>
```

## Stop

```bash
docker compose down          # stop, keep data volumes
docker compose down -v       # stop and delete cached packages
```

// Reposilite configuration (shared configuration file)
// Docs: https://reposilite.com/guide/
//
// NOTE: In Reposilite v3, repository configuration (including proxied repos) is stored
// in the SQLite database, NOT read from this groovy file at startup. The groovy DSL
// for repositories is silently ignored. Use the REST API instead:
//
//   PUT /api/settings/domain/maven  (Basic auth: admin:admin_secret)
//
// The test script (tests/test-reposilite.sh) handles this automatically — it checks
// whether the 'central' proxied repo exists and creates it via the API if not.
//
// Reposilite does NOT have native server-side release-age enforcement.
// Maven/Gradle have no client-side age setting either — use a private proxy
// with manual review or Nexus staging for policy enforcement.
//
// Reposilite provides:
//   - Lightweight Maven/Gradle proxy: ~20MB RAM (vs Nexus 1GB+)
//   - Proxied repositories: cache from Maven Central
//   - checksumPolicy=fail is enforced at the Maven client (settings.xml)
//   - Access control per repository

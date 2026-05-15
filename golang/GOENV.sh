#!/usr/bin/env bash
# Go environment variables for supply chain protection
# Source this file or add to CI environment.
# Can also be set via: go env -w GOFLAGS="-mod=readonly"
# Persistent env file: $(go env GOENV)  — typically ~/.config/go/env

# Prevent go commands from automatically modifying go.mod/go.sum.
# Fails loudly if a module would be added/upgraded instead of silently updating.
# Use in CI to enforce that go.sum is committed and up-to-date.
export GOFLAGS="-mod=readonly"

# Go module proxy (default: proxy.golang.org).
# All module downloads are routed through the proxy.
# The proxy caches modules permanently — even if the source repo is deleted.
# For corporate environments: use a private proxy (Athens, JFrog, Nexus)
# that scans/filters modules before serving them.
# Use 'off' not 'direct': 'direct' falls back to VCS source if the proxy is
# unreachable, bypassing all proxy controls. 'off' fails the build instead.
export GOPROXY="https://proxy.golang.org,off"

# Checksum database (default: sum.golang.org).
# Every module download is verified against this transparent log.
# NEVER set to "off" in production — this disables tamper detection.
export GOSUMDB="sum.golang.org"

# Private module patterns to skip the proxy and checksum DB.
# Use for internal modules that should not be proxied externally.
# Comma-separated glob patterns.
# export GOPRIVATE="github.com/myorg/*,*.internal.company.com"

# Bypass checksum DB for specific patterns (but still require go.sum match).
# Use for internal modules where you maintain your own checksums.
# export GONOSUMDB="github.com/myorg/private-*"

# Disable cgo to prevent C supply chain issues (optional, application-dependent).
# export CGO_ENABLED=0

# For air-gapped builds: pre-fetch with GOFLAGS="-mod=vendor"
# and commit the vendor directory.
# export GOFLAGS="-mod=vendor"

.PHONY: verify audit tidy vendor check

# Verify that all cached modules match go.sum (detects tampering)
verify:
	go mod verify

# Run Go vulnerability scanner
# Install: go install golang.org/x/vuln/cmd/govulncheck@latest
audit:
	govulncheck ./...

# Tidy go.mod/go.sum (only run locally, never in CI)
tidy:
	GOFLAGS="" go mod tidy

# Create vendor directory for air-gapped builds
vendor:
	go mod vendor

# Full CI check: verify checksums, run tests, audit vulnerabilities
check:
	go mod verify
	go build -mod=readonly ./...
	go test -mod=readonly ./...
	govulncheck ./...

# Nancy vulnerability scanner (alternative)
# Install: go install github.com/sonatype-nexus-community/nancy@latest
audit-nancy:
	go list -json -m all | nancy sleuth

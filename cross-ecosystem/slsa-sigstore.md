# SLSA & Sigstore — Provenance Attestations

## SLSA (Supply chain Levels for Software Artifacts)
Framework defining security levels for build provenance.
Spec: https://slsa.dev/spec/v1.2/

### Levels
| Level | Requirement | What it proves |
|-------|-------------|----------------|
| L1 | Provenance exists | Build produced provenance |
| L2 | Hosted build | CI system signed the provenance |
| L3 | Hardened build | Isolated build, no tampering possible |

### Achievable today (L2 on GitHub Actions)
GitHub Actions now generates SLSA L2 provenance for npm packages published via:
```yaml
- uses: actions/attest-build-provenance@v1
  with:
    subject-path: dist/
```

## Sigstore / cosign
Keyless signing using ephemeral certificates tied to OIDC identity.

### Verify an npm package's provenance
```bash
npm install -g @sigstore/cli
sigstore verify --bundle package-provenance.json package.tgz
```

### Verify a container image
```bash
cosign verify \
  --certificate-identity-regexp "https://github.com/owner/repo/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/owner/image:tag
```

### Python (PEP 740 / PyPI attestations)
PyPI now supports publishing attestations from GitHub Actions.
Packages published with `pypa/gh-action-pypi-publish@v1` get automatic attestation.

Verify:
```bash
pip install sigstore
python -m sigstore verify identity package.tar.gz \
  --bundle package.tar.gz.sigstore \
  --cert-identity "https://github.com/owner/repo/.github/workflows/publish.yml@refs/heads/main" \
  --cert-oidc-issuer "https://token.actions.githubusercontent.com"
```

## Rekor — Transparency Log
Public append-only log of all signing events.
Query: https://rekor.sigstore.dev

## Practical checklist
- [ ] Publish with provenance (`--provenance` flag in npm publish / pypa action)
- [ ] Verify provenance in CI before consuming packages (especially internal ones)
- [ ] Add SLSA verification to your security review checklist
- [ ] Track SLSA levels for your critical dependencies

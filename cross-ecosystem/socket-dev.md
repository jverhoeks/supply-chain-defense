# Socket.dev — Cross-Ecosystem Supply Chain Scanner

Socket (https://socket.dev) performs behavioral analysis on packages across ecosystems.
Unlike vulnerability databases (which only catch *known* CVEs), Socket scans actual code
for malicious signals and catches attacks before they're reported.

## Ecosystems supported
npm, PyPI, Go, Maven, Cargo, NuGet, RubyGems, Composer, Hex, Pub

## 70+ Risk Signals
- Network access from postinstall scripts
- Filesystem I/O during install
- Code obfuscation / dynamic code execution
- Typosquatting / dependency confusion detection
- Shell execution
- Environment variable exfiltration
- Protestware / sabotage code patterns

## Installation

### npm/pnpm/yarn (GitHub App)
Install Socket GitHub App → https://github.com/apps/socket-security
Scans all PRs that modify package.json / lockfiles.

### CLI (local analysis)
```bash
npm install -g @socketsecurity/cli
socket scan .
socket report create --view .
```

### pnpm integration
```bash
# Add to .npmrc
# (Socket hooks into pnpm install automatically when app is installed)
```

### Python (PyPI)
Socket scans PyPI packages. The GitHub App covers Python dependencies automatically.

## MCP Server (Claude Code)
```bash
claude mcp add socket -- npx -y @socketsecurity/mcp
```
Enables Claude to scan packages before recommending them.

## Key differentiator vs traditional scanners
Traditional scanners: known CVE databases → miss novel attacks
Socket: behavioral analysis → catches XZ-style attacks before disclosure

## Pricing
Free tier: public repos, limited scans
Pro: private repos, team features, CI/CD integration

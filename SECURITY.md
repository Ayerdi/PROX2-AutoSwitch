# Security policy

## Reporting a vulnerability

Do **not** open a public issue for an exploitable security problem or a report containing personal/private data. Use GitHub's private vulnerability reporting flow:

<https://github.com/Ayerdi/PROX2-AutoSwitch/security/advisories/new>

Include the affected release, impact, minimal reproduction and any known mitigation. Redact machine-specific audio identifiers and unrelated logs.

## Trust-sensitive components

### Logitech G HUB local WebSocket

`ws://localhost:9010` is an undocumented, reverse-engineered local interface. It is **not** an official Logitech API. Treat responses as untrusted input and keep bounded connection/request/close timeouts.

### NirSoft SoundVolumeCommandLine

The installer downloads `svcl-x64.zip` from NirSoft and verifies its pinned SHA-256 before extracting/running it. If NirSoft publishes a new build and the hash changes, installation must fail safely until the value is independently verified from the official hashes page.

**Never disable the checksum check to make installation succeed.**

## Local configuration

`config.json` stores machine-local Windows audio Item IDs because they are required to target endpoints. They are identifiers rather than credentials, but they should not be copied between machines and public issue reports should redact unnecessary identifiers.

The volatile G HUB `deviceId` is intentionally rediscovered rather than persisted.

## Release safety

Release ZIPs are built deterministically, hashed and rebuilt before publication. CI validates PowerShell syntax, PSScriptAnalyzer, Pester and scans Git history for secrets.

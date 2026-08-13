# Security policy

## Reporting a vulnerability

Do **not** open a public issue for an exploitable security problem or a report containing personal/private data. Use GitHub's private vulnerability reporting flow:

<https://github.com/Ayerdi/PROX2-AutoSwitch/security/advisories/new>

Include the affected release, impact, minimal reproduction and any known mitigation. Redact machine-specific audio identifiers and unrelated logs.

## Trust-sensitive components

### Logitech G HUB local WebSocket

`ws://localhost:9010` is an undocumented, reverse-engineered local interface. It is **not** an official Logitech API. Treat responses as untrusted input and keep bounded connection/request/close timeouts.

### Windows audio COM boundary

Endpoint enumeration and state reads use documented Windows Core Audio interfaces in-process. Changing the system default endpoint uses the undocumented `IPolicyConfig` COM interface, isolated inside the embedded C# bridge. Treat HRESULT failures as unknown state, verify every role after a switch, and never guess a target device.

## Local configuration

`config.json` stores machine-local Windows audio Item IDs because they are required to target endpoints. They are identifiers rather than credentials, but they should not be copied between machines and public issue reports should redact unnecessary identifiers.

The volatile G HUB `deviceId` is intentionally rediscovered rather than persisted.

## Release safety

Release ZIPs are built deterministically, hashed and rebuilt before publication. CI validates PowerShell syntax, PSScriptAnalyzer, Pester and scans Git history for secrets.

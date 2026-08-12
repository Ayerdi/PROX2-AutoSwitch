# Security

## Reporting a vulnerability

This project touches two trust-sensitive paths:

- **Logitech G HUB local WebSocket** (`ws://localhost:9010`): an undocumented, reverse-engineered interface. Treat it as unofficial and potentially changing.
- **NirSoft `svcl.exe` download**: the installer verifies the SHA-256 of `svcl-x64.zip` before running it. That check is intentional — never disable it.

Please **do not** open a public issue for a security problem that involves credentials, personal data or exploitable behavior. Report privately instead:

- Open a [private vulnerability report](https://github.com/Ayerdi/PROX2-AutoSwitch/security/advisories/new), or
- Email the maintainer directly if you have their address.

## Scope

- The SHA-256 pin for `svcl-x64.zip` lives in `Instalar-PROX2-AutoSwitch.ps1` (`$ExpectedSha256`). If NirSoft ships a new version, update it from the official hashes page — do not remove the check.
- `config.json` stores the current machine's Windows audio `Item ID`s because they are required to target endpoints; they are local identifiers, not secrets, and must not be copied between machines. Reconfigure may refresh the headset ID after endpoint recreation. The project does **not** persist the volatile G HUB `deviceId`, and repository/releases contain no user-specific IDs or credentials.

# Contributing

Thanks for helping improve Audio AutoSwitch.

Before proposing a change, read [SECURITY.md](SECURITY.md), [SOURCES.md](SOURCES.md) and [AGENT.md](AGENT.md). The project interacts with Windows Core Audio, a third-party command-line utility and an undocumented Logitech G HUB WebSocket, so evidence and safe failure behavior matter.

## Good contributions

- reproducible headset compatibility fixes;
- safer Windows endpoint detection;
- installer, tray or reconfiguration usability improvements;
- security hardening;
- tests and CI improvements;
- documentation and verified technical sources.

Avoid claiming a headset is supported unless its real ON/OFF behavior has been observed. `WindowsEndpoint` requires Windows to expose a useful endpoint state transition. Logitech PRO X 2 is the known exception handled through the G HUB fallback.

## Development checks

On Windows PowerShell / PowerShell:

```powershell
$ErrorActionPreference = 'Stop'

# Syntax
Get-ChildItem -Recurse -Include *.ps1,*.psm1 | ForEach-Object {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors) { throw "$($_.FullName): $($errors -join '; ')" }
}

# Tests
Import-Module Pester -RequiredVersion 5.9.0
Invoke-Pester -Path .\tests -CI
```

Do not remove checksum verification, unknown-state protection or OFF debounce to make a device appear compatible.

## Pull requests

1. Use a descriptive branch.
2. Add/update Pester coverage for logic changes.
3. Preserve Windows PowerShell 5.1 compatibility unless the project explicitly changes its support policy.
4. Document real hardware evidence for detection changes.
5. Never include machine-specific Item IDs, logs with personal data or private credentials.

Contributions are licensed under the repository's [MIT License](LICENSE).

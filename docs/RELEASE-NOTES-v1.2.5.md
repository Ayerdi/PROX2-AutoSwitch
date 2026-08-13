# Audio AutoSwitch v1.2.5

`v1.2.5` is a repository-quality and packaging maintenance release. Detection behavior is intentionally unchanged from v1.2.4.

## What changed

- English is canonical for the repository, Pages site, code comments, tests, technical documentation and release documentation.
- The versioned GitHub Wiki source now contains a complete English edition and a maintained Spanish edition.
- Canonical English PowerShell entrypoints are included in the release package:
  - `Install-AutoSwitch.ps1`
  - `Verify-AutoSwitch.ps1`
  - `Uninstall-AutoSwitch.ps1`
- Existing Spanish-named PowerShell entrypoints remain for backward compatibility.
- Repository governance now includes contributing, support, code-of-conduct, issue and pull-request guidance.
- CI adds secret scanning and repository/language quality checks.
- GitHub Actions are pinned to immutable commit SHAs.
- Release ZIP creation is deterministic and publication requires two byte-identical builds.

## Compatibility

There are no intentional changes to:

- `WindowsEndpoint` detection behavior;
- the Logitech G HUB fallback;
- OFF debounce behavior;
- Audio Enhancements behavior;
- config schema or migration behavior;
- the tested Bluetooth `Device Name + Name` re-resolution logic.

## Release assets

The release publishes both canonical and convenience names:

```text
PROX2-AutoSwitch-v1.2.5.zip
PROX2-AutoSwitch-v1.2.5.zip.sha256
Audio-AutoSwitch.zip
Audio-AutoSwitch.zip.sha256
```

The two ZIP names contain identical bytes and are accompanied by SHA-256 checksum files.

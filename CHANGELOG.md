# Changelog

All notable changes are documented here. The project follows Semantic Versioning.

## Unreleased

No pending changes after v1.2.5.

## 1.2.5 - 2026-08-12

### Added
- Canonical English PowerShell package entrypoints: `Install-AutoSwitch.ps1`, `Verify-AutoSwitch.ps1` and `Uninstall-AutoSwitch.ps1`.
- Versioned GitHub Wiki source with complete English and Spanish navigation.
- `CONTRIBUTING.md`, `SUPPORT.md`, `CODE_OF_CONDUCT.md` and a documentation index aligned with the companion Save Sync repository.
- Deterministic release builder, double-build verification and full-history Gitleaks scanning.

### Changed
- English is canonical across README, Pages, runtime diagnostics/comments and technical/maintenance documentation.
- GitHub Actions use pinned official action commits where practical.
- Release packaging is deterministic and no longer depends on an unpinned third-party release action.
- Existing `Install.cmd`, `Verify.cmd` and `Uninstall.cmd` from v1.2.4 remain the easiest entrypoints.
- Original Spanish-named PowerShell implementations remain for backward compatibility.

### Compatibility
- No intentional change to `WindowsEndpoint`, `LogitechGHub`, Unknown fail-safe behavior, OFF debounce, config schema or G HUB request protocol.

## 1.2.4 - 2026-08-12

### Added / improved
- Double-click `Install.cmd`, `Verify.cmd` and `Uninstall.cmd` launchers.
- Stable `Audio-AutoSwitch.zip` release asset alongside the versioned archive.
- Clean-install polling windows for real Bluetooth latency.
- Endpoint re-resolution by `Device Name` + `Name` when Bluetooth recreates an endpoint with a new Item ID.
- Detection-mode-aware verification.

## 1.2.3 - 2026-08-12

### Fixed
- `Reconfigure...` tolerates real Bluetooth latency with bounded polling.
- Recreated endpoints can be matched by stable Windows identity and their fresh Item ID persisted.
- Reconfiguration diagnostics were expanded.

## 1.2.2 - 2026-08-12

### Fixed
- Safer reconfiguration between `WindowsEndpoint` and `LogitechGHub`.
- Optional config fields are created/removed safely.
- Multiple PRO X 2 candidates require explicit user selection.

## 1.2.1 - 2026-08-12

### Fixed
- `Reconfigure...` runs the complete detection wizard and updates the detection mode/G HUB association correctly.

## 1.2.0 - 2026-08-12

### Added
- General `WindowsEndpoint` mode.
- Tray UI, Audio Enhancements helper and two-process runtime.
- Universal-first installation wizard and Pester coverage.

### Fixed
- Unknown state never switches output.
- Correct FxStore handling and Core Audio interop fixes.

## 1.1.0 - 2026-08-07

### Added
- Bounded G HUB timeouts, shared core module, Pester regressions and release checksum verification.

## 1.0.0 - 2026-08-07

### Added
- Initial PRO X 2 installer/runtime/uninstaller/verifier, G HUB detection and Windows output switching.

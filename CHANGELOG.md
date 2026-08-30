# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows [Semantic Versioning](https://semver.org/).

## [1.5.0] - 2026-08-31

### Fixed
- **Restored Logitech PRO X 2 LIGHTSPEED AutoSwitch after a G HUB API regression.** G HUB `2026.5.939708` was observed returning `NO_SUCH_PATH` for `GET /battery/<deviceId>/state`, while `/devices/list` kept the PRO X 2 receiver `ACTIVE` with `resourcesAvailable=true` even when the headset was physically off.
- PRO X 2 now bypasses that G HUB battery route and reads the LIGHTSPEED receiver directly through Logitech's Centurion HID protocol (`VID 046D`, `PID 0AF7`, `UsagePage 0xFFA0`, 64-byte reports).
- Direct HID was validated on real PRO X 2 hardware on 2026-08-31 with repeated real `ON → OFF → ON` cycles: valid battery frames selected the headset; two consecutive known OFF observations selected the configured fallback; returning ON selected the headset again.

### Added
- `lib/LogitechProX2Centurion.psm1`: isolated direct HID provider returning `Connected`, `Disconnected` or `Unknown`, plus `BatteryPercent`.
- PRO X 2 battery percentage and physical connection state in the tray; the tooltip also includes battery while connected.
- `tools/Test-LogitechProX2Centurion.ps1` for live direct-state/battery diagnostics.
- Pester coverage for PRO X 2 provider/config selection and release-package integration.

### Changed
- Existing `DetectionMode = LogitechGHub` configs remain backward compatible. When the configured headset is a PRO X 2, the runtime automatically prefers direct Centurion HID; other compatible Logitech headsets keep the existing G HUB provider.
- `Unknown` HID/open/read/protocol failures never switch audio. OFF still requires the configured consecutive-read debounce before the fallback is selected.
- Installer, verifier, README, English/Spanish Wiki source, website, maintainer notes, support/security notes, release tooling and package manifest were updated for v1.5.0.

## [1.4.0] - 2026-08-13

### Added
- **SteelSeries Arctis Nova 5/5X provider** (`SteelSeriesNova5` detection mode): reads the headset physical state directly over HID (P/Invoke to `hid.dll`/`setupapi.dll`, no SteelSeries GG or third-party software). Adds `lib/SteelSeriesNova5.psm1`, Pester tests and a diagnostic tool (`tools/Test-SteelSeriesNova5Hid.ps1`) to watch the receiver state live.
- Installer offers a "SteelSeries Arctis Nova 5/5X" option when picking the headset type; it verifies the HID receiver is present and writes `DetectionMode = SteelSeriesNova5`.
- Runtime worker supports the `SteelSeriesNova5` mode (state read every poll; `Unknown` never switches). Verifier shows the receiver presence for this mode.
- The release package now bundles the SteelSeries module and the diagnostic tool.

### Fixed
- **Logitech PRO X Wireless now detected via G HUB**: the G HUB filters hardcoded the `PRO\s*X\s*2` pattern, so any other PRO X headset (PRO X Wireless, PRO X) was skipped. New `Test-LogitechProXDeviceName` (in `AutoSwitchCore`, exported) matches PRO X / PRO X 2 / PRO X Wireless and excludes Logitech mouse names (e.g. G PRO X Superlight); used in the runtime fallback lookup and both installer G HUB filters. Prompts/logs now say "Logitech PRO X".

## [1.3.0] - 2026-08-13

### Changed
- Replaced the downloaded SoundVolumeCommandLine (`svcl.exe`) dependency with an in-process Windows Core Audio COM backend for endpoint enumeration, state reads, default-device reads and output switching. No third-party audio-control download is needed anymore.
- Default-output changes are now verified across Console, Multimedia and Communications roles before being accepted.
- Clean installs remove a stale legacy `svcl.exe` when present and no longer require a third-party audio-control download.

### Added
- Device pickers (installer and Reconfigure wizard) now list only endpoints whose `Device State` is `Active`, so you cannot pick a `NotPresent`/`Disabled` device by mistake; if no endpoint is `Active`, all are shown with a notice.
- Installer shortcut after picking headset/fallback: choose to validate the `ON → OFF → ON` cycle (auto-detects the detection mode) or use the selected endpoints as-is assuming `WindowsEndpoint` (skips the power on/off dance).

## [1.2.5] - 2026-08-13

### Added
- Versioned GitHub Wiki source with a complete English edition and a maintained Spanish edition.
- Canonical English PowerShell entrypoints: `Install-AutoSwitch.ps1`, `Verify-AutoSwitch.ps1`, and `Uninstall-AutoSwitch.ps1`.
- Repository governance: `CONTRIBUTING.md`, `SUPPORT.md`, `CODE_OF_CONDUCT.md`, issue forms and a pull-request template.
- Reproducible release tooling with deterministic ZIP creation, SHA-256 files and double-build byte comparison.
- Gitleaks secret scanning and repository/language quality checks in CI.

### Changed
- English is now the canonical language for the repository, runtime comments, tests, technical docs, GitHub Pages and release documentation.
- The Spanish-named PowerShell entrypoints remain in the package for backward compatibility, while new documentation uses the English aliases.
- GitHub Pages is now English-first; Spanish documentation lives in the Spanish Wiki path.
- Actions are pinned to immutable commit SHAs and checkout credentials are not persisted in validation jobs.
- Public project navigation now follows the same README → Website → Wiki → Docs/Support/Security → Releases structure used by the companion Dedicated Server Save Sync project.

### Security
- Release publication verifies repository quality and secret scanning before producing assets.
- The release archive is built twice and must be byte-identical before publication.

## [1.2.4] - 2026-08-13

### Added
- Double-click `Install.cmd`, `Verify.cmd`, and `Uninstall.cmd` launchers for users who download the release ZIP.
- Release packaging publishes the stable `Audio-AutoSwitch.zip` + SHA-256 alias in addition to the versioned archive.

### Fixed
- Clean installation polls Bluetooth/Core Audio transitions for 15 s / 15 s / 20 s and refreshes a recreated headset Item ID by `Device Name` + `Name`, matching the hardened Reconfigure flow.
- The verifier no longer reports G HUB as a failure for generic `WindowsEndpoint` installations.
- The one-command bootstrap uses generic Audio AutoSwitch wording.
- Leftover one-shot documentation workflows/scripts were removed from `.github/`.
- `Reconfigure...` re-resolves a recreated Bluetooth endpoint using the real `svcl` identity columns **`Device Name` + `Name`**, not the combined display label. This avoids collisions between multiple render endpoints belonging to the same device and handles a headset returning with a different `Item ID`. Regression tests cover exact identity matching.

### Changed
- README, GitHub Pages, maintainer notes, security/source notes and the historical WindowsEndpoint design document were refreshed to match the post-v1.2.3 behavior and hardware findings.

## [1.2.3] - 2026-08-12

### Fixed
- **`Reconfigure...` now tolerates real Bluetooth headset latency.** The wizard polls every 500 ms and allows up to 15 s for the first ON state, 15 s for OFF and 20 s for the final ON. This prevents false negatives when Windows needs several seconds to expose `Active` or `Unplugged`.
- **Bluetooth endpoints may return with a different `Item ID` after power cycling.** If the original ID disappears, Reconfigure locates the same endpoint by stable identity, uses the observed state and stores the newest `Item ID`. This was validated on real Jabra Evolve 65 hardware across `ON → OFF → ON`, restart and another `OFF → ON` cycle.
- Added detailed diagnostics when a state transition does not arrive before the bounded wait: the log records the last state and the endpoints/IDs visible through `svcl`.
- `Invoke-Reconfigure` also wraps dialog creation/opening in `try/catch`, so failures that occur before mode detection are written to `autoswitch.log`.

## [1.2.2] - 2026-08-12

### Fixed
- Hardened `Reconfigure...` when switching between `WindowsEndpoint` and `LogitechGHub`: a `WindowsEndpoint` config may not contain `GHubPort`; when reconfiguring to a PRO X 2, `Connect-GHub` now safely defaults to port 9010 instead of failing on a missing property.
- Optional config fields (`DetectionMode`, `EnhancementsDeviceId`, `GHubDisplayName`, `GHubPort`) are created or updated with `Add-Member -Force`; obsolete G HUB fields are removed when switching to `WindowsEndpoint` so stale associations are not retained.
- If G HUB exposes multiple PRO X 2 devices, the wizard asks the user to confirm the matching candidate instead of guessing. Cancel leaves the existing configuration untouched.

## [1.2.1] - 2026-08-12

### Fixed
- **Tray `Reconfigure...` now runs the complete detection wizard** instead of only replacing `HeadsetId`/`SpeakerId`. The previous implementation could leave an old detection mode or G HUB association behind when switching between a PRO X 2 and a generic headset.
- Reconfiguration now validates `ON → OFF → ON`, determines `WindowsEndpoint` or `LogitechGHub`, updates the relevant config fields and preserves the old configuration if compatibility cannot be proven.
- The README included in the v1.2.0 tag/package described an older G-HUB-first installer flow. Documentation was corrected to match the universal-first implementation.

## [1.2.0] - 2026-08-12

### Added
- Universal `WindowsEndpoint` mode: reads the Windows audio endpoint state from `svcl /scomma` and maps physical state. A Jabra Evolve 65 was validated with `Active → Connected` and `Unplugged`/absence → `Disconnected`.
- `DetectionMode` config field (`WindowsEndpoint` | `LogitechGHub`). Existing configs without the field remain backward compatible and are interpreted as `LogitechGHub` before migration.
- System tray runtime with its own icon: enable/disable AutoSwitch, toggle Audio Enhancements for the configured headset and exit.
- Tray information lines for Headset / Fallback / Next switch and a **Reconfigure...** action that chooses current Windows endpoints without requiring a reinstall.
- Two-process runtime architecture: the polling loop runs in a separate worker process (`AUTOSWITCH_WORKER=1`) while WinForms owns the responsive tray/message pump. Control flags under `control/` coordinate enable, reload and stop operations.
- `Toggle-AudioEnhancements.ps1`: temporary elevated helper that writes `PKEY_AudioEndpoint_Disable_SysFx` through `IPolicyConfig`, verifies the change and exits. The runtime itself remains non-elevated.
- Universal installer flow: choose headset + fallback, auto-detect `WindowsEndpoint` when Windows exposes the physical state, otherwise offer the PRO X 2 G HUB fallback, and abort safely if no compatible method can be proven.
- Optional `DisableEnhancementsOnStart` and `EnhancementsDeviceId` configuration.
- COM interop implemented in C# via `Add-Type` so PowerShell 5.1 can reliably use the required `[ComImport]` interfaces.
- Pester coverage for real `svcl /scomma` parsing, render-device filtering, endpoint labels, export validation and endpoint-state mapping.
- User-visible installer, runtime, helper, verifier and uninstaller text moved to English.

### Changed
- Config v1.2.0 records `DetectionMode`; existing G HUB installations retain their behavior.
- Runtime starts the worker with `$PSCommandPath` because `$MyInvocation.MyCommand.Path` can be empty inside functions in PowerShell 5.1.
- Runtime expects `Toggle-AudioEnhancements.ps1` and `icon.ico` in the install directory.
- Verifier reports detection mode, headset endpoint state and Audio Enhancements state.
- `LogitechGHub` mode keeps a persistent G HUB connection and resolves the current device ID again after reconnect failures.
- PowerShell files containing non-ASCII characters use UTF-8 BOM where required by the validation toolchain.

### Fixed
- `Unknown` endpoint state never changes the output. Invalid/empty exports and transient `svcl` failures therefore cannot send audio to the fallback.
- `Get-EndpointFxState` now reads `PKEY_AudioEndpoint_Disable_SysFx` from the FxStore through `IPolicyConfig::GetPropertyValue(..., bFxStore=true)`, matching the store written by the elevated helper.
- Corrected the `Add-Type` sentinel so the COM block is not compiled again on every call.
- `Get-SvclRenderDevice` returns arrays correctly and uses reliable CSV-column access.
- Removed installer functions that became unused after the universal selection-flow redesign.
- Replaced the generic system tray icon with the project icon.

### Security
- The G HUB WebSocket at `ws://localhost:9010` is an unofficial local interface and may change in future G HUB releases. Verified sources and constraints are documented in `AGENT.md` and `SOURCES.md`.

## [1.1.0] - 2026-08-07

### Added
- Bounded G HUB WebSocket timeouts: connection (5 s), response wait (5 s) and overall request limit (10 s). Timeout recovery closes the socket, logs the event and retries; unknown state never changes the output.
- Hard-bounded WebSocket close: `CloseAsync` waits at most 1 s, then `Abort()` + `Dispose()` guarantees recovery cannot hang on a stuck G HUB connection.
- `lib/AutoSwitchCore.psm1` shared pure logic for Item ID extraction, OFF debounce, config validation and request timeout helpers.
- Pester CI coverage for valid/invalid Item IDs, the `/Stdout` regression, debounce behavior, config validation and timeout cancellation.
- `install.ps1` verifies the release ZIP SHA-256 before extraction/execution, chooses exactly one versioned project archive and always cleans temporary files in `finally`.
- Release workflow publishes a versioned ZIP and SHA-256 checksum.
- Uninstaller reports process, startup and directory cleanup separately and distinguishes complete success from partial cleanup failure.

### Changed
- Installation config gained `ConnectTimeoutMs`, `ReceiveTimeoutMs` and `RequestTimeoutMs`.
- One-command install accepts only releases that provide a checksum asset.

### Fixed
- Removed misleading `$LASTEXITCODE` checking after launching the PowerShell installer; failures propagate as exceptions.
- Hardened uninstall path-boundary detection.
- Verifier reads `GHubPort` from config rather than hardcoding 9010.

## [1.0.0] - 2026-08-07

### Added
- Initial installer with verified NirSoft SoundVolumeCommandLine download, real Item ID calibration, bidirectional switch tests and invisible startup through `wscript.exe`.
- Runtime that detects the physical PRO X 2 state through the local G HUB WebSocket and changes the Windows default output.
- Uninstaller and verifier.
- One-command bootstrap that downloads the latest GitHub release and starts the complete installer.
- GitHub Pages project site.
- CI for PowerShell syntax and PSScriptAnalyzer validation.

### Known limitations
- Initial implementation supported only two outputs: headset and fallback.
- The G HUB WebSocket is not an official Logitech API and may change.

# v1.4.0 — SteelSeries Nova 5/5X provider + Logitech PRO X Wireless support

## What's new

### SteelSeries Arctis Nova 5/5X (HID)
- New `SteelSeriesNova5` detection mode: reads the headset physical state directly over HID (P/Invoke to `hid.dll`/`setupapi.dll`). No SteelSeries GG or third-party software.
- The installer offers a "SteelSeries Arctis Nova 5/5X" option when picking the headset type; it verifies the HID receiver is present before enabling the mode.
- Diagnostic tool to watch the receiver live: `tools/Test-SteelSeriesNova5Hid.ps1` (turn the headset ON/OFF and see Connected/Disconnected).

### Logitech PRO X Wireless (and any PRO X)
- G HUB detection now matches **PRO X, PRO X 2 and PRO X Wireless** (previously only PRO X 2), so PRO X Wireless users can use the LIGHTSPEED battery signal as the ON/OFF source.
- Logitech mouse names (e.g. G PRO X Superlight) are excluded from the headset candidates.

## Carried over from v1.3.0
- Native Windows Core Audio backend replaces `svcl.exe` — no third-party audio-control download.
- Output switches verified across Console, Multimedia and Communications.
- Installer/Reconfigure pickers list only `Active` endpoints; installer shortcut to skip the ON→OFF→ON cycle.

## Notes
- CI validates syntax, lint, Pester and quality; real headset behavior should be verified with the diagnostic tools (SteelSeries HID tool, or the normal Jabra / PRO X manual test).

# Audio AutoSwitch v1.5.0

v1.5.0 restores reliable Logitech PRO X 2 LIGHTSPEED switching after a change in Logitech G HUB's undocumented local API, and adds live PRO X 2 battery information to the tray.

## What happened

G HUB `2026.5.939708` was observed returning `NO_SUCH_PATH` for `GET /battery/<deviceId>/state`, while `/devices/list` continued to report the PRO X 2 receiver as `ACTIVE` even with the headset physically powered off. That removed the physical-state signal used by v1.4.x.

## What changed

PRO X 2 LIGHTSPEED (`VID 046D`, `PID 0AF7`) now uses Logitech's Centurion HID protocol directly through UsagePage `0xFFA0` and 64-byte reports. A valid battery reply means Connected and includes battery percentage. The known OFF signature means a disconnected observation. Any HID/open/read/protocol error is Unknown and never changes output; OFF still requires consecutive confirmations.

Existing `DetectionMode = LogitechGHub` configs remain compatible. The runtime automatically chooses Centurion for PRO X 2; other compatible Logitech headsets keep the G HUB provider.

## Tray battery

A connected PRO X 2 now shows connection state and battery, for example `Battery: 76%`. When powered off the tray shows Disconnected without a stale battery value.

## Hardware validation

On August 31, 2026 the direct provider completed repeated real `ON → OFF → ON` cycles. OFF selected the configured fallback after two confirmed observations; ON selected the PRO X 2 again. Battery values of 70% and 76% were observed during the end-to-end run.

## Included updates

- direct PRO X 2 provider and diagnostic tool;
- verifier direct-state/battery reporting;
- installer direct-HID preference;
- tray state/battery display;
- Pester coverage;
- deterministic v1.5.0 packaging;
- README, Wiki source (English and Spanish), website, changelog, sources, support, security and maintainer docs updated.

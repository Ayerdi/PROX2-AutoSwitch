# Support

Use GitHub Issues for reproducible bugs and compatibility reports. Use the Wiki and README first for installation, reconfiguration and troubleshooting.

A useful report includes:

- AutoSwitch release/version;
- Windows version;
- headset make/model and connection type;
- selected detection mode (`WindowsEndpoint`, `LogitechGHub` or `SteelSeriesNova5`) and, for PRO X 2, the direct HID state shown by `Verify.cmd`;
- the smallest relevant **redacted** log excerpt;
- whether the endpoint changes between `Active`, `Unplugged`, absent or another state when the headset is powered off/on.

Do not publish credentials, private paths, unrelated device identifiers or complete logs containing personal information.

Compatibility cannot be guaranteed for every wireless headset. The universal path depends on the state Windows exposes. Starting in v1.5.0, PRO X 2 LIGHTSPEED uses its receiver directly through Centurion HID; other Logitech G HUB providers still depend on an unofficial local interface that Logitech may change.

For security-sensitive problems use [SECURITY.md](SECURITY.md), not a public issue.

## PRO X 2 after a G HUB update

If a PRO X 2 installation stopped switching after a G HUB update, install v1.5.0 or newer and run `Verify.cmd`. The verifier should report the direct Centurion HID provider plus `Connected`/`Disconnected` state and battery when available.

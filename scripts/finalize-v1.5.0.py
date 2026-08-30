from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel, bom=False):
    enc = "utf-8-sig" if bom else "utf-8"
    return (ROOT / rel).read_text(encoding=enc)


def write(rel, text, bom=False):
    enc = "utf-8-sig" if bom else "utf-8"
    (ROOT / rel).write_text(text, encoding=enc)


def once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# Installer must write the actual release version into new config.json files.
installer = read("Instalar-PROX2-AutoSwitch.ps1", bom=True)
installer = once(
    installer,
    '        Version                = "1.4.0"',
    '        Version                = "1.5.0"',
    "installer config version",
)
write("Instalar-PROX2-AutoSwitch.ps1", installer, bom=True)


# Keep direct PRO X 2 status/battery polling alive while switching is paused.
# Only Centurion polls in this state; no Resolve-HeadsetState/Set-AudioOutput call
# is allowed until enabled.flag exists again.
runtime = read("Runtime-PROX2-AutoSwitch.ps1", bom=True)
runtime = once(
    runtime,
    '''        $enabled = Test-Path $enabledFlag
        if (-not $enabled) {
            Start-Sleep -Milliseconds ([int]$Config.PollMilliseconds)
            continue
        }
''',
    '''        $enabled = Test-Path $enabledFlag
        $centurionStatusOnly = (-not $enabled) -and
            $script:DetectionMode -eq 'LogitechGHub' -and
            $script:CenturionAvailable -and
            (Test-LogitechProX2CenturionConfig -Config $Config)

        if (-not $enabled -and -not $centurionStatusOnly) {
            Start-Sleep -Milliseconds ([int]$Config.PollMilliseconds)
            continue
        }

        if ($centurionStatusOnly) {
            # Keep tray telemetry fresh while AutoSwitch is paused, but discard
            # switching history so re-enabling starts from a clean observation.
            $misses = 0
            $lastState = $null
        }
''',
    "runtime paused Centurion polling",
)
runtime = once(
    runtime,
    '''        if ($known) {
            # Debounce: solo se decide OFF tras OffMissThreshold lecturas.
''',
    '''        if ($known -and $enabled) {
            # Debounce: solo se decide OFF tras OffMissThreshold lecturas.
''',
    "runtime switching gate",
)
write("Runtime-PROX2-AutoSwitch.ps1", runtime, bom=True)


# PSScriptAnalyzer requires a BOM for this non-ASCII Windows PowerShell test.
test_path = ROOT / "tests/LogitechProX2Centurion.Tests.ps1"
test_text = test_path.read_text(encoding="utf-8-sig")
test_path.write_text(test_text, encoding="utf-8-sig")


readme = read("README.md")
readme = once(
    readme,
    '- **AutoSwitch: Enabled / Disabled** — pause or resume switching.',
    '- **AutoSwitch: Enabled / Disabled** — pause or resume switching. On PRO X 2, direct HID connection state and battery continue refreshing while switching is paused; audio outputs are never changed until AutoSwitch is enabled again.',
    "README paused telemetry",
)
write("README.md", readme)


changelog = read("CHANGELOG.md")
changelog = once(
    changelog,
    '- PRO X 2 battery percentage and physical connection state in the tray; the tooltip also includes battery while connected.',
    '- PRO X 2 battery percentage and physical connection state in the tray; the tooltip also includes battery while connected. Centurion telemetry keeps refreshing while AutoSwitch is paused, without changing any audio output.',
    "changelog paused telemetry",
)
write("CHANGELOG.md", changelog)


notes = read("docs/RELEASE-NOTES-v1.5.0.md")
notes = once(
    notes,
    'A connected PRO X 2 now shows connection state and battery, for example `Battery: 76%`. When powered off the tray shows Disconnected without a stale battery value.',
    'A connected PRO X 2 now shows connection state and battery, for example `Battery: 76%`. When powered off the tray shows Disconnected without a stale battery value. Direct Centurion telemetry continues to refresh while AutoSwitch is paused, but no audio output is changed until switching is enabled again.',
    "release notes paused telemetry",
)
write("docs/RELEASE-NOTES-v1.5.0.md", notes)


wiki_en = read("wiki/Tray-and-Reconfiguration.md")
wiki_en = once(
    wiki_en,
    '- enable/disable automatic switching without exiting;',
    '- enable/disable automatic switching without exiting; PRO X 2 direct HID state/battery keeps refreshing while switching is paused, but outputs are not changed;',
    "English Wiki paused telemetry",
)
write("wiki/Tray-and-Reconfiguration.md", wiki_en)


wiki_es = read("wiki/Bandeja-y-reconfiguracion.md")
wiki_es = once(
    wiki_es,
    '- activar/desactivar AutoSwitch;',
    '- activar/desactivar AutoSwitch; en PRO X 2 el estado y la batería por HID directo siguen actualizándose mientras AutoSwitch está pausado, pero no se cambia ninguna salida de audio;',
    "Spanish Wiki paused telemetry",
)
write("wiki/Bandeja-y-reconfiguracion.md", wiki_es)

print("Final v1.5.0 fixes applied.")

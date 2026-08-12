from pathlib import Path
import re

ROOT = Path('.')

def read(path):
    return Path(path).read_text(encoding='utf-8-sig')

def write(path, text):
    Path(path).write_text(text, encoding='utf-8')

def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f'{label}: expected text not found')
    if text.count(old) != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {text.count(old)}')
    return text.replace(old, new, 1)

# ---------------------------------------------------------------------------
# 1) Bootstrap installer: English-only visible UI + generic branding.
# ---------------------------------------------------------------------------
install_bootstrap = r'''#requires -Version 5.1
$ErrorActionPreference = "Stop"

# PowerShell 5.1 on older .NET may negotiate TLS 1.0/1.1 and fail against
# GitHub/NirSoft. Force TLS 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Audio AutoSwitch one-command bootstrap.
# Downloads the latest GitHub Release ZIP plus its SHA-256 checksum and only
# runs the real installer after the package integrity has been verified.

$Repo = "Ayerdi/PROX2-AutoSwitch"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
$ZipPattern = "PROX2-AutoSwitch-*.zip"
$ChecksumSuffix = ".sha256"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Audio AutoSwitch" -ForegroundColor Cyan
Write-Host " Quick install" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Looking for the latest release..." -ForegroundColor Yellow

$release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ "User-Agent" = "Audio-AutoSwitch-installer" }

$zipAssets = @($release.assets | Where-Object { $_.name -like $ZipPattern })
if ($zipAssets.Count -ne 1) {
    throw "Expected exactly one project ZIP ($ZipPattern) in release $($release.tag_name), but found $($zipAssets.Count)."
}
$zipAsset = $zipAssets[0]

$checksumName = $zipAsset.name + $ChecksumSuffix
$checksumAsset = $release.assets | Where-Object { $_.name -eq $checksumName } | Select-Object -First 1
if (-not $checksumAsset) {
    throw "Release $($release.tag_name) does not publish $checksumName. Integrity cannot be verified, so installation is aborted."
}

$ZipPath = Join-Path $env:TEMP $zipAsset.name
$ChecksumPath = Join-Path $env:TEMP $checksumName
$ExtractDir = Join-Path $env:TEMP "PROX2-AutoSwitch-extract"

try {
    Write-Host "Version $($release.tag_name)" -ForegroundColor Green
    Write-Host "Downloading $($zipAsset.name) and checksum..." -ForegroundColor Yellow
    Invoke-WebRequest -UseBasicParsing -Uri $zipAsset.browser_download_url -OutFile $ZipPath
    Invoke-WebRequest -UseBasicParsing -Uri $checksumAsset.browser_download_url -OutFile $ChecksumPath

    Write-Host "Verifying SHA-256..." -ForegroundColor Yellow
    $expectedLine = (Get-Content -Raw $ChecksumPath).Trim()
    $expectedHash = ($expectedLine -split "\s+")[0].ToLowerInvariant()
    if (-not $expectedHash -or $expectedHash -notmatch '^[0-9a-f]{64}$') {
        throw "The downloaded checksum is not a valid SHA-256 value."
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -Path $ZipPath).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "The ZIP SHA-256 does not match the published checksum. Installation is aborted. Expected=$expectedHash Actual=$actualHash"
    }
    Write-Host "      SHA-256 OK." -ForegroundColor Green

    Write-Host "Extracting..." -ForegroundColor Yellow
    if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

    $Installer = Join-Path $ExtractDir "Instalar-PROX2-AutoSwitch.ps1"
    if (-not (Test-Path $Installer)) {
        # Releases may contain a wrapper directory, so search one level deeper.
        $nested = Get-ChildItem -Path $ExtractDir -Recurse -Filter "Instalar-PROX2-AutoSwitch.ps1" |
            Select-Object -First 1
        if ($nested) { $Installer = $nested.FullName }
    }
    if (-not (Test-Path $Installer)) {
        throw "The installer was not found inside the release ZIP."
    }

    & $Installer
}
finally {
    # Leave no temporary package behind, including on failure.
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $ChecksumPath -Force -ErrorAction SilentlyContinue
    Remove-Item $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
}
'''
write('install.ps1', install_bootstrap)

# ---------------------------------------------------------------------------
# 2) Clean installer: robust ON/OFF/ON polling + Bluetooth Item ID recovery.
# ---------------------------------------------------------------------------
p = Path('Instalar-PROX2-AutoSwitch.ps1')
text = read(p)
text = text.replace(' PRO X 2 LIGHTSPEED - Audio AutoSwitch', ' Audio AutoSwitch')

old = '''    $headsetId   = Get-CsvColumn -Row $chosenHeadset -Names @('Item ID')
    $speakerId   = Get-CsvColumn -Row $chosenSpeaker -Names @('Item ID')
    $headsetName = Get-SvclDeviceLabel -Row $chosenHeadset
    $speakerName = Get-SvclDeviceLabel -Row $chosenSpeaker
'''
new = '''    $headsetId           = Get-CsvColumn -Row $chosenHeadset -Names @('Item ID')
    $speakerId           = Get-CsvColumn -Row $chosenSpeaker -Names @('Item ID')
    $headsetName         = Get-SvclDeviceLabel -Row $chosenHeadset
    $speakerName         = Get-SvclDeviceLabel -Row $chosenSpeaker
    $headsetDeviceName   = Get-CsvColumn -Row $chosenHeadset -Names @('Device Name')
    $headsetEndpointName = Get-CsvColumn -Row $chosenHeadset -Names @('Name')
'''
text = replace_once(text, old, new, 'installer identity capture')

start_marker = '''    function Get-HeadsetCsvState {
        param([string]$ItemId)
'''
start = text.find(start_marker)
if start < 0:
    raise SystemExit('installer: old Get-HeadsetCsvState block not found')
end_marker = '''    if ($sOn1 -eq 'Connected' -and $sOff -eq 'Disconnected' -and $sOn2 -eq 'Connected') {'''
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit('installer: state decision marker not found')

replacement = r'''    function Get-HeadsetInstallState {
        param(
            [Parameter(Mandatory = $true)][string]$ItemId,
            [string]$DeviceName,
            [string]$EndpointName
        )

        $txt = (& $SvclPath /scomma "" 2>&1 | Out-String).Trim()
        if (-not (Test-SvclExportValid -CsvText $txt)) {
            return [pscustomobject]@{ State = 'Unknown'; FoundId = $null }
        }

        $rows = @(ConvertFrom-SvclCsv -Text $txt)
        $row = $rows | Where-Object {
            $id = Get-CsvColumn -Row $_ -Names @('Item ID')
            $null -ne $id -and $id.Trim() -ieq $ItemId.Trim()
        } | Select-Object -First 1

        # Bluetooth can recreate an endpoint with a new Item ID after reconnect.
        # Resolve the same Render endpoint by its real svcl identity rather than
        # treating the user-facing "Device Name — Name" label as one column.
        if (-not $row -and
            (-not [string]::IsNullOrWhiteSpace($DeviceName) -or
             -not [string]::IsNullOrWhiteSpace($EndpointName))) {
            $row = Find-SvclRenderDeviceByIdentity -Rows $rows -DeviceName $DeviceName -Name $EndpointName
        }

        if (-not $row) {
            return [pscustomobject]@{ State = 'Disconnected'; FoundId = $null }
        }

        $state = Get-CsvColumn -Row $row -Names @('Device State', 'State')
        $foundId = Get-CsvColumn -Row $row -Names @('Item ID')
        if ([string]::IsNullOrWhiteSpace($state)) {
            return [pscustomobject]@{ State = 'Unknown'; FoundId = $foundId }
        }

        return [pscustomobject]@{
            State   = (Resolve-EndpointState -State $state)
            FoundId = $foundId
        }
    }

    function Wait-ForHeadsetInstallState {
        param(
            [Parameter(Mandatory = $true)][string]$ItemId,
            [Parameter(Mandatory = $true)][string]$Expected,
            [string]$DeviceName,
            [string]$EndpointName,
            [int]$TimeoutSeconds,
            [int]$PollIntervalMs = 500
        )

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $currentId = $ItemId
        $lastState = 'Unknown'
        $lastFoundId = $null

        do {
            $res = Get-HeadsetInstallState -ItemId $currentId -DeviceName $DeviceName -EndpointName $EndpointName
            $lastState = $res.State
            if (-not [string]::IsNullOrWhiteSpace([string]$res.FoundId)) {
                $lastFoundId = [string]$res.FoundId
                $currentId = $lastFoundId
            }

            if ($lastState -eq $Expected) {
                return [pscustomobject]@{ State = $lastState; FoundId = $lastFoundId }
            }

            Start-Sleep -Milliseconds $PollIntervalMs
        } while ((Get-Date) -lt $deadline)

        return [pscustomobject]@{ State = $lastState; FoundId = $lastFoundId }
    }

    Write-Host "      Waiting for Windows to report the headset as connected (up to 15 s)..." -ForegroundColor DarkGray
    $rOn1 = Wait-ForHeadsetInstallState -ItemId $headsetId -Expected 'Connected' -DeviceName $headsetDeviceName -EndpointName $headsetEndpointName -TimeoutSeconds 15
    $sOn1 = $rOn1.State
    if ($rOn1.FoundId) { $headsetId = [string]$rOn1.FoundId }

    Write-Host ""
    Write-Host "Turn the headset OFF and press ENTER..." -ForegroundColor Cyan
    [void](Read-Host)
    Write-Host "      Waiting for Windows to report the headset as disconnected (up to 15 s)..." -ForegroundColor DarkGray
    $rOff = Wait-ForHeadsetInstallState -ItemId $headsetId -Expected 'Disconnected' -DeviceName $headsetDeviceName -EndpointName $headsetEndpointName -TimeoutSeconds 15
    $sOff = $rOff.State
    if ($rOff.FoundId) { $headsetId = [string]$rOff.FoundId }

    Write-Host "Turn the headset back ON and press ENTER..." -ForegroundColor Cyan
    [void](Read-Host)
    Write-Host "      Waiting for Windows to report the headset as connected (up to 20 s)..." -ForegroundColor DarkGray
    $rOn2 = Wait-ForHeadsetInstallState -ItemId $headsetId -Expected 'Connected' -DeviceName $headsetDeviceName -EndpointName $headsetEndpointName -TimeoutSeconds 20
    $sOn2 = $rOn2.State
    if ($rOn2.FoundId -and ([string]$rOn2.FoundId -ine $headsetId)) {
        Write-Host "      Bluetooth endpoint was recreated; refreshed its Windows Item ID." -ForegroundColor DarkGray
        $headsetId = [string]$rOn2.FoundId
    }

    Write-Host ""
    Write-Host ("      State ON (initial):  {0}" -f $sOn1) -ForegroundColor DarkGray
    Write-Host ("      State OFF:           {0}" -f $sOff) -ForegroundColor DarkGray
    Write-Host ("      State ON (final):    {0}" -f $sOn2) -ForegroundColor DarkGray

'''
text = text[:start] + replacement + text[end:]

# Avoid a stale ID in the output object after the Bluetooth cycle.
text = replace_once(
    text,
    '''    $headsetOutput = [pscustomobject]@{
        Name   = $headsetName
        ItemId = $headsetId
    }
''',
    '''    $headsetOutput = [pscustomobject]@{
        Name   = $headsetName
        ItemId = $headsetId
    }
''',
    'installer output object sanity'
)
write(p, text)

# ---------------------------------------------------------------------------
# 3) Verifier: generic branding and G HUB check only when that mode is active.
# ---------------------------------------------------------------------------
p = Path('Verificar-PROX2-AutoSwitch.ps1')
text = read(p)
text = text.replace('=== PRO X 2 AutoSwitch verification ===', '=== Audio AutoSwitch verification ===')

start = text.find('$ghubPort = $false')
end = text.find('if (Test-Path $ConfigPath) {', start)
if start < 0 or end < 0:
    raise SystemExit('verifier: G HUB block markers not found')

new_block = r'''$cfg = $null
$mode = $null
if (Test-Path $ConfigPath) {
    try {
        $cfg = Get-Content -Raw $ConfigPath | ConvertFrom-Json
        $mode = Get-ConfigDetectionMode -Config $cfg
    }
    catch {}
}

if ($mode -eq 'LogitechGHub') {
    $ghubPort = $false
    $ghubPortToTest = 9010
    if ($cfg -and $cfg.PSObject.Properties['GHubPort'] -and $cfg.GHubPort) {
        $ghubPortToTest = [int]$cfg.GHubPort
    }
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect("127.0.0.1", $ghubPortToTest, $null, $null)
        $ghubPort = $iar.AsyncWaitHandle.WaitOne(1000, $false)
        if ($ghubPort) { $client.EndConnect($iar) }
        $client.Close()
    }
    catch {
        $ghubPort = $false
    }

    $ghubDetail = if ($ghubPort) { "Port reachable" } else { "Open Logitech G HUB" }
    Show-Test "G HUB localhost:$ghubPortToTest" $ghubPort $ghubDetail
}
elif_PLACEHOLDER

'''.replace('elif_PLACEHOLDER', '''elseif ($mode -eq 'WindowsEndpoint') {
    Write-Host "[SKIP] G HUB (not used in WindowsEndpoint mode)" -ForegroundColor DarkGray
}
else {
    Show-Test "Detection mode" $false "Could not read a valid DetectionMode from config.json"
}''')
text = text[:start] + new_block + text[end:]

# Reuse cfg already loaded when possible, while keeping the existing detail output.
text = text.replace(
    '''if (Test-Path $ConfigPath) {
    try {
        $cfg = Get-Content -Raw $ConfigPath | ConvertFrom-Json
        Write-Host ""
''',
    '''if (Test-Path $ConfigPath) {
    try {
        if (-not $cfg) { $cfg = Get-Content -Raw $ConfigPath | ConvertFrom-Json }
        Write-Host ""
''',
    1
)
write(p, text)

# ---------------------------------------------------------------------------
# 4) Double-click wrappers. Keep all real logic in PowerShell.
# ---------------------------------------------------------------------------
wrappers = {
    'Install.cmd': r'''@echo off
setlocal
title Audio AutoSwitch - Install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Instalar-PROX2-AutoSwitch.ps1"
set "exitCode=%ERRORLEVEL%"
echo.
if not "%exitCode%"=="0" echo Installation exited with code %exitCode%.
pause
exit /b %exitCode%
''',
    'Verify.cmd': r'''@echo off
setlocal
title Audio AutoSwitch - Verify
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Verificar-PROX2-AutoSwitch.ps1"
set "exitCode=%ERRORLEVEL%"
echo.
pause
exit /b %exitCode%
''',
    'Uninstall.cmd': r'''@echo off
setlocal
title Audio AutoSwitch - Uninstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Desinstalar-PROX2-AutoSwitch.ps1"
set "exitCode=%ERRORLEVEL%"
echo.
pause
exit /b %exitCode%
'''
}
for name, content in wrappers.items():
    write(name, content)

# ---------------------------------------------------------------------------
# 5) Release ZIP: include wrappers and publish a stable-name ZIP alias too.
# ---------------------------------------------------------------------------
release = r'''name: release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build release ZIP and checksums
        run: |
          set -euo pipefail
          VERSION="${GITHUB_REF#refs/tags/}"
          PACKAGE_DIR="PROX2-AutoSwitch-$VERSION"
          VERSIONED_ZIP="PROX2-AutoSwitch-$VERSION.zip"
          STABLE_ZIP="Audio-AutoSwitch.zip"

          rm -rf "$PACKAGE_DIR"
          mkdir -p "$PACKAGE_DIR/lib"
          mkdir -p "$PACKAGE_DIR/assets"
          cp Install.cmd Verify.cmd Uninstall.cmd \
             Instalar-PROX2-AutoSwitch.ps1 \
             Runtime-PROX2-AutoSwitch.ps1 \
             Desinstalar-PROX2-AutoSwitch.ps1 \
             Verificar-PROX2-AutoSwitch.ps1 \
             Toggle-AudioEnhancements.ps1 \
             install.ps1 \
             README.md AGENT.md SOURCES.md SECURITY.md LICENSE CHANGELOG.md \
             "$PACKAGE_DIR/"
          cp lib/AutoSwitchCore.psm1 "$PACKAGE_DIR/lib/"
          cp assets/icon.ico "$PACKAGE_DIR/assets/"

          zip -r "$VERSIONED_ZIP" "$PACKAGE_DIR"
          sha256sum "$VERSIONED_ZIP" > "$VERSIONED_ZIP.sha256"

          # Stable asset name gives docs/users one permanent latest-release URL.
          cp "$VERSIONED_ZIP" "$STABLE_ZIP"
          sha256sum "$STABLE_ZIP" > "$STABLE_ZIP.sha256"

      - name: Upload release assets
        uses: softprops/action-gh-release@v2
        with:
          files: |
            PROX2-AutoSwitch-*.zip
            PROX2-AutoSwitch-*.zip.sha256
            Audio-AutoSwitch.zip
            Audio-AutoSwitch.zip.sha256
          generate_release_notes: true
'''
write('.github/workflows/release.yml', release)

# ---------------------------------------------------------------------------
# 6) CI checks wrappers are present too.
# ---------------------------------------------------------------------------
p = Path('.github/workflows/validate.yml')
text = read(p)
old = '''          $required = @(
            'install.ps1',
            'Instalar-PROX2-AutoSwitch.ps1',
'''
new = '''          $required = @(
            'install.ps1',
            'Install.cmd',
            'Verify.cmd',
            'Uninstall.cmd',
            'Instalar-PROX2-AutoSwitch.ps1',
'''
text = replace_once(text, old, new, 'validate required wrappers')
write(p, text)

# ---------------------------------------------------------------------------
# 7) README: prioritize ZIP + double-click path, keep one-command alternative.
# ---------------------------------------------------------------------------
p = Path('README.md')
text = read(p)
quick_anchor = 'See it live on the [project page](https://ayerdi.github.io/PROX2-AutoSwitch/).\n'
quick = r'''

## Quick start

### Recommended: download the ZIP

1. Open the [latest release](https://github.com/Ayerdi/PROX2-AutoSwitch/releases/latest) and download `Audio-AutoSwitch.zip`.
2. Extract the ZIP to a normal folder.
3. Double-click **`Install.cmd`**.
4. Pick your headset and fallback output, then follow the ON → OFF → ON wizard.
5. When installation finishes, turn the headset off/on once to confirm the real switch.

`Install.cmd` is only a small launcher for the PowerShell installer; all installation logic remains in the reviewed `.ps1` files. The release also includes **`Verify.cmd`** and **`Uninstall.cmd`** for double-click diagnostics/removal.

### One-command install

If you prefer PowerShell, this bootstrap downloads the latest versioned release ZIP plus its SHA-256 checksum, verifies it, and then starts the same installer:

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/install.ps1 | iex"
```
'''
if '## Quick start' not in text:
    text = replace_once(text, quick_anchor, quick_anchor + quick, 'README quick start insertion')

old_install = r'''## Installation

**One click** (downloads the latest release ZIP and its SHA-256 checksum, verifies the ZIP before extracting, then runs the full installer):

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/install.ps1 | iex"
```

Or manually:

1. Extract the whole ZIP to a normal folder. Don't run the installer from inside the ZIP.
2. Open PowerShell in that folder.
3. If Windows blocked the downloaded scripts:

```powershell
Get-ChildItem . -Filter *.ps1 | Unblock-File
```

4. Run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\\Instalar-PROX2-AutoSwitch.ps1"
```

The installer will:
'''
new_install = r'''## Installation details

The recommended ZIP path is **extract → double-click `Install.cmd`**. If Windows has marked the downloaded scripts as blocked and the launcher cannot run them, open PowerShell in the extracted folder and run:

```powershell
Get-ChildItem . -Filter *.ps1 | Unblock-File
powershell.exe -ExecutionPolicy Bypass -File ".\\Instalar-PROX2-AutoSwitch.ps1"
```

The installer will:
'''
text = replace_once(text, old_install, new_install, 'README installation section')

text = text.replace(
    'ask you to turn the headset OFF and back ON — if Windows reflects `Active → Unplugged → Active`, it picks `WindowsEndpoint` mode automatically;',
    'ask you to turn the headset OFF and back ON — it polls Windows for up to 15 s / 15 s / 20 s instead of trusting one fast Bluetooth reading; if Windows reflects `Active → Unplugged → Active`, it picks `WindowsEndpoint` mode automatically; if the endpoint is recreated with a new Item ID during that cycle, the installer re-resolves it by `Device Name` + `Name` and keeps the newest ID;'
)

text = text.replace(
    '- `install.ps1` — one-click bootstrap: fetches the latest release ZIP and its `.sha256`, verifies the hash, then runs the installer.',
    '- `install.ps1` — one-command bootstrap: fetches the latest versioned release ZIP and its `.sha256`, verifies the hash, then runs the installer.\n- `Install.cmd` / `Verify.cmd` / `Uninstall.cmd` — tiny double-click launchers; the real logic remains in PowerShell.'
)
write(p, text)

# ---------------------------------------------------------------------------
# 8) CHANGELOG Unreleased notes.
# ---------------------------------------------------------------------------
p = Path('CHANGELOG.md')
text = read(p)
needle = '## [Unreleased]\n'
if needle not in text:
    raise SystemExit('CHANGELOG: Unreleased heading not found')
notes = '''## [Unreleased]\n\n### Added\n- Double-click `Install.cmd`, `Verify.cmd`, and `Uninstall.cmd` launchers for users who download the release ZIP.\n- Release packaging now also publishes a stable `Audio-AutoSwitch.zip` + SHA-256 alias in addition to the versioned archive.\n\n### Fixed\n- Clean installation now polls Bluetooth/Core Audio transitions for 15 s / 15 s / 20 s and refreshes a recreated headset Item ID by `Device Name` + `Name`, matching the hardened Reconfigure flow.\n- The verifier no longer reports G HUB as a failure for generic `WindowsEndpoint` installations.\n- The one-command bootstrap now uses English/generic Audio AutoSwitch wording.\n- Removed leftover one-shot documentation workflows/scripts from `.github/`.\n'''
if 'Double-click `Install.cmd`' not in text:
    text = text.replace(needle, notes, 1)
write(p, text)

# ---------------------------------------------------------------------------
# 9) Remove all old one-shot tooling now; workflow also removes itself later.
# ---------------------------------------------------------------------------
for path in list(Path('.github').glob('tmp_*')) + list(Path('.github/workflows').glob('tmp-*.yml')):
    if path.name in {'tmp_onboarding_hardening.py', 'tmp-onboarding-hardening.yml'}:
        continue
    if path.is_file():
        path.unlink()

print('Onboarding hardening applied.')

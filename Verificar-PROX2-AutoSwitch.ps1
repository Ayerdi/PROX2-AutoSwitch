#requires -Version 5.1
$ErrorActionPreference = "Continue"

$InstallDir   = Join-Path $env:LOCALAPPDATA "PROX2AutoSwitch"
$MainScript   = Join-Path $InstallDir "PROX2AutoSwitch.ps1"
$ConfigPath   = Join-Path $InstallDir "config.json"
$LogPath      = Join-Path $InstallDir "autoswitch.log"
$ShortcutPath = Join-Path ([Environment]::GetFolderPath("Startup")) "PRO X 2 AutoSwitch.lnk"

Write-Host ""
Write-Host "=== Audio AutoSwitch verification ===" -ForegroundColor Cyan
Write-Host ""

function Show-Test {
    param([string]$Label, [bool]$Ok, [string]$Detail)

    if ($Ok) {
        Write-Host "[OK]   $Label" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] $Label" -ForegroundColor Red
    }

    if ($Detail) {
        Write-Host "       $Detail" -ForegroundColor DarkGray
    }
}

Show-Test "Install directory" (Test-Path $InstallDir) $InstallDir
Show-Test "Runtime" (Test-Path $MainScript) $MainScript
Show-Test "Logic module (lib)" (Test-Path (Join-Path $InstallDir "lib\AutoSwitchCore.psm1")) (Join-Path $InstallDir "lib\AutoSwitchCore.psm1")
Show-Test "Configuration" (Test-Path $ConfigPath) $ConfigPath
Show-Test "Invisible autostart" (Test-Path $ShortcutPath) $ShortcutPath

# Module functions (Core Audio backend, detection mode and enhancements).
$ModulePath = Join-Path $InstallDir "lib\AutoSwitchCore.psm1"
if (Test-Path $ModulePath) {
    Import-Module $ModulePath -ErrorAction SilentlyContinue
}

$coreAudioOk = $false
$coreAudioDetail = 'Module unavailable'
if (Test-Path $ModulePath) {
    try {
        $render = @(Get-CoreAudioRenderDevices)
        $defaultId = Get-CoreAudioDefaultRenderDeviceId
        $coreAudioOk = ($render.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($defaultId))
        $coreAudioDetail = "$($render.Count) render endpoint(s); default=$defaultId"
    }
    catch {
        $coreAudioDetail = $_.Exception.Message
    }
}
Show-Test "Native Windows Core Audio" $coreAudioOk $coreAudioDetail

$escaped = [regex]::Escape($MainScript)
$process = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match $escaped } |
    Select-Object -First 1

$processDetail = "Not found"
if ($process) {
    $processDetail = "PID $($process.ProcessId)"
}
Show-Test "AutoSwitch process" ($null -ne $process) $processDetail

$cfg = $null
$mode = $null
if (Test-Path $ConfigPath) {
    try {
        $cfg = Get-Content -Raw $ConfigPath | ConvertFrom-Json
        $mode = Get-ConfigDetectionMode -Config $cfg
    }
    catch {}
}

# G HUB is a requirement only for the Logitech-specific detection path. A
# generic WindowsEndpoint installation must not show a scary false failure.
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
        if ($ghubPort) {
            $client.EndConnect($iar)
        }
        $client.Close()
    }
    catch {
        $ghubPort = $false
    }

    $ghubDetail = if ($ghubPort) { "Port reachable" } else { "Open Logitech G HUB" }
    Show-Test "G HUB localhost:$ghubPortToTest" $ghubPort $ghubDetail
}
elseif ($mode -eq 'WindowsEndpoint') {
    Write-Host "[SKIP] G HUB (not used in WindowsEndpoint mode)" -ForegroundColor DarkGray
}
elseif ($mode -eq 'SteelSeriesNova5') {
    Write-Host "[SKIP] G HUB (not used in SteelSeriesNova5 mode)" -ForegroundColor DarkGray
    # SteelSeries receiver presence over HID.
    $steelModule = Join-Path $InstallDir "lib\SteelSeriesNova5.psm1"
    if (Test-Path $steelModule) {
        try {
            Import-Module $steelModule -ErrorAction Stop
            if (Test-SteelSeriesNova5Receiver) {
                Show-Test "SteelSeries Nova 5/5X receiver" $true "HID receiver found"
            }
            else {
                Show-Test "SteelSeries Nova 5/5X receiver" $false "No compatible HID receiver found"
            }
        }
        catch {
            Show-Test "SteelSeries Nova 5/5X receiver" $false $_.Exception.Message
        }
    }
    else {
        Show-Test "SteelSeries Nova 5/5X receiver" $false "Module not installed"
    }
}
else {
    Show-Test "Detection mode" $false "Could not read a valid DetectionMode from config.json"
}

if (Test-Path $ConfigPath) {
    try {
        if (-not $cfg) {
            $cfg = Get-Content -Raw $ConfigPath | ConvertFrom-Json
        }

        Write-Host ""
        Write-Host "Configuration:" -ForegroundColor Yellow

        $mode = Get-ConfigDetectionMode -Config $cfg
        Write-Host "  Detection mode: $mode"

        if ($cfg.HeadsetName) { Write-Host "  Headset:        $($cfg.HeadsetName)" }
        if ($cfg.SpeakerName) { Write-Host "  Fallback:       $($cfg.SpeakerName)" }

        if ($mode -eq 'LogitechGHub' -and $cfg.GHubDisplayName) {
            Write-Host "  G HUB:          $($cfg.GHubDisplayName)"
        }

        # Current state of the headset endpoint (WindowsEndpoint only).
        if ($mode -eq 'WindowsEndpoint' -and $cfg.HeadsetId) {
            try {
                $rows = @(Get-CoreAudioRenderDevices)
                $row = $rows | Where-Object {
                    $id = Get-CsvColumn -Row $_ -Names @('Item ID')
                    $null -ne $id -and $id.Trim().ToLowerInvariant() -eq [string]$cfg.HeadsetId
                } | Select-Object -First 1
                if ($row) {
                    $st = Get-CsvColumn -Row $row -Names @('Device State', 'State')
                    Write-Host "  Headset state:  $st"
                }
                else {
                    Write-Host "  Headset state:  (endpoint not present)" -ForegroundColor DarkGray
                }
            }
            catch {
                Write-Host "  Headset state:  unreadable" -ForegroundColor DarkGray
            }
        }

        # Enhancements state (non-elevated read).
        if ($cfg.HeadsetId) {
            $fx = Get-EndpointFxState -DeviceId ([string]$cfg.HeadsetId)
            if ($null -eq $fx) {
                Write-Host "  Enhancements:   unreadable" -ForegroundColor DarkGray
            }
            elseif ($fx) {
                Write-Host "  Enhancements:   DISABLED" -ForegroundColor Green
            }
            else {
                Write-Host "  Enhancements:   enabled" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Warning "config.json could not be read: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Last log lines:" -ForegroundColor Yellow
if (Test-Path $LogPath) {
    Get-Content $LogPath -Tail 15
}
else {
    Write-Host "(log does not exist yet)" -ForegroundColor DarkGray
}

Write-Host ""

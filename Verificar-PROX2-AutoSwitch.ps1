#requires -Version 5.1
$ErrorActionPreference = "Continue"

$InstallDir   = Join-Path $env:LOCALAPPDATA "PROX2AutoSwitch"
$MainScript   = Join-Path $InstallDir "PROX2AutoSwitch.ps1"
$ConfigPath   = Join-Path $InstallDir "config.json"
$SvclPath     = Join-Path $InstallDir "svcl.exe"
$LogPath      = Join-Path $InstallDir "autoswitch.log"
$ShortcutPath = Join-Path ([Environment]::GetFolderPath("Startup")) "PRO X 2 AutoSwitch.lnk"

Write-Host ""
Write-Host "=== Verificacion PRO X 2 AutoSwitch ===" -ForegroundColor Cyan
Write-Host ""

function Show-Test {
    param([string]$Label, [bool]$Ok, [string]$Detail)

    if ($Ok) {
        Write-Host "[OK]   $Label" -ForegroundColor Green
    }
    else {
        Write-Host "[FALLO] $Label" -ForegroundColor Red
    }

    if ($Detail) {
        Write-Host "       $Detail" -ForegroundColor DarkGray
    }
}

Show-Test "Directorio de instalacion" (Test-Path $InstallDir) $InstallDir
Show-Test "Runtime" (Test-Path $MainScript) $MainScript
Show-Test "Modulo de logica (lib)" (Test-Path (Join-Path $InstallDir "lib\AutoSwitchCore.psm1")) (Join-Path $InstallDir "lib\AutoSwitchCore.psm1")
Show-Test "Configuracion" (Test-Path $ConfigPath) $ConfigPath
Show-Test "svcl.exe" (Test-Path $SvclPath) $SvclPath
Show-Test "Inicio automatico invisible" (Test-Path $ShortcutPath) $ShortcutPath

# Funciones del modulo (Get-ConfigDetectionMode, ConvertFrom-SvclCsv, Get-EndpointFxState).
$ModulePath = Join-Path $InstallDir "lib\AutoSwitchCore.psm1"
if (Test-Path $ModulePath) {
    Import-Module $ModulePath -ErrorAction SilentlyContinue
}

$escaped = [regex]::Escape($MainScript)
$process = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match $escaped } |
    Select-Object -First 1

$processDetail = "No encontrado"
if ($process) {
    $processDetail = "PID $($process.ProcessId)"
}
Show-Test "Proceso AutoSwitch" ($null -ne $process) $processDetail

$ghubPort = $false
$ghubPortToTest = 9010
if (Test-Path $ConfigPath) {
    try {
        $cfgPort = (Get-Content -Raw $ConfigPath | ConvertFrom-Json).GHubPort
        if ($cfgPort) { $ghubPortToTest = [int]$cfgPort }
    }
    catch {}
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

$ghubDetail = "Abre Logitech G HUB"
if ($ghubPort) {
    $ghubDetail = "Puerto accesible"
}
Show-Test "G HUB localhost:$ghubPortToTest" $ghubPort $ghubDetail

if (Test-Path $ConfigPath) {
    try {
        $cfg = Get-Content -Raw $ConfigPath | ConvertFrom-Json
        Write-Host ""
        Write-Host "Configuracion:" -ForegroundColor Yellow

        $mode = Get-ConfigDetectionMode -Config $cfg
        Write-Host "  Modo deteccion: $mode"

        if ($cfg.HeadsetName) { Write-Host "  Auriculares:   $($cfg.HeadsetName)" }
        if ($cfg.SpeakerName) { Write-Host "  Alternativa:   $($cfg.SpeakerName)" }

        if ($mode -eq 'LogitechGHub' -and $cfg.GHubDisplayName) {
            Write-Host "  G HUB:         $($cfg.GHubDisplayName)"
        }

        # Estado actual del endpoint del headset (solo WindowsEndpoint).
        if ($mode -eq 'WindowsEndpoint' -and $cfg.HeadsetId) {
            try {
                $csv = (& $SvclPath /scomma "" 2>&1 | Out-String).Trim()
                $rows = @(ConvertFrom-SvclCsv -Text $csv)
                $row = $rows | Where-Object {
                    $id = Get-CsvColumn -Row $_ -Names @('Item ID')
                    $null -ne $id -and $id.Trim().ToLowerInvariant() -eq [string]$cfg.HeadsetId
                } | Select-Object -First 1
                if ($row) {
                    $st = Get-CsvColumn -Row $row -Names @('Device State', 'State')
                    Write-Host "  Estado headset: $st"
                }
                else {
                    Write-Host "  Estado headset: (endpoint no presente)" -ForegroundColor DarkGray
                }
            }
            catch {
                Write-Host "  Estado headset: no legible" -ForegroundColor DarkGray
            }
        }

        # Estado de enhancements (lectura sin elevacion).
        if ($cfg.HeadsetId) {
            $fx = Get-EndpointFxState -DeviceId ([string]$cfg.HeadsetId)
            if ($null -eq $fx) {
                Write-Host "  Enhancements:   no legible" -ForegroundColor DarkGray
            }
            elseif ($fx) {
                Write-Host "  Enhancements:   DESHABILITADOS" -ForegroundColor Green
            }
            else {
                Write-Host "  Enhancements:   habilitados" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Warning "config.json no se pudo leer: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Ultimas lineas del log:" -ForegroundColor Yellow
if (Test-Path $LogPath) {
    Get-Content $LogPath -Tail 15
}
else {
    Write-Host "(todavia no existe log)" -ForegroundColor DarkGray
}

Write-Host ""

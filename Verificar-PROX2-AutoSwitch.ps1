#requires -Version 5.1
$ErrorActionPreference = 'Continue'

$InstallDir = Join-Path $env:LOCALAPPDATA 'PROX2AutoSwitch'
$MainScript = Join-Path $InstallDir 'PROX2AutoSwitch.ps1'
$ConfigPath = Join-Path $InstallDir 'config.json'
$SvclPath = Join-Path $InstallDir 'svcl.exe'
$LogPath = Join-Path $InstallDir 'autoswitch.log'
$CoreModule = Join-Path $InstallDir 'lib\AutoSwitchCore.psm1'
$SteelSeriesModule = Join-Path $InstallDir 'lib\SteelSeriesNova5.psm1'
$DefaultHeadsetControlPath = Join-Path $InstallDir 'headsetcontrol.exe'
$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'PRO X 2 AutoSwitch.lnk'

$script:Failed = $false
function Show-Test {
    param([string]$Label, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "[OK]   $Label" -ForegroundColor Green }
    else { Write-Host "[FAIL] $Label" -ForegroundColor Red; $script:Failed = $true }
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkGray }
}

Write-Host ''
Write-Host '=== Audio AutoSwitch verification ===' -ForegroundColor Cyan
Write-Host ''

Show-Test 'Install directory' (Test-Path -LiteralPath $InstallDir) $InstallDir
Show-Test 'Runtime' (Test-Path -LiteralPath $MainScript) $MainScript
Show-Test 'Logic module (lib)' (Test-Path -LiteralPath $CoreModule) $CoreModule
Show-Test 'SteelSeries provider module' (Test-Path -LiteralPath $SteelSeriesModule) $SteelSeriesModule
Show-Test 'Configuration' (Test-Path -LiteralPath $ConfigPath) $ConfigPath
Show-Test 'svcl.exe' (Test-Path -LiteralPath $SvclPath) $SvclPath
Show-Test 'Invisible autostart' (Test-Path -LiteralPath $ShortcutPath) $ShortcutPath

if (Test-Path -LiteralPath $CoreModule) {
    Import-Module $CoreModule -Force -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath $SteelSeriesModule) {
    Import-Module $SteelSeriesModule -Force -ErrorAction SilentlyContinue
}

$escaped = [regex]::Escape($MainScript)
$process = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match $escaped } |
    Select-Object -First 1
Show-Test 'AutoSwitch process' ($null -ne $process) $(if ($process) { "PID $($process.ProcessId)" } else { 'Not found' })

$cfg = $null
$mode = $null
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $cfg = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
        $mode = Get-ConfigDetectionMode -Config $cfg
    }
    catch { }
}
Show-Test 'Detection mode' ($mode -in @('WindowsEndpoint', 'LogitechGHub', 'SteelSeriesNova5')) $(if ($mode) { $mode } else { 'Invalid or unreadable config' })

$currentState = $null
if ($mode -eq 'WindowsEndpoint' -and $cfg.HeadsetId -and (Test-Path -LiteralPath $SvclPath)) {
    try {
        $csv = (& $SvclPath /scomma '' 2>&1 | Out-String).Trim()
        if (Test-SvclExportValid -CsvText $csv) {
            $rows = @(ConvertFrom-SvclCsv -Text $csv)
            $row = $rows | Where-Object {
                $id = Get-CsvColumn -Row $_ -Names @('Item ID')
                $null -ne $id -and $id.Trim().ToLowerInvariant() -eq ([string]$cfg.HeadsetId).Trim().ToLowerInvariant()
            } | Select-Object -First 1

            if ($row) {
                $rawState = Get-CsvColumn -Row $row -Names @('Device State', 'State')
                $currentState = Resolve-EndpointState -State $rawState
            }
            else {
                $currentState = 'Disconnected'
            }
        }
    }
    catch { }

    Show-Test 'Windows headset state' ($currentState -in @('Connected', 'Disconnected')) $(if ($currentState) { "State: $currentState" } else { 'Unreadable' })
}
elseif ($mode -eq 'LogitechGHub') {
    $port = 9010
    if ($cfg.PSObject.Properties['GHubPort'] -and $cfg.GHubPort) { $port = [int]$cfg.GHubPort }
    $reachable = $false
    try {
        $reachable = Test-NetConnection -ComputerName '127.0.0.1' -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
    }
    catch { $reachable = $false }
    Show-Test "G HUB localhost:$port" ([bool]$reachable) $(if ($reachable) { 'Port reachable' } else { 'Open Logitech G HUB' })
}
elseif ($mode -eq 'SteelSeriesNova5') {
    $hcPath = $DefaultHeadsetControlPath
    if ($cfg.PSObject.Properties['HeadsetControlPath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$cfg.HeadsetControlPath)) {
        $hcPath = [string]$cfg.HeadsetControlPath
    }
    Show-Test 'HeadsetControl provider' (Test-Path -LiteralPath $hcPath) $hcPath

    $steelSeriesPid = 0
    $pidOk = $false
    if ($cfg.PSObject.Properties['SteelSeriesProductId']) {
        try {
            $steelSeriesPid = [int]$cfg.SteelSeriesProductId
            $pidOk = $steelSeriesPid -in @(0x2232, 0x2253)
        }
        catch { }
    }
    Show-Test 'SteelSeries Nova 5/5X PID' $pidOk $(if ($pidOk) { '0x{0:X4}' -f $steelSeriesPid } else { 'Missing or unsupported PID' })

    if ((Test-Path -LiteralPath $hcPath) -and $pidOk -and
        (Get-Command Get-SteelSeriesNova5State -ErrorAction SilentlyContinue)) {
        try {
            $currentState = Get-SteelSeriesNova5State -HeadsetControlPath $hcPath -ProductId $steelSeriesPid
        }
        catch { $currentState = 'Unknown' }
        Show-Test 'SteelSeries physical state' ($currentState -in @('Connected', 'Disconnected')) "State: $currentState"
    }
}

if ($cfg) {
    Write-Host ''
    Write-Host 'Configuration:' -ForegroundColor Yellow
    Write-Host "  Detection mode: $mode"
    if ($cfg.HeadsetName) { Write-Host "  Headset:        $($cfg.HeadsetName)" }
    if ($cfg.SpeakerName) { Write-Host "  Fallback:       $($cfg.SpeakerName)" }
    if ($mode -eq 'LogitechGHub' -and $cfg.GHubDisplayName) { Write-Host "  G HUB:          $($cfg.GHubDisplayName)" }
    if ($mode -eq 'SteelSeriesNova5' -and $cfg.PSObject.Properties['SteelSeriesProductId']) {
        Write-Host ('  SteelSeries PID: 0x{0:X4}' -f ([int]$cfg.SteelSeriesProductId))
    }
    if ($currentState) { Write-Host "  Headset state:  $currentState" }

    if ($cfg.HeadsetId -and (Get-Command Get-EndpointFxState -ErrorAction SilentlyContinue)) {
        $fx = Get-EndpointFxState -DeviceId ([string]$cfg.HeadsetId)
        if ($null -eq $fx) { Write-Host '  Enhancements:   unreadable' -ForegroundColor DarkGray }
        elseif ($fx) { Write-Host '  Enhancements:   DISABLED' -ForegroundColor Green }
        else { Write-Host '  Enhancements:   enabled' -ForegroundColor Yellow }
    }
}

Write-Host ''
Write-Host 'Last log lines:' -ForegroundColor Yellow
if (Test-Path -LiteralPath $LogPath) { Get-Content -LiteralPath $LogPath -Tail 15 }
else { Write-Host '(log does not exist yet)' -ForegroundColor DarkGray }
Write-Host ''

if ($script:Failed) { exit 1 }
exit 0

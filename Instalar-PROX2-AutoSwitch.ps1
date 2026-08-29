#requires -Version 5.1
$ErrorActionPreference = "Stop"

$PackageDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir   = Join-Path $env:LOCALAPPDATA "PROX2AutoSwitch"
$RuntimeSrc   = Join-Path $PackageDir "Runtime-PROX2-AutoSwitch.ps1"
$UninstallSrc = Join-Path $PackageDir "Desinstalar-PROX2-AutoSwitch.ps1"
$VerifySrc    = Join-Path $PackageDir "Verificar-PROX2-AutoSwitch.ps1"
$ModuleSrc    = Join-Path $PackageDir "lib\AutoSwitchCore.psm1"
$GHubModuleSrc = Join-Path $PackageDir "lib\LogitechGHub.psm1"
$SteelModuleSrc = Join-Path $PackageDir "lib\SteelSeriesNova5.psm1"
$HelperSrc    = Join-Path $PackageDir "Toggle-AudioEnhancements.ps1"
$IconSrc      = Join-Path $PackageDir "assets\icon.ico"
$VersionSrc   = Join-Path $PackageDir "VERSION"

$MainScript   = Join-Path $InstallDir "PROX2AutoSwitch.ps1"
$ConfigPath   = Join-Path $InstallDir "config.json"
$LauncherVbs  = Join-Path $InstallDir "Iniciar-Oculto.vbs"
$LogPath      = Join-Path $InstallDir "autoswitch.log"
$HelperPath   = Join-Path $InstallDir "Toggle-AudioEnhancements.ps1"

$StartupDir   = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "PRO X 2 AutoSwitch.lnk"

foreach ($required in @($RuntimeSrc, $UninstallSrc, $VerifySrc, $ModuleSrc, $GHubModuleSrc, $SteelModuleSrc, $HelperSrc, $IconSrc, $VersionSrc)) {
    if (-not (Test-Path $required)) {
        throw "A package file is missing: $required. Extract the full ZIP before installing."
    }
}

# Shared logic and provider modules.
Import-Module $ModuleSrc -ErrorAction Stop
Import-Module $GHubModuleSrc -ErrorAction Stop

$PackageVersion = (Get-Content -Raw -Path $VersionSrc).Trim()
if ($PackageVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "VERSION is invalid: '$PackageVersion'."
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw "This package is built for Windows x64."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Audio AutoSwitch" -ForegroundColor Cyan
Write-Host " Clean installation" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Stop a previous installation, if any.
$escapedMain = [regex]::Escape($MainScript)
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -match $escapedMain
    } |
    ForEach-Object {
        Write-Host "Stopping previous instance (PID $($_.ProcessId))..." -ForegroundColor DarkGray
        Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null
    }

Start-Sleep -Milliseconds 500

# Native Core Audio backend: no third-party audio executable is downloaded.
Write-Host "[1/6] Checking native Windows Core Audio..." -ForegroundColor Yellow
try {
    $nativeDevices = @(Get-CoreAudioRenderDevices)
    if ($nativeDevices.Count -eq 0) {
        throw "Windows returned no render endpoints."
    }
    [void](Get-CoreAudioDefaultRenderDeviceId)
}
catch {
    throw "Native Windows Core Audio is unavailable: $($_.Exception.Message)"
}
Write-Host "      Core Audio OK ($($nativeDevices.Count) render endpoint(s))." -ForegroundColor Green

# Remove a stale dependency left by installations older than the native backend.
$legacySvclPath = Join-Path $InstallDir "svcl.exe"
if (Test-Path $legacySvclPath) {
    Remove-Item $legacySvclPath -Force -ErrorAction SilentlyContinue
}

# Copy the source version of the runtime and utilities.
Copy-Item $RuntimeSrc $MainScript -Force
Copy-Item $UninstallSrc (Join-Path $InstallDir "Desinstalar-PROX2-AutoSwitch.ps1") -Force
Copy-Item $VerifySrc (Join-Path $InstallDir "Verificar-PROX2-AutoSwitch.ps1") -Force
Copy-Item $HelperSrc (Join-Path $InstallDir "Toggle-AudioEnhancements.ps1") -Force
Copy-Item $IconSrc (Join-Path $InstallDir "icon.ico") -Force
New-Item -ItemType Directory -Path (Join-Path $InstallDir "lib") -Force | Out-Null
Copy-Item $ModuleSrc (Join-Path $InstallDir "lib\AutoSwitchCore.psm1") -Force
Copy-Item $GHubModuleSrc (Join-Path $InstallDir "lib\LogitechGHub.psm1") -Force
Copy-Item $SteelModuleSrc (Join-Path $InstallDir "lib\SteelSeriesNova5.psm1") -Force

function Get-DefaultRenderItemId {
    return Get-CoreAudioDefaultRenderDeviceId
}

function Test-SetDefault {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Label
    )

    Write-Host ""
    Write-Host "Testing real switch -> $Label" -ForegroundColor Yellow

    try {
        Set-CoreAudioDefaultRenderDevice -DeviceId $Id
    }
    catch {
        Write-Host ("      TEST FAILED. Core Audio error: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }

    Start-Sleep -Milliseconds 800
    if (Test-CoreAudioDefaultRenderDevice -DeviceId $Id) {
        Write-Host "      TEST OK (Console/Multimedia/Communications)" -ForegroundColor Green
        return $true
    }

    $actual = $null
    try { $actual = Get-CoreAudioDefaultRenderDeviceIds } catch { }
    Write-Host ("      TEST FAILED. Actual roles: {0}" -f ($actual | ConvertTo-Json -Compress)) -ForegroundColor Red
    return $false
}

function Select-InstallerLogitechHeadset {
    <#
    .SYNOPSIS
        Return a compatible G HUB headset, asking only when more than one exists.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WindowsHeadsetName)

    Open-LogitechGHubConnection
    $candidates = @(Get-LogitechGHubHeadsets)

    if ($candidates.Count -eq 0) {
        return $null
    }
    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    Write-Host "Logitech headsets detected by G HUB:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $candidates[$i].extendedDisplayName, $candidates[$i].id)
    }

    $ghubChoice = 0
    do {
        $gc = Read-Host "Enter the number of the Logitech headset that matches '$WindowsHeadsetName'"
        $valid = [int]::TryParse($gc, [ref]$ghubChoice) -and
                 $ghubChoice -ge 1 -and
                 $ghubChoice -le $candidates.Count
    } until ($valid)

    return $candidates[$ghubChoice - 1]
}

try {
    $DetectionMode = $null
    $ghubHeadset = $null

    Write-Host "[2/6] Selecting headset and fallback..." -ForegroundColor Yellow

    try {
        $renderRows = @(Get-CoreAudioRenderDevices)
    }
    catch {
        throw "Could not read the Windows audio device list through Core Audio: $($_.Exception.Message)"
    }
    if ($renderRows.Count -eq 0) {
        throw "No render (output) devices found in the Windows list."
    }

    $activeRows = @($renderRows | Where-Object {
        (Get-DeviceColumn -Row $_ -Names @('Device State')) -ieq 'Active'
    })
    $pickable = if ($activeRows.Count -gt 0) { $activeRows } else { $renderRows }

    Write-Host ""
    Write-Host "Detected output devices:" -ForegroundColor Yellow
    if ($activeRows.Count -eq 0) {
        Write-Host "  (no Active endpoints found; showing all states)" -ForegroundColor DarkGray
    }
    for ($i = 0; $i -lt $pickable.Count; $i++) {
        $label = Get-DeviceLabel -Row $pickable[$i]
        $state = Get-DeviceColumn -Row $pickable[$i] -Names @('Device State')
        Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $label, $state)
    }

    $chosenHeadset = $null
    do {
        $choice = Read-Host "Enter the number of the HEADSET"
        $parsed = 0
        $valid = [int]::TryParse($choice, [ref]$parsed) -and
                 $parsed -ge 1 -and
                 $parsed -le $pickable.Count
    } until ($valid)
    $chosenHeadset = $pickable[$parsed - 1]

    $chosenSpeaker = $null
    do {
        $choice = Read-Host "Enter the number of the FALLBACK device (speakers)"
        $parsed = 0
        $valid = [int]::TryParse($choice, [ref]$parsed) -and
                 $parsed -ge 1 -and
                 $parsed -le $pickable.Count
    } until ($valid)
    $chosenSpeaker = $pickable[$parsed - 1]

    $headsetId           = Get-DeviceColumn -Row $chosenHeadset -Names @('Item ID')
    $speakerId           = Get-DeviceColumn -Row $chosenSpeaker -Names @('Item ID')
    $headsetName         = Get-DeviceLabel -Row $chosenHeadset
    $speakerName         = Get-DeviceLabel -Row $chosenSpeaker
    $headsetDeviceName   = Get-DeviceColumn -Row $chosenHeadset -Names @('Device Name')
    $headsetEndpointName = Get-DeviceColumn -Row $chosenHeadset -Names @('Name')

    if (-not (Test-ValidAudioConfig -HeadsetId $headsetId -SpeakerId $speakerId)) {
        throw "You chose the same device for headset and fallback. Run the installer again."
    }

    Write-Host "      Headset:  $headsetName" -ForegroundColor Green
    Write-Host "      Fallback: $speakerName" -ForegroundColor Green

    Write-Host ""
    Write-Host "Which kind of headset is this?" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Standard wireless headset (Bluetooth/USB, e.g. Jabra)" -ForegroundColor White
    Write-Host "      -> Use WindowsEndpoint: Windows detects the endpoint as" -ForegroundColor DarkGray
    Write-Host "         Active when ON and Unplugged/absent when OFF." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [2] Any Logitech headset (G HUB)" -ForegroundColor White
    Write-Host "      -> Use LogitechGHub: Windows keeps the endpoint Active even" -ForegroundColor DarkGray
    Write-Host "         when OFF, so detection uses the G HUB battery signal." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [3] Not sure - validate automatically" -ForegroundColor White
    Write-Host "      -> Run the ON->OFF->ON cycle and auto-detect the mode" -ForegroundColor DarkGray
    Write-Host "         (recommended if this is a new headset)." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [4] SteelSeries Arctis Nova 5/5X" -ForegroundColor White
    Write-Host "      -> Use SteelSeriesNova5: reads the headset state over HID" -ForegroundColor DarkGray
    Write-Host "         (no SteelSeries GG or third-party software needed)." -ForegroundColor DarkGray
    $cycleChoice = 0
    do {
        $cc = Read-Host "Choose 1, 2, 3 or 4"
        [int]::TryParse($cc, [ref]$cycleChoice) | Out-Null
    } until ($cycleChoice -ge 1 -and $cycleChoice -le 4)

    if ($cycleChoice -eq 1) {
        $DetectionMode = "WindowsEndpoint"
        Write-Host "      Using WindowsEndpoint mode with the selected endpoints." -ForegroundColor Green
    }
    elseif ($cycleChoice -eq 2) {
        Write-Host "      Assuming a Logitech headset. Looking it up in G HUB..." -ForegroundColor Yellow
        try {
            $ghubHeadset = Select-InstallerLogitechHeadset -WindowsHeadsetName $headsetName
            if ($ghubHeadset) {
                $DetectionMode = "LogitechGHub"
                Write-Host "      G HUB: $($ghubHeadset.extendedDisplayName)" -ForegroundColor Green
            }
            else {
                Write-Host "      G HUB reports no compatible Logitech headset. Try option 3 (auto-detect)." -ForegroundColor Red
            }
        }
        catch {
            Write-Host "      Could not connect to G HUB. Detail: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            Close-LogitechGHubConnection
        }

        if (-not $DetectionMode) {
            Write-Host "      No G HUB association was set; the config will not be written." -ForegroundColor DarkGray
        }
    }
    elseif ($cycleChoice -eq 4) {
        $steelModule = Join-Path $InstallDir "lib\SteelSeriesNova5.psm1"
        if (-not (Test-Path $steelModule)) {
            Write-Host "      SteelSeries module not present in the package; cannot use this mode." -ForegroundColor Red
        }
        else {
            try {
                Import-Module $steelModule -ErrorAction Stop
                if (Test-SteelSeriesNova5Receiver) {
                    $DetectionMode = "SteelSeriesNova5"
                    Write-Host "      SteelSeries Nova 5/5X receiver detected over HID." -ForegroundColor Green
                }
                else {
                    Write-Host "      No compatible SteelSeries Nova 5/5X receiver found." -ForegroundColor Red
                }
            }
            catch {
                Write-Host "      SteelSeries check failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host ""
        Write-Host "Checking that Windows reflects the physical state of the headset..." -ForegroundColor Cyan
        Write-Host "      The headset must be ON now. Checking..." -ForegroundColor DarkGray

        function Get-HeadsetInstallState {
            param(
                [Parameter(Mandatory = $true)][string]$ItemId,
                [string]$DeviceName,
                [string]$EndpointName
            )

            try {
                $rows = @(Get-CoreAudioRenderDevices)
            }
            catch {
                return [pscustomobject]@{ State = 'Unknown'; FoundId = $null }
            }
            $row = $rows | Where-Object {
                $id = Get-DeviceColumn -Row $_ -Names @('Item ID')
                $null -ne $id -and $id.Trim() -ieq $ItemId.Trim()
            } | Select-Object -First 1

            if (-not $row -and
                (-not [string]::IsNullOrWhiteSpace($DeviceName) -or
                 -not [string]::IsNullOrWhiteSpace($EndpointName))) {
                $row = Find-RenderDeviceByIdentity -Rows $rows -DeviceName $DeviceName -Name $EndpointName
            }

            if (-not $row) {
                return [pscustomobject]@{ State = 'Disconnected'; FoundId = $null }
            }

            $state = Get-DeviceColumn -Row $row -Names @('Device State', 'State')
            $foundId = Get-DeviceColumn -Row $row -Names @('Item ID')
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

        if ($sOn1 -eq 'Connected' -and $sOff -eq 'Disconnected' -and $sOn2 -eq 'Connected') {
            $DetectionMode = "WindowsEndpoint"
            Write-Host "      Windows reflects the ON->OFF->ON cycle: universal mode." -ForegroundColor Green
        }
        else {
            Write-Host "      Windows does NOT reflect the physical cycle of this headset." -ForegroundColor DarkGray
            Write-Host ""
            $conf = Read-Host "Is this headset a Logitech headset detected by G HUB? (y/N)"
            if ($conf -match '^(s|si|sí|y|yes)$') {
                try {
                    $ghubHeadset = Select-InstallerLogitechHeadset -WindowsHeadsetName $headsetName
                    if ($ghubHeadset) {
                        $DetectionMode = "LogitechGHub"
                        Write-Host "      G HUB: $($ghubHeadset.extendedDisplayName)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "      G HUB reports no compatible Logitech headset." -ForegroundColor Red
                    }
                }
                catch {
                    Write-Host "      Could not connect to G HUB. Detail: $($_.Exception.Message)" -ForegroundColor Red
                }
                finally {
                    Close-LogitechGHubConnection
                }
            }
        }
    }

    if (-not $DetectionMode) {
        throw "Windows cannot detect the physical state of this headset and there is no compatible method (nor a confirmed G HUB). Not installing."
    }

    Write-Host ""
    Write-Host "[3/6] Calibrating Windows outputs..." -ForegroundColor Yellow
    Write-Host "No old IDs are kept: the current Windows ones are captured." -ForegroundColor DarkGray

    $headsetOutput = [pscustomobject]@{
        Name   = $headsetName
        ItemId = $headsetId
    }
    $speakerOutput = [pscustomobject]@{
        Name   = $speakerName
        ItemId = $speakerId
    }

    Write-Host ""
    Write-Host "[4/6] Validating audio switches before installing..." -ForegroundColor Yellow

    $okHeadset = Test-SetDefault `
        -Id $headsetOutput.ItemId `
        -Label $headsetOutput.Name

    $okSpeaker = Test-SetDefault `
        -Id $speakerOutput.ItemId `
        -Label $speakerOutput.Name

    if (-not ($okHeadset -and $okSpeaker)) {
        throw "One of the real audio switch tests failed. AutoSwitch will not be installed."
    }

    $config = [ordered]@{
        Version                = $PackageVersion
        DetectionMode          = $DetectionMode
        HeadsetName            = [string]$headsetOutput.Name
        HeadsetId              = [string]$headsetOutput.ItemId
        SpeakerName            = [string]$speakerOutput.Name
        SpeakerId              = [string]$speakerOutput.ItemId
        PollMilliseconds       = 1500
        OffMissThreshold       = 2
        ConnectTimeoutMs       = 5000
        ReceiveTimeoutMs       = 5000
        RequestTimeoutMs       = 10000
        DisableEnhancementsOnStart = $false
        InstalledAt            = (Get-Date).ToString("o")
    }

    if ($DetectionMode -eq 'LogitechGHub' -and $ghubHeadset) {
        $config['GHubDisplayName'] = [string]$ghubHeadset.extendedDisplayName
        $config['GHubPort']        = 9010
    }

    Write-Host ""
    Write-Host "Windows Audio Enhancements:" -ForegroundColor Yellow
    $enhChoice = Read-Host "Do you want to disable the headset's audio enhancements? (y/N)"
    if ($enhChoice -match '^(s|si|sí|y|yes)$') {
        $config['EnhancementsDeviceId'] = [string]$headsetOutput.ItemId
        $config['DisableEnhancementsOnStart'] = $true
        Write-Host "      They will be disabled (a UAC window may appear)..." -ForegroundColor DarkGray
    }

    Write-AutoSwitchJsonAtomically -InputObject $config -Path $ConfigPath

    if ($config['DisableEnhancementsOnStart']) {
        try {
            $proc = Start-Process -FilePath (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$HelperPath`" -DeviceId `"$($config['HeadsetId'])`" -Action Disable" `
                -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
            $proc.WaitForExit()
            if ($proc.ExitCode -eq 0) {
                Write-Host "      Enhancements disabled and verified." -ForegroundColor Green
            }
            else {
                Write-Warning "The enhancements helper did not confirm the change (exit code $($proc.ExitCode))."
            }
        }
        catch {
            Write-Warning "Could not disable enhancements now (UAC canceled or error): $($_.Exception.Message)"
            Write-Host "      You can do it later from the tray icon." -ForegroundColor DarkGray
        }
    }

    Write-Host "[5/6] Setting up invisible startup..." -ForegroundColor Yellow

    $PowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $WScriptExe    = Join-Path $env:SystemRoot "System32\wscript.exe"

    if (-not (Test-Path $WScriptExe)) {
        throw "wscript.exe was not found. This installer uses WScript to avoid a PowerShell window at login."
    }

    $vbs = @"
Set shell = CreateObject("WScript.Shell")
cmd = Chr(34) & "$PowerShellExe" & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & "$MainScript" & Chr(34)
shell.Run cmd, 0, False
Set shell = Nothing
"@

    Set-Content -Path $LauncherVbs -Value $vbs -Encoding ASCII

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $WScriptExe
    $Shortcut.Arguments = "`"$LauncherVbs`""
    $Shortcut.WorkingDirectory = $InstallDir
    $Shortcut.IconLocation = "$env:SystemRoot\System32\SndVol.exe,0"
    $Shortcut.Description = "Audio AutoSwitch - invisible startup"
    $Shortcut.Save()

    Start-Process -FilePath $WScriptExe -ArgumentList "`"$LauncherVbs`"" -WindowStyle Hidden
    Start-Sleep -Seconds 2

    $running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match $escapedMain } |
        Select-Object -First 1

    Write-Host "[6/6] Finalizing..." -ForegroundColor Yellow
    Write-Host ""

    if ($running) {
        Write-Host "INSTALLATION COMPLETED." -ForegroundColor Green
        Write-Host "AutoSwitch running in the background (PID $($running.ProcessId))." -ForegroundColor Green
    }
    else {
        Write-Warning "The installation finished, but I could not confirm the hidden process."
        Write-Host "Run the included verifier."
    }

    Write-Host ""
    Write-Host "Headset ON  -> $($headsetOutput.Name)"
    Write-Host "Headset OFF -> $($speakerOutput.Name)"
    Write-Host ""
    Write-Host "Installed at: $InstallDir" -ForegroundColor DarkGray
    Write-Host "Log:          $LogPath" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Now try turning the headset on and off." -ForegroundColor Cyan
}
finally {
    Close-LogitechGHubConnection
}

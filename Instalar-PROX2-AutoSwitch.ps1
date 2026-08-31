#requires -Version 5.1
$ErrorActionPreference = "Stop"

$PackageDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir   = Join-Path $env:LOCALAPPDATA "PROX2AutoSwitch"
$RuntimeSrc   = Join-Path $PackageDir "Runtime-PROX2-AutoSwitch.ps1"
$UninstallSrc = Join-Path $PackageDir "Desinstalar-PROX2-AutoSwitch.ps1"
$VerifySrc    = Join-Path $PackageDir "Verificar-PROX2-AutoSwitch.ps1"
$ModuleSrc    = Join-Path $PackageDir "lib\AutoSwitchCore.psm1"
$SteelModuleSrc = Join-Path $PackageDir "lib\SteelSeriesNova5.psm1"
$CenturionModuleSrc = Join-Path $PackageDir "lib\LogitechProX2Centurion.psm1"
$HelperSrc    = Join-Path $PackageDir "Toggle-AudioEnhancements.ps1"
$IconSrc      = Join-Path $PackageDir "assets\icon.ico"

$MainScript   = Join-Path $InstallDir "PROX2AutoSwitch.ps1"
$ConfigPath   = Join-Path $InstallDir "config.json"
$LauncherVbs  = Join-Path $InstallDir "Iniciar-Oculto.vbs"
$LogPath      = Join-Path $InstallDir "autoswitch.log"
$HelperPath   = Join-Path $InstallDir "Toggle-AudioEnhancements.ps1"

$StartupDir   = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "PRO X 2 AutoSwitch.lnk"


foreach ($required in @($RuntimeSrc, $UninstallSrc, $VerifySrc, $ModuleSrc, $SteelModuleSrc, $CenturionModuleSrc, $HelperSrc, $IconSrc)) {
    if (-not (Test-Path $required)) {
        throw "A package file is missing: $required. Extract the full ZIP before installing."
    }
}

# Shared logic (Item ID extraction, config validation, debounce).
Import-Module $ModuleSrc -ErrorAction Stop
Import-Module $CenturionModuleSrc -ErrorAction Stop

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
Copy-Item $SteelModuleSrc (Join-Path $InstallDir "lib\SteelSeriesNova5.psm1") -Force
Copy-Item $CenturionModuleSrc (Join-Path $InstallDir "lib\LogitechProX2Centurion.psm1") -Force

# --- G HUB functions for the installer ---
$script:Ws  = $null

# G HUB timeouts (ms): the assistant's G HUB check must not hang if G HUB
# accepts the connection and then stops responding.
$script:ConnectTimeoutMs = 5000
$script:ReceiveTimeoutMs = 5000
$script:RequestTimeoutMs = 10000

# G HUB timeout token: defined in lib\AutoSwitchCore.psm1 (imported above).

function Close-GHubConnection {
    # Closing must not hang the assistant: if CloseAsync does not finish in
    # 1 s (or fails), Abort() + Dispose() guarantee exit.
    if ($null -ne $script:Ws -and
        $script:Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $closeCts = New-Object System.Threading.CancellationTokenSource
        $closeCts.CancelAfter(1000)
        try {
            $script:Ws.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "fin",
                $closeCts.Token
            ).GetAwaiter().GetResult() | Out-Null
        }
        catch {
            try { $script:Ws.Abort() } catch {}
        }
        finally {
            $closeCts.Dispose()
        }
    }

    try { if ($null -ne $script:Ws)  { $script:Ws.Dispose() } } catch {}

    $script:Ws  = $null
}

function Connect-GHub {
    Close-GHubConnection

    $script:Ws  = New-Object System.Net.WebSockets.ClientWebSocket

    $script:Ws.Options.UseDefaultCredentials = $false
    $script:Ws.Options.SetRequestHeader("Origin", "file://")
    $script:Ws.Options.SetRequestHeader("Pragma", "no-cache")
    $script:Ws.Options.SetRequestHeader("Cache-Control", "no-cache")
    $script:Ws.Options.SetRequestHeader(
        "Sec-WebSocket-Extensions",
        "permessage-deflate; client_max_window_bits"
    )
    $script:Ws.Options.SetRequestHeader("Sec-WebSocket-Protocol", "json")
    $script:Ws.Options.AddSubProtocol("json")

    $uri = New-Object System.Uri("ws://localhost:9010")

    $timeout = New-GHubTimeoutToken -Milliseconds $script:ConnectTimeoutMs
    try {
        $script:Ws.ConnectAsync($uri, $timeout.Token).GetAwaiter().GetResult() | Out-Null
    }
    catch [System.OperationCanceledException] {
        throw "Timeout connecting to G HUB ($($script:ConnectTimeoutMs) ms)."
    }
    finally {
        $timeout.Dispose()
    }

    if ($script:Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "Could not open ws://localhost:9010."
    }
}

function Send-GHubJson {
    param([Parameter(Mandatory=$true)][object]$Object)

    $json = $Object | ConvertTo-Json -Compress -Depth 20
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (,$bytes)

    $timeout = New-GHubTimeoutToken -Milliseconds $script:ReceiveTimeoutMs
    try {
        $script:Ws.SendAsync(
            $segment,
            [System.Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            $timeout.Token
        ).GetAwaiter().GetResult() | Out-Null
    }
    catch [System.OperationCanceledException] {
        throw "Timeout sending request to G HUB ($($script:ReceiveTimeoutMs) ms)."
    }
    finally {
        $timeout.Dispose()
    }
}

function Receive-GHubText {
    param(
        # Hard deadline for the request: no fragment may cross this point.
        [Parameter(Mandatory=$true)][datetime]$Deadline
    )

    $buffer = New-Object byte[] 16384
    $stream = New-Object System.IO.MemoryStream

    try {
        do {
            $remainingMs = [int](($Deadline - (Get-Date)).TotalMilliseconds)
            if ($remainingMs -le 0) {
                throw "G HUB request timeout ($($script:RequestTimeoutMs) ms)."
            }
            # Each fragment waits at most ReceiveTimeoutMs, never past the
            # global request deadline.
            $fragmentMs = [Math]::Min($script:ReceiveTimeoutMs, $remainingMs)

            $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (,$buffer)

            $timeout = New-GHubTimeoutToken -Milliseconds $fragmentMs
            try {
                $result = $script:Ws.ReceiveAsync(
                    $segment,
                    $timeout.Token
                ).GetAwaiter().GetResult()
            }
            catch [System.OperationCanceledException] {
                throw "Timeout waiting for a G HUB response ($($fragmentMs) ms)."
            }
            finally {
                $timeout.Dispose()
            }

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw "G HUB closed the WebSocket."
            }

            if ($result.Count -gt 0) {
                $stream.Write($buffer, 0, $result.Count)
            }
        } while (-not $result.EndOfMessage)

        return [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-GHubGet {
    param([Parameter(Mandatory=$true)][string]$Path)

    $msgId = [guid]::NewGuid().ToString()

    Send-GHubJson @{
        msgId = $msgId
        verb  = "GET"
        path  = $Path
    }

    # Global per-request limit: even if G HUB interleaves events, the expected
    # response must arrive before the deadline.
    $deadline = (Get-Date).AddMilliseconds($script:RequestTimeoutMs)

    while ($true) {
        if ((Get-Date) -gt $deadline) {
            throw "G HUB request timeout ($($script:RequestTimeoutMs) ms): $Path"
        }

        $raw = Receive-GHubText -Deadline $deadline
        try { $message = $raw | ConvertFrom-Json } catch { continue }

        if (($message.msgId -eq $msgId) -or ($message.path -eq $Path)) {
            return $message
        }
    }
}

# --- Audio functions ---
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

try {
    # --- Step 3: pick headset and fallback FIRST ---
    # DetectionMode is not decided until the device has been chosen and we
    # have validated that Windows (or G HUB) can observe its physical state.
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

    # Show only Active endpoints (usable right now). If there is none,
    # show all with a notice so the install is not blocked.
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

    # --- Atajo: como usar el headset elegido ---
    # El ciclo ON -> OFF -> ON confirma que Windows refleja el estado fisico
    # (needed to detect ON/OFF at runtime). But if the user already
    # knows the chosen endpoints are correct (e.g. tested before),
    # they can skip the cycle and use WindowsEndpoint directly.
    Write-Host ""
    Write-Host "Which kind of headset is this?" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Standard wireless headset (Bluetooth/USB, e.g. Jabra)" -ForegroundColor White
    Write-Host "      -> Use WindowsEndpoint: Windows detects the endpoint as" -ForegroundColor DarkGray
    Write-Host "         Active when ON and Unplugged/absent when OFF." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [2] Logitech headset (PRO X 2 direct HID; others via G HUB)" -ForegroundColor White
    Write-Host "      -> PRO X 2 reads its LIGHTSPEED receiver directly (Centurion HID)." -ForegroundColor DarkGray
    Write-Host "         Other compatible Logitech headsets keep the G HUB provider." -ForegroundColor DarkGray
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
        # Standard wireless headset: assume WindowsEndpoint. The selected endpoints
        # are already Active render endpoints, so the runtime will watch their
        # Active/Unplugged state. No cycle needed.
        $DetectionMode = "WindowsEndpoint"
        Write-Host "      Using WindowsEndpoint mode with the selected endpoints." -ForegroundColor Green
    }
    elseif ($cycleChoice -eq 2) {
        $centurionMatched = $false
        if ($headsetName -match '(?i)PRO\s*X\s*2') {
            try {
                $centurion = Get-LogitechProX2CenturionState
                if ($centurion.State -eq 'Connected' -or $centurion.State -eq 'Disconnected') {
                    $DetectionMode = "LogitechGHub"
                    $ghubHeadset = [pscustomobject]@{ extendedDisplayName = $headsetName; id = "centurion-direct" }
                    $centurionMatched = $true
                    $batteryDetail = if ([int]$centurion.BatteryPercent -ge 0) { " battery=$([int]$centurion.BatteryPercent)%" } else { "" }
                    Write-Host "      PRO X 2 direct Centurion HID detected.$batteryDetail" -ForegroundColor Green
                }
            }
            catch { Write-Host ("      Direct PRO X 2 HID check failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkGray }
        }

        if (-not $centurionMatched) {
            Write-Host "      Looking up the Logitech headset in G HUB..." -ForegroundColor Yellow
            try {
                Connect-GHub
                $devices = Invoke-GHubGet -Path "/devices/list"
                $ghubCandidates = @($devices.payload.deviceInfos | Where-Object { Test-LogitechHeadsetDevice -Device $_ })
                if ($ghubCandidates.Count -eq 0) {
                    Write-Host "      G HUB reports no compatible Logitech headset. Try option 3." -ForegroundColor Red
                }
                else {
                    $ghubHeadset = $ghubCandidates[0]
                    if ($ghubCandidates.Count -gt 1) {
                        Write-Host "Logitech headsets detected by G HUB:" -ForegroundColor Yellow
                        for ($i = 0; $i -lt $ghubCandidates.Count; $i++) {
                            Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $ghubCandidates[$i].extendedDisplayName, $ghubCandidates[$i].id)
                        }
                        $ghubChoice = 0
                        do {
                            $gc = Read-Host "Enter the number of the Logitech headset that matches '$headsetName'"
                            $ghubValid = [int]::TryParse($gc, [ref]$ghubChoice) -and $ghubChoice -ge 1 -and $ghubChoice -le $ghubCandidates.Count
                        } until ($ghubValid)
                        $ghubHeadset = $ghubCandidates[$ghubChoice - 1]
                    }
                    $DetectionMode = "LogitechGHub"
                    Write-Host "      G HUB: $($ghubHeadset.extendedDisplayName)" -ForegroundColor Green
                }
            }
            catch { Write-Host ("      Could not connect to G HUB. Detail: {0}" -f $_.Exception.Message) -ForegroundColor Red }
            finally { Close-GHubConnection }
        }
    }
    elseif ($cycleChoice -eq 4) {
        # SteelSeries Arctis Nova 5/5X: HID receiver detection via the module.
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
    # --- Validate the headset ON -> OFF -> ON cycle ---
    # The headset must be ON now. We ask for OFF and then ON, and check that
    # Windows reflects the change on each transition.
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

        # Bluetooth can recreate an endpoint with a new Item ID after reconnect.
        # Resolve the same Render endpoint by its native Core Audio identity rather than
        # treating the user-facing "Device Name — Name" label as one column.
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

        # G HUB fallback: ONLY if the user confirms that the chosen headset is
        # a Logitech headset listed by G HUB. Never associate $logi[0].
        Write-Host ""
        $conf = Read-Host "Is this headset a Logitech headset detected by G HUB? (y/N)"
        if ($conf -match '^(s|si|sí|y|yes)$') {
            try {
                Connect-GHub
                $devices = Invoke-GHubGet -Path "/devices/list"
                $deviceInfos = @($devices.payload.deviceInfos)

                Write-Host ""
                # Filter to ONLY Logitech headset candidates: prevents accidentally
                # picking a Logitech mouse/keyboard and watching its battery.
                $ghubCandidates = @($deviceInfos | Where-Object {
                    Test-LogitechHeadsetDevice -Device $_
                })

                if ($ghubCandidates.Count -eq 0) {
                    Write-Host "      G HUB reports no Logitech headset." -ForegroundColor Red
                }
                else {
                    Write-Host "Logitech headsets detected by G HUB:" -ForegroundColor Yellow
                    for ($i = 0; $i -lt $ghubCandidates.Count; $i++) {
                        Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $ghubCandidates[$i].extendedDisplayName, $ghubCandidates[$i].id)
                    }

                    $ghubChoice = 0
                    do {
                        $gc = Read-Host "Enter the number of the Logitech headset that matches '$headsetName'"
                        $ghubValid = [int]::TryParse($gc, [ref]$ghubChoice) -and
                                     $ghubChoice -ge 1 -and
                                     $ghubChoice -le $ghubCandidates.Count
                    } until ($ghubValid)

                    $ghubHeadset = $ghubCandidates[$ghubChoice - 1]
                    $DetectionMode = "LogitechGHub"
                    Write-Host "      G HUB: $($ghubHeadset.extendedDisplayName)" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "      Could not connect to G HUB. Detail: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    }  # end of the shortcut cycle (ON->OFF->ON) else block

    if (-not $DetectionMode) {
        throw "Windows cannot detect the physical state of this headset and there is no compatible method (nor a confirmed G HUB). Not installing."
    }

    Write-Host ""
    Write-Host "[3/6] Calibrating Windows outputs..." -ForegroundColor Yellow
    Write-Host "No old IDs are kept: the current Windows ones are captured." -ForegroundColor DarkGray

    # In both modes we already have the IDs captured from the Windows list.
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
        Version                = "1.5.0"
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

    # G HUB mode specific fields.
    if ($DetectionMode -eq 'LogitechGHub' -and $ghubHeadset) {
        $config['GHubDisplayName'] = [string]$ghubHeadset.extendedDisplayName
        $config['GHubPort']        = 9010
    }

    # Ask whether to disable the headset's audio enhancements now (requires a
    # one-off elevation via UAC).
    Write-Host ""
    Write-Host "Windows Audio Enhancements:" -ForegroundColor Yellow
    $enhChoice = Read-Host "Do you want to disable the headset's audio enhancements? (y/N)"
    if ($enhChoice -match '^(s|si|sí|y|yes)$') {
        $config['EnhancementsDeviceId'] = [string]$headsetOutput.ItemId
        $config['DisableEnhancementsOnStart'] = $true
        Write-Host "      They will be disabled (a UAC window may appear)..." -ForegroundColor DarkGray
    }

    $config | ConvertTo-Json -Depth 10 |
        Set-Content -Path $ConfigPath -Encoding UTF8

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

    # The shortcut launches wscript.exe, not PowerShell directly, so no
    # console window remains visible at login.
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $WScriptExe
    $Shortcut.Arguments = "`"$LauncherVbs`""
    $Shortcut.WorkingDirectory = $InstallDir
    $Shortcut.IconLocation = "$env:SystemRoot\System32\SndVol.exe,0"
    $Shortcut.Description = "PRO X 2 AutoSwitch - invisible startup"
    $Shortcut.Save()

    # Start now, hidden.
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
    Close-GHubConnection
}

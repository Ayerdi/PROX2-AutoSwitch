#requires -Version 5.1
$ErrorActionPreference = "Stop"

# Ruta canonica del script: $PSCommandPath (no $MyInvocation.MyCommand.Path,
# que dentro de una funcion describe la invocacion y puede quedar vacio).
$script:RuntimePath = $PSCommandPath

$InstallDir = Split-Path -Parent $script:RuntimePath
$ConfigPath = Join-Path $InstallDir "config.json"
$SvclPath   = Join-Path $InstallDir "svcl.exe"
$LogPath    = Join-Path $InstallDir "autoswitch.log"
$script:HelperPath = Join-Path $InstallDir "Toggle-AudioEnhancements.ps1"
$script:DefaultHeadsetControlPath = Join-Path $InstallDir "headsetcontrol.exe"

if (-not (Test-Path $ConfigPath)) { exit 10 }
if (-not (Test-Path $SvclPath))   { exit 11 }

$Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json

# Logica compartida (extraccion de Item ID, debounce, CSV, estados, config).
$ModulePath = Join-Path $InstallDir "lib\AutoSwitchCore.psm1"
if (-not (Test-Path $ModulePath)) { exit 12 }
Import-Module $ModulePath -ErrorAction Stop

# SteelSeries provider. It is imported last because it extends
# Get-ConfigDetectionMode with SteelSeriesNova5 while preserving legacy modes.
$SteelSeriesModulePath = Join-Path $InstallDir "lib\SteelSeriesNova5.psm1"
if (-not (Test-Path $SteelSeriesModulePath)) { exit 14 }
Import-Module $SteelSeriesModulePath -ErrorAction Stop

# Timeouts de G HUB (ms). Overridables desde config.json.
$script:ConnectTimeoutMs = 5000
$script:ReceiveTimeoutMs = 5000
$script:RequestTimeoutMs = 10000
foreach ($k in 'ConnectTimeoutMs', 'ReceiveTimeoutMs', 'RequestTimeoutMs') {
    if ($Config.$k) { Set-Variable -Scope script -Name $k -Value ([int]$Config.$k) }
}

$script:DetectionMode = Get-ConfigDetectionMode -Config $Config
if (-not $script:DetectionMode) {
    Write-Host "config.json tiene un DetectionMode no valido. Reinstala o corrige el archivo."
    exit 13
}

function Write-AutoSwitchLog {
    param([string]$Message)

    try {
        if ((Test-Path $LogPath) -and ((Get-Item $LogPath).Length -gt 1MB)) {
            $old = "$LogPath.old"
            Remove-Item $old -Force -ErrorAction SilentlyContinue
            Move-Item $LogPath $old -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

# Migracion de config v1.1.0 -> v1.3.0: se anade DetectionMode si falta.
if (-not $Config.PSObject.Properties['DetectionMode']) {
    try {
        $migrated = [ordered]@{}
        foreach ($p in $Config.PSObject.Properties) {
            $migrated[$p.Name] = $p.Value
        }
        $migrated['DetectionMode'] = $script:DetectionMode
        $migrated['Version'] = '1.3.0'
        $migrated | ConvertTo-Json -Depth 10 |
            Set-Content -Path $ConfigPath -Encoding UTF8
        Write-AutoSwitchLog "Config migrated to v1.3.0 (DetectionMode=$script:DetectionMode)."
    }
    catch { }
}

# Impide dos instancias del runtime para el mismo usuario.
# El worker (AUTOSWITCH_WORKER=1) es un proceso hijo legitimo del runtime y
# no debe competir por el mutex.
$createdNew = $false
$mutex = $null
if ($env:AUTOSWITCH_WORKER -ne '1') {
    $mutexName = "Local\PROX2AutoSwitch_" + [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
    if (-not $createdNew) {
        exit 0
    }
}

$script:Ws  = $null

function Close-GHubConnection {
    # El cierre no debe poder colgar la recuperacion: si CloseAsync no
    # termina en 1 s (o falla), Abort() + Dispose() garantizan salida.
    if ($null -ne $script:Ws -and
        $script:Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $closeCts = New-Object System.Threading.CancellationTokenSource
        $closeCts.CancelAfter(1000)
        try {
            $script:Ws.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "reconnect",
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

    try {
        if ($null -ne $script:Ws) { $script:Ws.Dispose() }
    } catch {}

    $script:Ws  = $null
}

# Token de timeout G HUB: definido en lib\AutoSwitchCore.psm1 (importado arriba).

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

    # WindowsEndpoint configs may never have had GHubPort. Reconfigure can
    # switch such a config to PRO X 2, so use the established default safely.
    $ghubPort = 9010
    if ($Config.PSObject.Properties['GHubPort'] -and $Config.GHubPort) {
        $ghubPort = [int]$Config.GHubPort
    }
    $uri = New-Object System.Uri("ws://localhost:$ghubPort")

    $timeout = New-GHubTimeoutToken -Milliseconds $script:ConnectTimeoutMs
    try {
        $script:Ws.ConnectAsync($uri, $timeout.Token).GetAwaiter().GetResult() | Out-Null
    }
    catch [System.OperationCanceledException] {
        throw "Timeout al conectar con G HUB ($($script:ConnectTimeoutMs) ms)."
    }
    finally {
        $timeout.Dispose()
    }

    if ($script:Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "No se pudo conectar con Logitech G HUB."
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
        throw "Timeout al enviar peticion a G HUB ($($script:ReceiveTimeoutMs) ms)."
    }
    finally {
        $timeout.Dispose()
    }
}

function Receive-GHubText {
    param(
        # Deadline duro de la peticion: ningun fragmento puede cruzar este punto.
        [Parameter(Mandatory=$true)][datetime]$Deadline
    )

    $buffer = New-Object byte[] 16384
    $stream = New-Object System.IO.MemoryStream

    try {
        do {
            $remainingMs = [int](($Deadline - (Get-Date)).TotalMilliseconds)
            if ($remainingMs -le 0) {
                throw "Timeout de peticion G HUB ($($script:RequestTimeoutMs) ms)."
            }
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
                throw "Timeout esperando respuesta de G HUB ($($fragmentMs) ms)."
            }
            finally {
                $timeout.Dispose()
            }

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw "G HUB cerro el WebSocket."
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

    $deadline = (Get-Date).AddMilliseconds($script:RequestTimeoutMs)

    while ($true) {
        if ((Get-Date) -gt $deadline) {
            throw "Timeout de peticion G HUB ($($script:RequestTimeoutMs) ms): $Path"
        }

        $raw = Receive-GHubText -Deadline $deadline

        try { $message = $raw | ConvertFrom-Json }
        catch { continue }

        if (($message.msgId -eq $msgId) -or ($message.path -eq $Path)) {
            return $message
        }
    }
}

function Get-ProX2BatteryPath {
    $devices = Invoke-GHubGet -Path "/devices/list"
    $all = @($devices.payload.deviceInfos)

    $headset = $all |
        Where-Object { $_.extendedDisplayName -eq [string]$Config.GHubDisplayName } |
        Select-Object -First 1

    if (-not $headset) {
        $headset = $all |
            Where-Object { $_.extendedDisplayName -match "PRO\s*X\s*2" } |
            Select-Object -First 1
    }

    if (-not $headset) {
        throw "G HUB no devuelve el PRO X 2 en /devices/list."
    }

    Write-AutoSwitchLog ("PRO X 2 detectado por G HUB: {0} ({1})" -f $headset.extendedDisplayName, $headset.id)
    return "/battery/$($headset.id)/state"
}

function Get-SteelSeriesRuntimeConfig {
    $path = $script:DefaultHeadsetControlPath
    if ($Config.PSObject.Properties['HeadsetControlPath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.HeadsetControlPath)) {
        $path = [string]$Config.HeadsetControlPath
    }

    if (-not $Config.PSObject.Properties['SteelSeriesProductId']) {
        throw 'SteelSeriesProductId is missing from config.json.'
    }
    $productId = [int]$Config.SteelSeriesProductId
    if ($productId -notin @(0x2232, 0x2253)) {
        throw ("Unsupported SteelSeriesProductId: 0x{0:X4}" -f $productId)
    }

    return [pscustomobject]@{
        HeadsetControlPath = $path
        ProductId = $productId
    }
}

function Get-DefaultRenderItemId {
    $raw = & $SvclPath /GetColumnValue "DefaultRenderDevice" "Item ID" 2>&1
    $text = ($raw | Out-String).Trim()

    $id = Get-RenderItemIdFromText -Text $text
    if (-not $id) {
        throw "No se pudo leer el Item ID del dispositivo predeterminado. Salida: $text"
    }

    return $id
}

function Set-AudioOutput {
    param(
        [Parameter(Mandatory=$true)][string]$DeviceId,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $current = $null
    try { $current = Get-DefaultRenderItemId } catch {}

    if ($current -and ($current -ieq $DeviceId)) { return }

    & $SvclPath /SetDefault $DeviceId all | Out-Null
    Start-Sleep -Milliseconds 350

    $actual = Get-DefaultRenderItemId
    if ($actual -ieq $DeviceId) {
        Write-AutoSwitchLog "Output changed -> $Label"
        return
    }

    Start-Sleep -Milliseconds 500
    & $SvclPath /SetDefault $DeviceId all | Out-Null
    Start-Sleep -Milliseconds 350

    $actual = Get-DefaultRenderItemId
    if ($actual -ieq $DeviceId) {
        Write-AutoSwitchLog "Output changed -> $Label (segundo intento)"
        return
    }

    throw "svcl no consiguio establecer '$Label'. Esperado=$DeviceId Actual=$actual"
}

# --- Estado del endpoint de Windows (DetectionMode=WindowsEndpoint) ---
function Get-SvclCsvExport {
    $raw = & $SvclPath /scomma "" 2>&1
    return ($raw | Out-String).Trim()
}

function Get-HeadsetEndpointState {
    $csv = Get-SvclCsvExport

    if (-not (Test-SvclExportValid -CsvText $csv)) { return 'Unknown' }

    $rows = ConvertFrom-SvclCsv -Text $csv
    $row = $rows |
        Where-Object {
            $id = Get-CsvColumn -Row $_ -Names @('Item ID')
            $null -ne $id -and $id.Trim().ToLowerInvariant() -eq [string]$Config.HeadsetId
        } |
        Select-Object -First 1

    if (-not $row) { return 'Disconnected' }

    $state = Get-CsvColumn -Row $row -Names @('Device State', 'State')
    if ($null -eq $state) { return 'Unknown' }

    return Resolve-EndpointState -State $state
}

# --- Tray icon + Timer (message pump) + worker process ---
$script:TrayIcon = $null
$script:MenuItemAutoSwitch = $null
$script:MenuItemEnhancements = $null
$script:MenuTimer = $null
$script:MenuItemInfoHeadset = $null
$script:MenuItemInfoFallback = $null
$script:MenuItemInfoNext = $null
$script:ReloadFlag = $null

function Get-EnhancementsAction {
    $fx = Get-EndpointFxState -DeviceId ([string]$Config.HeadsetId)
    if ($null -eq $fx) { return $null }
    if ($fx) { return 'Enable' }
    return 'Disable'
}

function Update-EnhancementsMenu {
    if (-not $script:MenuItemEnhancements) { return }

    $action = Get-EnhancementsAction
    $headsetName = if ($Config.HeadsetName) { [string]$Config.HeadsetName } else { 'this device' }

    if ($null -eq $action) {
        $script:MenuItemEnhancements.Text = "Audio Enhancements (unreadable)"
        $script:MenuItemEnhancements.Enabled = $false
        return
    }

    $script:MenuItemEnhancements.Enabled = $true
    if ($action -eq 'Disable') {
        $script:MenuItemEnhancements.Text = "Disable Audio Enhancements for $headsetName"
    }
    else {
        $script:MenuItemEnhancements.Text = "Enable Audio Enhancements for $headsetName"
    }
}

function Invoke-EnhancementsToggle {
    if (-not (Test-Path $HelperPath)) {
        Write-AutoSwitchLog "Enhancements helper not found: $HelperPath"
        return
    }

    $action = Get-EnhancementsAction
    if ($null -eq $action) {
        Write-AutoSwitchLog "Could not read the headset's enhancements state."
        return
    }

    try {
        Write-AutoSwitchLog ("Requesting {0} enhancements on {1}..." -f $action, $Config.HeadsetId)

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$HelperPath`" -DeviceId `"$($Config.HeadsetId)`" -Action $action"
        $psi.UseShellExecute = $true
        $psi.Verb = "RunAs"
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()
    }
    catch {
        Write-AutoSwitchLog ("Enhancements: change canceled or failed ({0})." -f $_.Exception.Message)
        return
    }

    if ($proc.ExitCode -eq 0) {
        Write-AutoSwitchLog "Enhancements: change verified by the helper."
        Update-EnhancementsMenu
    }
    else {
        Write-AutoSwitchLog "Enhancements: the helper did not confirm the change (exit code $($proc.ExitCode))."
    }
}

function Get-RenderDevicesFromCsv {
    $csv = Get-SvclCsvExport
    if (-not (Test-SvclExportValid -CsvText $csv)) { return @() }
    return @(Get-SvclRenderDevice -CsvText $csv)
}

function Update-TrayInfo {
    $hs = if ($Config.HeadsetName) { [string]$Config.HeadsetName } else { [string]$Config.HeadsetId }
    $fb = if ($Config.SpeakerName) { [string]$Config.SpeakerName } else { [string]$Config.SpeakerId }
    if ($script:MenuItemInfoHeadset) {
        $script:MenuItemInfoHeadset.Text = "Headset: $hs"
        $script:MenuItemInfoHeadset.Enabled = $false
    }
    if ($script:MenuItemInfoFallback) {
        $script:MenuItemInfoFallback.Text = "Fallback: $fb"
        $script:MenuItemInfoFallback.Enabled = $false
    }

    $next = "Current: ?"
    try {
        $current = Get-DefaultRenderItemId
        if ($current -ieq [string]$Config.HeadsetId) {
            $next = "Next switch: $fb"
        }
        elseif ($current -ieq [string]$Config.SpeakerId) {
            $next = "Next switch: $hs"
        }
        else {
            $next = "Current: $current"
        }
    }
    catch { $next = "Next switch: unknown" }

    if ($script:MenuItemInfoNext) {
        $script:MenuItemInfoNext.Text = $next
        $script:MenuItemInfoNext.Enabled = $false
    }
}

# --- Reconfigurar headset/fallback sin reinstalar ---
function Save-Config {
    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Get-HeadsetStateForId {
    param(
        [Parameter(Mandatory = $true)][string]$ItemId,
        [string]$DeviceName,
        [string]$EndpointName,
        [switch]$Diagnose
    )

    $csv = Get-SvclCsvExport
    if (-not (Test-SvclExportValid -CsvText $csv)) {
        if ($Diagnose) { Write-AutoSwitchLog ("Get-HeadsetStateForId: svcl export invalido/vacio para {0}" -f $ItemId) }
        return 'Unknown'
    }

    $rows = @(ConvertFrom-SvclCsv -Text $csv)
    $row = $rows |
        Where-Object {
            $id = Get-CsvColumn -Row $_ -Names @('Item ID')
            $null -ne $id -and $id.Trim().ToLowerInvariant() -eq $ItemId.Trim().ToLowerInvariant()
        } |
        Select-Object -First 1

    if (-not $row -and
        (-not [string]::IsNullOrWhiteSpace($DeviceName) -or
         -not [string]::IsNullOrWhiteSpace($EndpointName))) {
        $row = Find-SvclRenderDeviceByIdentity -Rows $rows -DeviceName $DeviceName -Name $EndpointName
        if ($row) {
            $id = Get-CsvColumn -Row $row -Names @('Item ID')
            if ($Diagnose) {
                Write-AutoSwitchLog ("Get-HeadsetStateForId: {0} no encontrado por Item ID; identidad DeviceName='{1}' Name='{2}' -> nuevo Item ID {3}" -f $ItemId, $DeviceName, $EndpointName, $id)
            }
            return [pscustomobject]@{
                State   = (Resolve-EndpointState -State (Get-CsvColumn -Row $row -Names @('Device State', 'State')))
                FoundId = $id
            }
        }
    }

    if (-not $row) {
        if ($Diagnose) {
            $lines = @()
            foreach ($r in $rows) {
                $name  = Get-CsvColumn -Row $r -Names @('Device Name', 'Name')
                $id    = Get-CsvColumn -Row $r -Names @('Item ID')
                $st    = Get-CsvColumn -Row $r -Names @('Device State', 'State')
                $type  = Get-CsvColumn -Row $r -Names @('Type')
                $dir   = Get-CsvColumn -Row $r -Names @('Direction')
                $lines += "[$type/$dir] '$name' id='$id' state='$st'"
            }
            Write-AutoSwitchLog ("Get-HeadsetStateForId: NO se encontro {0} en la exportacion. Fila(s) disponibles:`n{1}" -f $ItemId, ($lines -join "`n"))
        }
        return 'Disconnected'
    }

    $state = Get-CsvColumn -Row $row -Names @('Device State', 'State')
    if ($null -eq $state) {
        if ($Diagnose) { Write-AutoSwitchLog ("Get-HeadsetStateForId: fila para {0} sin columna de estado" -f $ItemId) }
        return 'Unknown'
    }

    if ($Diagnose) { Write-AutoSwitchLog ("Get-HeadsetStateForId: {0} -> '{1}'" -f $ItemId, $state) }
    return Resolve-EndpointState -State $state
}

function Wait-ForHeadsetState {
    param(
        [Parameter(Mandatory = $true)][string]$ItemId,
        [Parameter(Mandatory = $true)][string]$Expected,
        [string]$DeviceName,
        [string]$EndpointName,
        [int]$TimeoutSeconds = 12,
        [int]$PollIntervalMs = 500
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $last = $null
    $foundId = $null

    do {
        $res = Get-HeadsetStateForId -ItemId $ItemId -DeviceName $DeviceName -EndpointName $EndpointName
        if ($res -is [pscustomobject]) {
            $last = $res.State
            if ($res.FoundId) { $foundId = $res.FoundId }
        }
        else { $last = $res }

        if ($last -eq $Expected) {
            return [pscustomobject]@{ State = $last; FoundId = $foundId }
        }
        Start-Sleep -Milliseconds $PollIntervalMs
    } while ((Get-Date) -lt $deadline)

    Write-AutoSwitchLog ("Wait-ForHeadsetState: timeout esperando '{0}' para {1}. Ultimo estado observado: {2}" -f $Expected, $ItemId, $last)
    [void](Get-HeadsetStateForId -ItemId $ItemId -DeviceName $DeviceName -EndpointName $EndpointName -Diagnose)
    return [pscustomobject]@{ State = $last; FoundId = $foundId }
}

function Test-GHubProX2 {
    try {
        Connect-GHub
        $devices = Invoke-GHubGet -Path "/devices/list"
        $deviceInfos = @($devices.payload.deviceInfos)

        $candidates = @($deviceInfos | Where-Object {
            $_.extendedDisplayName -match 'PRO\s*X\s*2'
        })

        if ($candidates.Count -eq 0) { return $null }
        if ($candidates.Count -eq 1) { return $candidates[0] }

        foreach ($candidate in $candidates) {
            $answer = [System.Windows.Forms.MessageBox]::Show(
                ("Multiple PRO X 2 devices were found in G HUB.`n`nUse this one?`n{0} ({1})" -f $candidate.extendedDisplayName, $candidate.id),
                "Audio AutoSwitch",
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { return $candidate }
            if ($answer -eq [System.Windows.Forms.DialogResult]::Cancel) { return $null }
        }
        return $null
    }
    catch {
        Write-AutoSwitchLog ("Reconfigure: G HUB check failed: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Test-SteelSeriesNova5ForReconfigure {
    try {
        if (-not (Test-Path -LiteralPath $script:DefaultHeadsetControlPath)) {
            # Reconfigure may be used after switching from another headset.
            # Download the same pinned portable binary the installer uses.
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            [void](Install-HeadsetControlPortable -DestinationPath $script:DefaultHeadsetControlPath)
        }
        return Get-SteelSeriesNova5ConnectedProductId -HeadsetControlPath $script:DefaultHeadsetControlPath
    }
    catch {
        Write-AutoSwitchLog ("Reconfigure: SteelSeries check failed: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Show-ReconfigureDialog {
    $devices = Get-RenderDevicesFromCsv
    if ($devices.Count -lt 2) {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not read the Windows output devices. Is svcl.exe present and the audio system OK?",
            "Audio AutoSwitch",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Audio AutoSwitch - Reconfigure"
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(460, 240)

    $lblHeadset = New-Object System.Windows.Forms.Label
    $lblHeadset.Text = "Headset:"
    $lblHeadset.Location = New-Object System.Drawing.Point(20, 24)
    $lblHeadset.AutoSize = $true

    $comboHeadset = New-Object System.Windows.Forms.ComboBox
    $comboHeadset.DropDownStyle = 'DropDownList'
    $comboHeadset.Location = New-Object System.Drawing.Point(150, 20)
    $comboHeadset.Width = 280
    foreach ($d in $devices) {
        [void]$comboHeadset.Items.Add((Get-SvclDeviceLabel -Row $d))
    }

    $lblFallback = New-Object System.Windows.Forms.Label
    $lblFallback.Text = "Fallback:"
    $lblFallback.Location = New-Object System.Drawing.Point(20, 64)
    $lblFallback.AutoSize = $true

    $comboFallback = New-Object System.Windows.Forms.ComboBox
    $comboFallback.DropDownStyle = 'DropDownList'
    $comboFallback.Location = New-Object System.Drawing.Point(150, 60)
    $comboFallback.Width = 280
    foreach ($d in $devices) {
        [void]$comboFallback.Items.Add((Get-SvclDeviceLabel -Row $d))
    }

    for ($i = 0; $i -lt $devices.Count; $i++) {
        $id = Get-CsvColumn -Row $devices[$i] -Names @('Item ID')
        if ($id -ieq [string]$Config.HeadsetId) { $comboHeadset.SelectedIndex = $i }
        if ($id -ieq [string]$Config.SpeakerId) { $comboFallback.SelectedIndex = $i }
    }

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Pick the headset and the fallback, then click 'Detect mode...'."
    $lblStatus.Location = New-Object System.Drawing.Point(20, 104)
    $lblStatus.Size = New-Object System.Drawing.Size(420, 40)
    $lblStatus.ForeColor = [System.Drawing.Color]::Gray

    $btnDetect = New-Object System.Windows.Forms.Button
    $btnDetect.Text = "Detect mode..."
    $btnDetect.Location = New-Object System.Drawing.Point(150, 150)
    $btnDetect.Width = 120

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(280, 150)
    $btnCancel.Width = 90

    $btnCancel.Add_Click({ $form.Close() })

    $btnDetect.Add_Click({
        $btnDetect.Enabled = $false
        try {
            if ($comboHeadset.SelectedIndex -lt 0 -or $comboFallback.SelectedIndex -lt 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Select both the headset and the fallback first.",
                    "Audio AutoSwitch",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
                return
            }

            $newHeadsetId = Get-CsvColumn -Row $devices[$comboHeadset.SelectedIndex] -Names @('Item ID')
            $newFallbackId = Get-CsvColumn -Row $devices[$comboFallback.SelectedIndex] -Names @('Item ID')
            if (-not (Test-ValidAudioConfig -HeadsetId $newHeadsetId -SpeakerId $newFallbackId)) {
                [System.Windows.Forms.MessageBox]::Show(
                    "The headset and the fallback must be different devices.",
                    "Audio AutoSwitch",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
                return
            }

            $selectedHeadsetRow = $devices[$comboHeadset.SelectedIndex]
            $newHeadsetName = Get-SvclDeviceLabel -Row $selectedHeadsetRow
            $newHeadsetDeviceName = Get-CsvColumn -Row $selectedHeadsetRow -Names @('Device Name')
            $newHeadsetEndpointName = Get-CsvColumn -Row $selectedHeadsetRow -Names @('Name')
            $newSpeakerName = Get-SvclDeviceLabel -Row $devices[$comboFallback.SelectedIndex]

            $lblStatus.Text = "Step 1/3: turn the headset ON, then click OK in the prompt."
            $lblStatus.Refresh()

            [System.Windows.Forms.MessageBox]::Show(
                "Turn the headset ON now, then click OK.`n(It can take several seconds for Windows to notice.)",
                "Audio AutoSwitch",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            $r1 = Wait-ForHeadsetState -ItemId $newHeadsetId -DeviceName $newHeadsetDeviceName -EndpointName $newHeadsetEndpointName -Expected 'Connected' -TimeoutSeconds 15

            [System.Windows.Forms.MessageBox]::Show(
                "Turn the headset OFF now, then click OK.`n(It can take several seconds for Windows to notice.)",
                "Audio AutoSwitch",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            $r2 = Wait-ForHeadsetState -ItemId $newHeadsetId -DeviceName $newHeadsetDeviceName -EndpointName $newHeadsetEndpointName -Expected 'Disconnected' -TimeoutSeconds 15

            [System.Windows.Forms.MessageBox]::Show(
                "Turn the headset back ON now, then click OK.`n(It can take several seconds for Windows to notice.)",
                "Audio AutoSwitch",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            $r3 = Wait-ForHeadsetState -ItemId $newHeadsetId -DeviceName $newHeadsetDeviceName -EndpointName $newHeadsetEndpointName -Expected 'Connected' -TimeoutSeconds 20

            $s1 = $r1.State
            $s2 = $r2.State
            $s3 = $r3.State
            $lblStatus.Text = "Step 2/3: ON=$s1  OFF=$s2  ON=$s3"
            $lblStatus.Refresh()

            $observedId = $null
            if ($r3.FoundId) { $observedId = $r3.FoundId }
            elseif ($r1.FoundId) { $observedId = $r1.FoundId }
            if ($observedId) { $newHeadsetId = $observedId }

            Write-AutoSwitchLog ("Reconfigure wizard: ON=$s1 OFF=$s2 ON=$s3 (headset={0} itemId={1})" -f $newHeadsetName, $newHeadsetId)

            $newMode = $null
            $newGhubName = $null
            $newSteelSeriesProductId = $null

            if ($s1 -eq 'Connected' -and $s2 -eq 'Disconnected' -and $s3 -eq 'Connected') {
                $newMode = "WindowsEndpoint"
            }
            else {
                $steelAnswer = [System.Windows.Forms.MessageBox]::Show(
                    "Windows does not reflect the physical ON/OFF cycle of this headset.`n`nIs it a SteelSeries Arctis Nova 5 or Nova 5X?",
                    "Audio AutoSwitch",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )

                if ($steelAnswer -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $lblStatus.Text = "Step 3/3: checking SteelSeries receiver..."
                    $lblStatus.Refresh()
                    $newSteelSeriesProductId = Test-SteelSeriesNova5ForReconfigure

                    if ($newSteelSeriesProductId) {
                        [System.Windows.Forms.MessageBox]::Show(
                            "SteelSeries receiver found. Turn the headset OFF now, then click OK.",
                            "Audio AutoSwitch",
                            [System.Windows.Forms.MessageBoxButtons]::OK,
                            [System.Windows.Forms.MessageBoxIcon]::Information
                        ) | Out-Null
                        $steelOff = Wait-SteelSeriesNova5State -Expected 'Disconnected' -HeadsetControlPath $script:DefaultHeadsetControlPath -ProductId $newSteelSeriesProductId -TimeoutSeconds 15

                        [System.Windows.Forms.MessageBox]::Show(
                            "Turn the headset back ON now, then click OK.",
                            "Audio AutoSwitch",
                            [System.Windows.Forms.MessageBoxButtons]::OK,
                            [System.Windows.Forms.MessageBoxIcon]::Information
                        ) | Out-Null
                        $steelOn = Wait-SteelSeriesNova5State -Expected 'Connected' -HeadsetControlPath $script:DefaultHeadsetControlPath -ProductId $newSteelSeriesProductId -TimeoutSeconds 20

                        if ($steelOff -eq 'Disconnected' -and $steelOn -eq 'Connected') {
                            $newMode = 'SteelSeriesNova5'
                        }
                    }
                }

                if (-not $newMode) {
                    $answer = [System.Windows.Forms.MessageBox]::Show(
                        "No SteelSeries Nova 5/5X cycle was validated.`n`nIs this headset a Logitech PRO X 2 detected by G HUB?",
                        "Audio AutoSwitch",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Question
                    )
                    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                        $lblStatus.Text = "Step 3/3: checking G HUB for PRO X 2..."
                        $lblStatus.Refresh()
                        $ghubDevice = Test-GHubProX2
                        if ($ghubDevice) {
                            $newMode = "LogitechGHub"
                            $newGhubName = [string]$ghubDevice.extendedDisplayName
                        }
                    }
                }
            }

            if (-not $newMode) {
                [System.Windows.Forms.MessageBox]::Show(
                    "No compatible detection method found for this headset.`n`nThe configuration was NOT changed. Run the installer for a full setup.",
                    "Audio AutoSwitch",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
                return
            }

            $Config.HeadsetId   = [string]$newHeadsetId
            $Config.SpeakerId   = [string]$newFallbackId
            $Config.HeadsetName = $newHeadsetName
            $Config.SpeakerName = $newSpeakerName
            $Config | Add-Member -NotePropertyName DetectionMode -NotePropertyValue $newMode -Force
            $Config | Add-Member -NotePropertyName Version -NotePropertyValue '1.3.0' -Force
            $Config | Add-Member -NotePropertyName EnhancementsDeviceId -NotePropertyValue ([string]$newHeadsetId) -Force

            if ($newMode -eq 'LogitechGHub') {
                $ghubPortToSave = 9010
                if ($Config.PSObject.Properties['GHubPort'] -and $Config.GHubPort) {
                    $ghubPortToSave = [int]$Config.GHubPort
                }
                $Config | Add-Member -NotePropertyName GHubDisplayName -NotePropertyValue $newGhubName -Force
                $Config | Add-Member -NotePropertyName GHubPort -NotePropertyValue $ghubPortToSave -Force
            }
            else {
                $Config.PSObject.Properties.Remove('GHubDisplayName')
                $Config.PSObject.Properties.Remove('GHubPort')
            }

            if ($newMode -eq 'SteelSeriesNova5') {
                $Config | Add-Member -NotePropertyName SteelSeriesProductId -NotePropertyValue ([int]$newSteelSeriesProductId) -Force
                $Config | Add-Member -NotePropertyName HeadsetControlPath -NotePropertyValue ([string]$script:DefaultHeadsetControlPath) -Force
            }
            else {
                $Config.PSObject.Properties.Remove('SteelSeriesProductId')
                $Config.PSObject.Properties.Remove('HeadsetControlPath')
            }

            Save-Config
            try { New-Item -ItemType File -Path $script:ReloadFlag -Force | Out-Null } catch {}

            Write-AutoSwitchLog ("Reconfigured: headset={0} fallback={1} mode={2}" -f $Config.HeadsetName, $Config.SpeakerName, $newMode)
            $form.Close()

            [System.Windows.Forms.MessageBox]::Show(
                "Reconfigured.`nHeadset: $newHeadsetName`nFallback: $newSpeakerName`nDetection mode: $newMode",
                "Audio AutoSwitch",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null

            Update-TrayInfo
            Update-EnhancementsMenu
        }
        catch {
            Write-AutoSwitchLog ("Reconfigure failed: {0}" -f $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show(
                "Reconfigure failed: $($_.Exception.Message)",
                "Audio AutoSwitch",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        finally { $btnDetect.Enabled = $true }
    })

    $form.Controls.Add($lblHeadset)
    $form.Controls.Add($comboHeadset)
    $form.Controls.Add($lblFallback)
    $form.Controls.Add($comboFallback)
    $form.Controls.Add($lblStatus)
    $form.Controls.Add($btnDetect)
    $form.Controls.Add($btnCancel)

    $form.ShowDialog() | Out-Null
}

function Invoke-Reconfigure {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    try { Show-ReconfigureDialog }
    catch {
        Write-AutoSwitchLog ("Reconfigure failed: {0}" -f $_.Exception.Message)
        try {
            [System.Windows.Forms.MessageBox]::Show(
                "Reconfigure failed: $($_.Exception.Message)",
                "Audio AutoSwitch",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        catch { }
    }
}

function Invoke-AutoSwitchToggle {
    $newState = -not (Test-Path $script:EnabledFlag)
    Set-AutoSwitchEnabledState -Enabled $newState
    if ($script:MenuItemAutoSwitch) {
        if ($newState) {
            $script:MenuItemAutoSwitch.Text = "AutoSwitch: Enabled"
            $script:MenuItemAutoSwitch.Checked = $true
        }
        else {
            $script:MenuItemAutoSwitch.Text = "AutoSwitch: Disabled"
            $script:MenuItemAutoSwitch.Checked = $false
        }
    }
    Write-AutoSwitchLog ("AutoSwitch {0} por el usuario." -f $(if ($newState) { 'activado' } else { 'desactivado' }))
}

function Stop-Runtime {
    Stop-Worker
    try { if ($script:MenuTimer) { $script:MenuTimer.Stop() } } catch {}
    try { $script:TrayIcon.Visible = $false } catch {}
    try { if ($script:MainForm) { $script:MainForm.Close() } } catch {}
    [System.Windows.Forms.Application]::Exit()
}

# --- Worker: proceso separado que hace el polling ---
$script:ControlDir = Join-Path $InstallDir "control"
$script:EnabledFlag = Join-Path $script:ControlDir "enabled.flag"
$script:StopFlag    = Join-Path $script:ControlDir "stop.flag"
$script:ReloadFlag  = Join-Path $script:ControlDir "reload.flag"
$script:WorkerProcess = $null

function Start-Worker {
    try { New-Item -ItemType Directory -Path $script:ControlDir -Force | Out-Null } catch {}
    try { New-Item -ItemType File -Path $script:EnabledFlag -Force | Out-Null } catch {}
    try { Remove-Item $script:StopFlag -Force -ErrorAction SilentlyContinue } catch {}

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:RuntimePath`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['AUTOSWITCH_WORKER'] = '1'
    $psi.EnvironmentVariables['AUTOSWITCH_CONTROL'] = $script:ControlDir

    $script:WorkerProcess = [System.Diagnostics.Process]::Start($psi)
}

function Set-AutoSwitchEnabledState {
    param([bool]$Enabled)
    if ($Enabled) {
        try { New-Item -ItemType File -Path $script:EnabledFlag -Force | Out-Null } catch {}
    }
    else {
        try { Remove-Item $script:EnabledFlag -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Stop-Worker {
    try { New-Item -ItemType File -Path $script:StopFlag -Force | Out-Null } catch {}
    try {
        if ($script:WorkerProcess -and -not $script:WorkerProcess.HasExited) {
            $script:WorkerProcess.WaitForExit(5000) | Out-Null
            if (-not $script:WorkerProcess.HasExited) { $script:WorkerProcess.Kill() }
            $script:WorkerProcess.Dispose()
        }
    } catch {}
}

function Start-WorkerLoop {
    $controlDir = $env:AUTOSWITCH_CONTROL
    $enabledFlag = Join-Path $controlDir "enabled.flag"
    $stopFlag    = Join-Path $controlDir "stop.flag"
    $reloadFlag  = Join-Path $controlDir "reload.flag"

    $lastState = $null
    $misses = 0
    $availabilityLogged = $false
    $script:WorkerBatteryPath = $null

    Write-AutoSwitchLog "Worker started (mode $script:DetectionMode)."

    while (-not (Test-Path $stopFlag)) {
        if (Test-Path $reloadFlag) {
            try {
                Remove-Item $reloadFlag -Force -ErrorAction SilentlyContinue
                $newConfig = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
                if ($newConfig) {
                    Set-Variable -Name Config -Value $newConfig -Scope 1
                    $newMode = Get-ConfigDetectionMode -Config $newConfig
                    if ($newMode) { $script:DetectionMode = $newMode }
                    $lastState = $null
                    $misses = 0
                    $script:WorkerBatteryPath = $null
                    $availabilityLogged = $false
                    Write-AutoSwitchLog "Config reloaded (reconfigure)."
                }
            }
            catch { Write-AutoSwitchLog ("Could not reload config: {0}" -f $_.Exception.Message) }
        }

        if (-not (Test-Path $enabledFlag)) {
            Start-Sleep -Milliseconds ([int]$Config.PollMilliseconds)
            continue
        }

        $isOn = $false
        $known = $false

        if ($script:DetectionMode -eq 'WindowsEndpoint') {
            try {
                $endpoint = Get-HeadsetEndpointState
                if ($endpoint -eq 'Connected') { $isOn = $true; $known = $true }
                elseif ($endpoint -eq 'Disconnected') { $isOn = $false; $known = $true }
            }
            catch {
                if (-not $availabilityLogged) {
                    Write-AutoSwitchLog ("WindowsEndpoint no disponible: {0}. Se reintentara." -f $_.Exception.Message)
                    $availabilityLogged = $true
                }
            }
        }
        elseif ($script:DetectionMode -eq 'SteelSeriesNova5') {
            try {
                $steelConfig = Get-SteelSeriesRuntimeConfig
                $steelState = Get-SteelSeriesNova5State -HeadsetControlPath $steelConfig.HeadsetControlPath -ProductId $steelConfig.ProductId

                if ($steelState -eq 'Connected') {
                    $isOn = $true
                    $known = $true
                    if ($availabilityLogged) { Write-AutoSwitchLog "SteelSeries HID state provider recovered." }
                    $availabilityLogged = $false
                }
                elseif ($steelState -eq 'Disconnected') {
                    $isOn = $false
                    $known = $true
                    if ($availabilityLogged) { Write-AutoSwitchLog "SteelSeries HID state provider recovered." }
                    $availabilityLogged = $false
                }
                elseif (-not $availabilityLogged) {
                    Write-AutoSwitchLog "SteelSeries HID state is Unknown. No audio change will be made until a known state returns."
                    $availabilityLogged = $true
                }
            }
            catch {
                if (-not $availabilityLogged) {
                    Write-AutoSwitchLog ("SteelSeries HID provider unavailable: {0}. Unknown state; no audio change." -f $_.Exception.Message)
                    $availabilityLogged = $true
                }
            }
        }
        else {
            try {
                if (-not $script:WorkerBatteryPath) {
                    Connect-GHub
                    $script:WorkerBatteryPath = Get-ProX2BatteryPath

                    if ($availabilityLogged) { Write-AutoSwitchLog "G HUB connection recovered." }
                    else { Write-AutoSwitchLog "Connected to G HUB." }
                    $availabilityLogged = $false
                }

                $battery = Invoke-GHubGet -Path $script:WorkerBatteryPath
                $isOn = $null -ne $battery.payload
                $known = $true
            }
            catch {
                Close-GHubConnection
                $script:WorkerBatteryPath = $null
                if (-not $availabilityLogged) {
                    Write-AutoSwitchLog ((
                        "G HUB/AutoSwitch no disponible: {0}. " +
                        "Se reintentara; mientras el estado sea desconocido no se cambia la salida."
                    ) -f $_.Exception.Message)
                    $availabilityLogged = $true
                }
            }
        }

        if ($known) {
            $state = Resolve-HeadsetState `
                -PayloadPresent $isOn `
                -Misses $misses `
                -OffMissThreshold ([int]$Config.OffMissThreshold)
            $misses = $state.Misses

            if ($state.Decision -and ($null -eq $lastState -or $state.IsOn -ne $lastState)) {
                try {
                    if ($state.IsOn) {
                        Set-AudioOutput -DeviceId ([string]$Config.HeadsetId) -Label ([string]$Config.HeadsetName)
                    }
                    else {
                        Set-AudioOutput -DeviceId ([string]$Config.SpeakerId) -Label ([string]$Config.SpeakerName)
                    }
                    $lastState = $state.IsOn
                }
                catch { Write-AutoSwitchLog ("No se pudo cambiar la salida de audio: {0}. Se reintentara." -f $_.Exception.Message) }
            }
        }

        Start-Sleep -Milliseconds ([int]$Config.PollMilliseconds)
    }

    Close-GHubConnection
    Write-AutoSwitchLog "Worker stopped."
}

function Initialize-TrayAndTimer {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon

    try {
        $iconFile = Join-Path $InstallDir "icon.ico"
        if (Test-Path $iconFile) { $script:TrayIcon.Icon = [System.Drawing.Icon]::new($iconFile) }
        else { $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application }
    }
    catch { $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application }

    $script:TrayIcon.Text = "Audio AutoSwitch"
    $script:TrayIcon.Visible = $true

    $script:MainForm = New-Object System.Windows.Forms.Form
    $script:MainForm.WindowState = 'Minimized'
    $script:MainForm.ShowInTaskbar = $false
    $script:MainForm.Visible = $false
    $script:MainForm.FormBorderStyle = 'None'

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $script:MenuItemInfoHeadset = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:MenuItemInfoHeadset.Text = "Headset: ..."
    $script:MenuItemInfoHeadset.Enabled = $false
    [void]$menu.Items.Add($script:MenuItemInfoHeadset)

    $script:MenuItemInfoFallback = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:MenuItemInfoFallback.Text = "Fallback: ..."
    $script:MenuItemInfoFallback.Enabled = $false
    [void]$menu.Items.Add($script:MenuItemInfoFallback)

    $script:MenuItemInfoNext = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:MenuItemInfoNext.Text = "Next switch: ..."
    $script:MenuItemInfoNext.Enabled = $false
    [void]$menu.Items.Add($script:MenuItemInfoNext)

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $script:MenuItemAutoSwitch = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:MenuItemAutoSwitch.Text = "AutoSwitch: Enabled"
    $script:MenuItemAutoSwitch.Checked = $true
    $script:MenuItemAutoSwitch.Add_Click({ Invoke-AutoSwitchToggle })
    [void]$menu.Items.Add($script:MenuItemAutoSwitch)

    $script:MenuItemEnhancements = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:MenuItemEnhancements.Text = "Audio Enhancements..."
    $script:MenuItemEnhancements.Add_Click({ Invoke-EnhancementsToggle })
    [void]$menu.Items.Add($script:MenuItemEnhancements)

    $reconfigureItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $reconfigureItem.Text = "Reconfigure..."
    $reconfigureItem.Add_Click({ Invoke-Reconfigure })
    [void]$menu.Items.Add($reconfigureItem)

    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitItem.Text = "Exit"
    $exitItem.Add_Click({ Stop-Runtime })
    [void]$menu.Items.Add($exitItem)

    $script:TrayIcon.ContextMenuStrip = $menu

    $script:MenuTimer = New-Object System.Windows.Forms.Timer
    $script:MenuTimer.Interval = 5000
    $script:MenuTimer.Add_Tick({
        Update-EnhancementsMenu
        Update-TrayInfo
    })
    $script:MenuTimer.Start()

    Update-EnhancementsMenu
    Update-TrayInfo
    Write-AutoSwitchLog "Tray configured; message pump active."
}

Write-AutoSwitchLog "PRO X 2 AutoSwitch started (mode $script:DetectionMode)."

if ($env:AUTOSWITCH_WORKER -eq '1') {
    Start-WorkerLoop
    exit 0
}

try {
    Start-Worker
    Initialize-TrayAndTimer

    if ($Config.DisableEnhancementsOnStart) {
        $action = Get-EnhancementsAction
        if ($action -eq 'Disable') {
            Write-AutoSwitchLog "DisableEnhancementsOnStart is active: disabling the headset enhancements."
            Invoke-EnhancementsToggle
        }
    }

    [System.Windows.Forms.Application]::Run($script:MainForm)
    Write-AutoSwitchLog "Message pump finished (Exit)."
}
finally {
    Stop-Worker
    try { $script:TrayIcon.Visible = $false } catch {}
    Close-GHubConnection
    try {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    } catch {}
}

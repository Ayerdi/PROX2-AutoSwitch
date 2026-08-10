#requires -Version 5.1
$ErrorActionPreference = "Stop"

$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $InstallDir "config.json"
$SvclPath   = Join-Path $InstallDir "svcl.exe"
$LogPath    = Join-Path $InstallDir "autoswitch.log"
$HelperPath = Join-Path $InstallDir "Toggle-AudioEnhancements.ps1"

if (-not (Test-Path $ConfigPath)) { exit 10 }
if (-not (Test-Path $SvclPath))   { exit 11 }

$Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json

# Logica compartida (extraccion de Item ID, debounce, CSV, estados, config).
$ModulePath = Join-Path $InstallDir "lib\AutoSwitchCore.psm1"
if (-not (Test-Path $ModulePath)) { exit 12 }
Import-Module $ModulePath -ErrorAction Stop

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

# Migracion de config v1.1.0 -> v1.2.0: se anade DetectionMode si falta.
if (-not $Config.PSObject.Properties['DetectionMode']) {
    try {
        $migrated = [ordered]@{}
        foreach ($p in $Config.PSObject.Properties) {
            $migrated[$p.Name] = $p.Value
        }
        $migrated['DetectionMode'] = $script:DetectionMode
        $migrated['Version'] = '1.2.0'
        $migrated | ConvertTo-Json -Depth 10 |
            Set-Content -Path $ConfigPath -Encoding UTF8
        Write-AutoSwitchLog "Config migrada a v1.2.0 (DetectionMode=$script:DetectionMode)."
    }
    catch { }
}

# Impide dos instancias del runtime para el mismo usuario.
$createdNew = $false
$mutexName = "Local\PROX2AutoSwitch_" + [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
    exit 0
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

    $uri = New-Object System.Uri("ws://localhost:$($Config.GHubPort)")

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
            # El fragmento espera como mucho ReceiveTimeoutMs, nunca mas alla
            # del deadline global de la peticion.
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

    # Limite global por peticion: aunque G HUB intercale eventos,
    # la respuesta buscada debe llegar antes del deadline.
    $deadline = (Get-Date).AddMilliseconds($script:RequestTimeoutMs)

    while ($true) {
        if ((Get-Date) -gt $deadline) {
            throw "Timeout de peticion G HUB ($($script:RequestTimeoutMs) ms): $Path"
        }

        $raw = Receive-GHubText -Deadline $deadline

        try {
            $message = $raw | ConvertFrom-Json
        }
        catch {
            continue
        }

        # G HUB puede intercalar eventos asincronos.
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

function Get-DefaultRenderItemId {
    # IMPORTANTE: /GetColumnValue ya escribe el valor en stdout.
    # No agregar /Stdout aqui: /Stdout añade informacion del item y rompe el parseo.
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

    if ($current -and ($current -ieq $DeviceId)) {
        return
    }

    & $SvclPath /SetDefault $DeviceId all | Out-Null
    Start-Sleep -Milliseconds 350

    $actual = Get-DefaultRenderItemId
    if ($actual -ieq $DeviceId) {
        Write-AutoSwitchLog "Salida cambiada -> $Label"
        return
    }

    # Un reintento por si Windows estaba recreando el endpoint.
    Start-Sleep -Milliseconds 500
    & $SvclPath /SetDefault $DeviceId all | Out-Null
    Start-Sleep -Milliseconds 350

    $actual = Get-DefaultRenderItemId
    if ($actual -ieq $DeviceId) {
        Write-AutoSwitchLog "Salida cambiada -> $Label (segundo intento)"
        return
    }

    throw "svcl no consiguio establecer '$Label'. Esperado=$DeviceId Actual=$actual"
}

# --- Estado del endpoint de Windows (DetectionMode=WindowsEndpoint) ---

function Get-SvclCsvExport {
    # Exporta TODOS los items de sonido en CSV. /scomma "" lista todo.
    $raw = & $SvclPath /scomma "" 2>&1
    return ($raw | Out-String).Trim()
}

function Get-HeadsetEndpointState {
    <#
    .SYNOPSIS
        Devuelve 'Connected' / 'Disconnected' / 'Unknown' del endpoint del headset.
    .DESCRIPTION
        Busca la fila cuyo Item ID coincide con Config.HeadsetId (mas robusto
        que el nombre) y normaliza su columna State/DeviceState.
    #>
    $csv = Get-SvclCsvExport
    $rows = ConvertFrom-SvclCsv -Text $csv

    $row = $rows |
        Where-Object {
            $id = Get-CsvColumn -Row $_ -Names @('Item ID')
            $null -ne $id -and $id.Trim().ToLowerInvariant() -eq [string]$Config.HeadsetId
        } |
        Select-Object -First 1

    if (-not $row) {
        # El endpoint no aparece en la lista: para Windows significa
        # que no esta presente -> Disconnected.
        return 'Disconnected'
    }

    $state = Get-CsvColumn -Row $row -Names @('State', 'DeviceState')
    if ($null -eq $state) {
        return 'Unknown'
    }

    return Resolve-EndpointState -State $state
}

# --- Tray icon + Timer (message pump) ---

$script:TrayIcon = $null
$script:MenuItemAutoSwitch = $null
$script:MenuItemEnhancements = $null
$script:AutoSwitchEnabled = $true
$script:PollTimer = $null
$script:LastState = $null
$script:Misses = 0
$script:AvailabilityLogged = $false
$script:AudioOpInProgress = $false

function Get-EnhancementsAction {
    # Lee el estado actual de SysFx del headset y devuelve 'Disable' o 'Enable'.
    $fx = Get-EndpointFxState -DeviceId ([string]$Config.HeadsetId)
    if ($null -eq $fx) {
        return $null
    }
    if ($fx) { return 'Enable' }   # ya deshabilitados -> ofrecer habilitar
    return 'Disable'               # habilitados -> ofrecer deshabilitar
}

function Update-EnhancementsMenu {
    if (-not $script:MenuItemEnhancements) { return }

    $action = Get-EnhancementsAction
    $headsetName = if ($Config.HeadsetName) { [string]$Config.HeadsetName } else { 'este dispositivo' }

    if ($null -eq $action) {
        $script:MenuItemEnhancements.Text = "Audio Enhancements (no legible)"
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
        Write-AutoSwitchLog "No se encuentra el helper de enhancements: $HelperPath"
        return
    }

    $action = Get-EnhancementsAction
    if ($null -eq $action) {
        Write-AutoSwitchLog "No se pudo leer el estado de enhancements del headset."
        return
    }

    try {
        Write-AutoSwitchLog ("Solicitando {0} enhancements en {1}..." -f $action, $Config.HeadsetId)

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
        # UAC cancelado o error al lanzar.
        Write-AutoSwitchLog ("Enhancements: cambio cancelado o fallido ({0})." -f $_.Exception.Message)
        return
    }

    if ($proc.ExitCode -eq 0) {
        Write-AutoSwitchLog "Enhancements: cambio verificado por el helper."
        Update-EnhancementsMenu
    }
    else {
        Write-AutoSwitchLog "Enhancements: el helper no confirmo el cambio (codigo $($proc.ExitCode))."
    }
}

function Invoke-AutoSwitchToggle {
    $script:AutoSwitchEnabled = -not $script:AutoSwitchEnabled
    if ($script:MenuItemAutoSwitch) {
        if ($script:AutoSwitchEnabled) {
            $script:MenuItemAutoSwitch.Text = "AutoSwitch: Enabled"
            $script:MenuItemAutoSwitch.Checked = $true
        }
        else {
            $script:MenuItemAutoSwitch.Text = "AutoSwitch: Disabled"
            $script:MenuItemAutoSwitch.Checked = $false
        }
    }
    Write-AutoSwitchLog ("AutoSwitch {0} por el usuario." -f $(if ($script:AutoSwitchEnabled) { 'activado' } else { 'desactivado' }))
}

function Stop-Runtime {
    try { $script:TrayIcon.Visible = $false } catch {}
    try { $script:PollTimer.Stop() } catch {}
    [System.Windows.Forms.Application]::Exit()
}

function Invoke-PollOnce {
    if (-not $script:AutoSwitchEnabled) {
        return
    }

    $isOn = $false
    $known = $false

    if ($script:DetectionMode -eq 'WindowsEndpoint') {
        try {
            $endpoint = Get-HeadsetEndpointState
            if ($endpoint -eq 'Connected') {
                $isOn = $true
                $known = $true
            }
            elseif ($endpoint -eq 'Disconnected') {
                $isOn = $false
                $known = $true
            }
            # Unknown -> no tocar nada.
        }
        catch {
            if (-not $script:AvailabilityLogged) {
                Write-AutoSwitchLog ("WindowsEndpoint no disponible: {0}. Se reintentara." -f $_.Exception.Message)
                $script:AvailabilityLogged = $true
            }
        }
    }
    else {
        # LogitechGHub
        try {
            Connect-GHub
            $batteryPath = Get-ProX2BatteryPath

            if ($script:AvailabilityLogged) {
                Write-AutoSwitchLog "Conexion con G HUB recuperada."
            }
            else {
                Write-AutoSwitchLog "Conectado con G HUB."
            }
            $script:AvailabilityLogged = $false

            $battery = Invoke-GHubGet -Path $batteryPath
            $isOn = $null -ne $battery.payload
            $known = $true
        }
        catch {
            Close-GHubConnection
            if (-not $script:AvailabilityLogged) {
                Write-AutoSwitchLog ((
                    "G HUB/AutoSwitch no disponible: {0}. " +
                    "Se reintentara; mientras el estado sea desconocido no se cambia la salida."
                ) -f $_.Exception.Message)
                $script:AvailabilityLogged = $true
            }
            return
        }
    }

    if (-not $known) {
        return
    }

    # Debounce: solo se decide OFF tras OffMissThreshold lecturas consecutivas.
    $state = Resolve-HeadsetState `
        -PayloadPresent $isOn `
        -Misses $script:Misses `
        -OffMissThreshold ([int]$Config.OffMissThreshold)

    $script:Misses = $state.Misses

    if ($state.Decision -and
        ($null -eq $script:LastState -or $state.IsOn -ne $script:LastState)) {
        $script:AudioOpInProgress = $true
        try {
            if ($state.IsOn) {
                Set-AudioOutput `
                    -DeviceId ([string]$Config.HeadsetId) `
                    -Label ([string]$Config.HeadsetName)
            }
            else {
                Set-AudioOutput `
                    -DeviceId ([string]$Config.SpeakerId) `
                    -Label ([string]$Config.SpeakerName)
            }
            $script:LastState = $state.IsOn
        }
        catch {
            Write-AutoSwitchLog (
                "No se pudo cambiar la salida de audio: {0}. Se reintentara." -f $_.Exception.Message
            )
        }
        finally {
            $script:AudioOpInProgress = $false
        }
    }
}

function Initialize-TrayAndTimer {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application
    $script:TrayIcon.Text = "Audio AutoSwitch"
    $script:TrayIcon.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $script:MenuItemAutoSwitch = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:MenuItemAutoSwitch.Text = "AutoSwitch: Enabled"
    $script:MenuItemAutoSwitch.Checked = $true
    $script:MenuItemAutoSwitch.Add_Click({ Invoke-AutoSwitchToggle })
    [void]$menu.Items.Add($script:MenuItemAutoSwitch)

    $script:MenuItemEnhancements = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:MenuItemEnhancements.Text = "Audio Enhancements..."
    $script:MenuItemEnhancements.Add_Click({ Invoke-EnhancementsToggle })
    [void]$menu.Items.Add($script:MenuItemEnhancements)

    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitItem.Text = "Exit"
    $exitItem.Add_Click({ Stop-Runtime })
    [void]$menu.Items.Add($exitItem)

    $script:TrayIcon.ContextMenuStrip = $menu

    Update-EnhancementsMenu

    $script:PollTimer = New-Object System.Windows.Forms.Timer
    $script:PollTimer.Interval = [int]$Config.PollMilliseconds
    $script:PollTimer.Add_Tick({ Invoke-PollOnce })
    $script:PollTimer.Start()
}

Write-AutoSwitchLog "PRO X 2 AutoSwitch iniciado (modo $script:DetectionMode)."

try {
    Initialize-TrayAndTimer

    if ($Config.DisableEnhancementsOnStart) {
        $action = Get-EnhancementsAction
        if ($action -eq 'Disable') {
            Write-AutoSwitchLog "DisableEnhancementsOnStart esta activo: deshabilitando enhancements del headset."
            Invoke-EnhancementsToggle
        }
    }

    [System.Windows.Forms.Application]::Run()
}
finally {
    try { $script:TrayIcon.Visible = $false } catch {}
    Close-GHubConnection
    try {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    } catch {}
}

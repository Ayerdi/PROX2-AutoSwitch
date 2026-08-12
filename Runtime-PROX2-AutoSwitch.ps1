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
        - Export valido + fila con Item ID coincidente -> estado normalizado.
        - Export valido + fila ausente (endpoint no presente) -> Disconnected.
        - Export invalido/vacio (svcl fallo, basura) -> Unknown (no tocar nada).
    #>
    $csv = Get-SvclCsvExport

    if (-not (Test-SvclExportValid -CsvText $csv)) {
        # svcl no devolvio un export valido: estado desconocido, NO asumir off.
        return 'Unknown'
    }

    $rows = ConvertFrom-SvclCsv -Text $csv

    $row = $rows |
        Where-Object {
            $id = Get-CsvColumn -Row $_ -Names @('Item ID')
            $null -ne $id -and $id.Trim().ToLowerInvariant() -eq [string]$Config.HeadsetId
        } |
        Select-Object -First 1

    if (-not $row) {
        # Export valido pero el endpoint no aparece: para Windows significa
        # que no esta presente -> Disconnected.
        return 'Disconnected'
    }

    $state = Get-CsvColumn -Row $row -Names @('Device State', 'State')
    if ($null -eq $state) {
        return 'Unknown'
    }

    return Resolve-EndpointState -State $state
}

# --- Tray icon + Timer (message pump) + worker process ---
# El polling corre en un proceso PowerShell aparte (worker) para no bloquear
# el hilo de WinForms. El Timer del hilo de UI solo marca estado; el worker
# hace polling con su propio guard anti-concurrencia (no lanza un poll si el
# anterior sigue en marcha).

$script:TrayIcon = $null
$script:MenuItemAutoSwitch = $null
$script:MenuItemEnhancements = $null
$script:MenuTimer = $null

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
# El polling (svcl/G HUB, Set-AudioOutput) corre en un proceso PowerShell
# aparte (AUTOSWITCH_WORKER=1) para no bloquear el hilo de WinForms (tray).
# La comunicacion con el proceso principal es por archivos de control:
#   $ControlDir\enabled.flag   - el tray lo crea/borra (AutoSwitch ON/OFF)
#   $ControlDir\stop.flag      - el tray lo crea al salir
# El propio worker tiene un guard anti-polls-concurrentes: si una lectura
# (p. ej. un /SetDefault lento o G HUB en timeout) se pasa del intervalo,
# no se lanza otro poll hasta que termine.

$script:ControlDir = Join-Path $InstallDir "control"
$script:EnabledFlag = Join-Path $script:ControlDir "enabled.flag"
$script:StopFlag    = Join-Path $script:ControlDir "stop.flag"
$script:WorkerProcess = $null

function Start-Worker {
    # Lanza el mismo script en modo worker (env var). Asi el worker tiene
    # acceso a TODAS las funciones (G HUB, audio, endpoint) sin duplicarlas.
    try { New-Item -ItemType Directory -Path $script:ControlDir -Force | Out-Null } catch {}

    # Estado inicial: AutoSwitch ON.
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
            if (-not $script:WorkerProcess.HasExited) {
                $script:WorkerProcess.Kill()
            }
            $script:WorkerProcess.Dispose()
        }
    } catch {}
}

# --- Bucle del worker (solo cuando AUTOSWITCH_WORKER=1) ---
# Se ejecuta al final del script; las funciones G HUB/audio/endpoint ya estan
# definidas arriba porque es el mismo script.

function Start-WorkerLoop {
    $controlDir = $env:AUTOSWITCH_CONTROL
    $enabledFlag = Join-Path $controlDir "enabled.flag"
    $stopFlag    = Join-Path $controlDir "stop.flag"

    $lastState = $null
    $misses = 0
    $availabilityLogged = $false
    $script:WorkerBatteryPath = $null

    Write-AutoSwitchLog "Worker iniciado (modo $script:DetectionMode)."

    while (-not (Test-Path $stopFlag)) {
        $enabled = Test-Path $enabledFlag
        if (-not $enabled) {
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
                # Unknown -> no tocar nada.
            }
            catch {
                if (-not $availabilityLogged) {
                    Write-AutoSwitchLog ("WindowsEndpoint no disponible: {0}. Se reintentara." -f $_.Exception.Message)
                    $availabilityLogged = $true
                }
            }
        }
        else {
            # LogitechGHub: conexion PERSISTENTE. Se conecta una vez, se resuelve
            # el batteryPath una vez, y solo se reconecta (re-resolviendo el
            # deviceId, que puede cambiar tras una reconexion) si algo falla.
            try {
                if (-not $script:WorkerBatteryPath) {
                    Connect-GHub
                    $script:WorkerBatteryPath = Get-ProX2BatteryPath

                    if ($availabilityLogged) {
                        Write-AutoSwitchLog "Conexion con G HUB recuperada."
                    }
                    else {
                        Write-AutoSwitchLog "Conectado con G HUB."
                    }
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
            # Debounce: solo se decide OFF tras OffMissThreshold lecturas.
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
                catch {
                    Write-AutoSwitchLog ("No se pudo cambiar la salida de audio: {0}. Se reintentara." -f $_.Exception.Message)
                }
            }
        }

        Start-Sleep -Milliseconds ([int]$Config.PollMilliseconds)
    }

    Close-GHubConnection
    Write-AutoSwitchLog "Worker detenido."
}

function Initialize-TrayAndTimer {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon

    # Icono propio de la app (icono de auricular azul). Si el .ico no existe
    # en disco, caemos a SystemIcons.Application para que siempre haya uno.
    try {
        $iconFile = Join-Path $InstallDir "icon.ico"
        if (Test-Path $iconFile) {
            $script:TrayIcon.Icon = [System.Drawing.Icon]::new($iconFile)
        }
        else {
            $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application
        }
    }
    catch {
        $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application
    }

    $script:TrayIcon.Text = "Audio AutoSwitch"
    $script:TrayIcon.Visible = $true

    # Form invisible que sostiene el message pump de WinForms. Application.Run()
    # sin Form no siempre mantiene el NotifyIcon visible activo en todos los
    # builds de .NET; con un Form oculto el pump es robusto y la bandeja no se cae.
    $script:MainForm = New-Object System.Windows.Forms.Form
    $script:MainForm.WindowState = 'Minimized'
    $script:MainForm.ShowInTaskbar = $false
    $script:MainForm.Visible = $false
    $script:MainForm.FormBorderStyle = 'None'

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

    # Refresca el texto del menu de enhancements periodicamente (el estado
    # SysFx puede cambiar desde el instalador o un helper externo). Se actualiza
    # en el hilo de UI; Get-EndpointFxState es una lectura COM ligera.
    $script:MenuTimer = New-Object System.Windows.Forms.Timer
    $script:MenuTimer.Interval = 5000
    $script:MenuTimer.Add_Tick({
        Update-EnhancementsMenu
    })
    $script:MenuTimer.Start()

    Update-EnhancementsMenu
    Write-AutoSwitchLog "Tray configurada; message pump activo."
}

Write-AutoSwitchLog "PRO X 2 AutoSwitch iniciado (modo $script:DetectionMode)."

if ($env:AUTOSWITCH_WORKER -eq '1') {
    # Modo worker: solo el bucle de polling. No toca la bandeja.
    Start-WorkerLoop
    exit 0
}

try {
    Start-Worker
    Initialize-TrayAndTimer

    if ($Config.DisableEnhancementsOnStart) {
        $action = Get-EnhancementsAction
        if ($action -eq 'Disable') {
            Write-AutoSwitchLog "DisableEnhancementsOnStart esta activo: deshabilitando enhancements del headset."
            Invoke-EnhancementsToggle
        }
    }

    # Message pump principal sostenido por un Form invisible. La bandeja de
    # notificaciones procesa eventos aqui; se mantiene activa hasta Exit.
    [System.Windows.Forms.Application]::Run($script:MainForm)
    Write-AutoSwitchLog "Message pump finalizado (Exit)."
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

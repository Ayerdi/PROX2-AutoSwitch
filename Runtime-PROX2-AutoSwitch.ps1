#requires -Version 5.1
$ErrorActionPreference = "Stop"

$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $InstallDir "config.json"
$SvclPath   = Join-Path $InstallDir "svcl.exe"
$LogPath    = Join-Path $InstallDir "autoswitch.log"

if (-not (Test-Path $ConfigPath)) { exit 10 }
if (-not (Test-Path $SvclPath))   { exit 11 }

$Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json

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

# Impide dos instancias del runtime para el mismo usuario.
$createdNew = $false
$mutexName = "Local\PROX2AutoSwitch_" + [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
    exit 0
}

$script:Ws  = $null
$script:Cts = $null

function Close-GHubConnection {
    try {
        if ($null -ne $script:Ws -and
            $script:Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $script:Ws.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "reconnect",
                $script:Cts.Token
            ).GetAwaiter().GetResult() | Out-Null
        }
    } catch {}

    try {
        if ($null -ne $script:Ws) { $script:Ws.Dispose() }
    } catch {}

    try {
        if ($null -ne $script:Cts) { $script:Cts.Dispose() }
    } catch {}

    $script:Ws  = $null
    $script:Cts = $null
}

function Connect-GHub {
    Close-GHubConnection

    $script:Ws  = New-Object System.Net.WebSockets.ClientWebSocket
    $script:Cts = New-Object System.Threading.CancellationTokenSource

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
    $script:Ws.ConnectAsync($uri, $script:Cts.Token).GetAwaiter().GetResult() | Out-Null

    if ($script:Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "No se pudo conectar con Logitech G HUB."
    }
}

function Send-GHubJson {
    param([Parameter(Mandatory=$true)][object]$Object)

    $json = $Object | ConvertTo-Json -Compress -Depth 20
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (,$bytes)

    $script:Ws.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        $script:Cts.Token
    ).GetAwaiter().GetResult() | Out-Null
}

function Receive-GHubText {
    $buffer = New-Object byte[] 16384
    $stream = New-Object System.IO.MemoryStream

    try {
        do {
            $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (,$buffer)
            $result = $script:Ws.ReceiveAsync(
                $segment,
                $script:Cts.Token
            ).GetAwaiter().GetResult()

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

    while ($true) {
        $raw = Receive-GHubText

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

    $m = [regex]::Match(
        $text,
        '\{0\.0\.0\.00000000\}\.\{[0-9A-Fa-f-]+\}'
    )

    if (-not $m.Success) {
        throw "No se pudo leer el Item ID del dispositivo predeterminado. Salida: $text"
    }

    return $m.Value.ToLowerInvariant()
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

Write-AutoSwitchLog "PRO X 2 AutoSwitch iniciado."

$availabilityLogged = $false

try {
    while ($true) {
        try {
            Connect-GHub
            $batteryPath = Get-ProX2BatteryPath

            if ($availabilityLogged) {
                Write-AutoSwitchLog "Conexion con G HUB recuperada."
            } else {
                Write-AutoSwitchLog "Conectado con G HUB."
            }

            $availabilityLogged = $false
            $lastState = $null
            $misses = 0

            while ($script:Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                $battery = Invoke-GHubGet -Path $batteryPath

                if ($null -ne $battery.payload) {
                    $misses = 0
                    $isOn = $true
                }
                else {
                    $misses++

                    if ($misses -lt [int]$Config.OffMissThreshold) {
                        Start-Sleep -Milliseconds ([int]$Config.PollMilliseconds)
                        continue
                    }

                    $isOn = $false
                }

                if ($null -eq $lastState -or $isOn -ne $lastState) {
                    if ($isOn) {
                        Set-AudioOutput `
                            -DeviceId ([string]$Config.HeadsetId) `
                            -Label ([string]$Config.HeadsetName)
                    }
                    else {
                        Set-AudioOutput `
                            -DeviceId ([string]$Config.SpeakerId) `
                            -Label ([string]$Config.SpeakerName)
                    }

                    $lastState = $isOn
                }

                Start-Sleep -Milliseconds ([int]$Config.PollMilliseconds)
            }

            throw "Se perdio la conexion con G HUB."
        }
        catch {
            Close-GHubConnection

            if (-not $availabilityLogged) {
                Write-AutoSwitchLog ((
                    "G HUB/AutoSwitch no disponible: {0}. " +
                    "Se reintentara; mientras el estado sea desconocido no se cambia la salida."
                ) -f $_.Exception.Message)
                $availabilityLogged = $true
            }

            Start-Sleep -Seconds 5
        }
    }
}
finally {
    Close-GHubConnection
    try {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    } catch {}
}

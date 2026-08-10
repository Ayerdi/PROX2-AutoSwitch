#requires -Version 5.1
$ErrorActionPreference = "Stop"

# PowerShell 5.1 sobre .NET antiguo puede negociar TLS 1.0/1.1 y fallar
# contra GitHub/NirSoft. Forzamos TLS 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PackageDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir   = Join-Path $env:LOCALAPPDATA "PROX2AutoSwitch"
$RuntimeSrc   = Join-Path $PackageDir "Runtime-PROX2-AutoSwitch.ps1"
$UninstallSrc = Join-Path $PackageDir "Desinstalar-PROX2-AutoSwitch.ps1"
$VerifySrc    = Join-Path $PackageDir "Verificar-PROX2-AutoSwitch.ps1"
$ModuleSrc    = Join-Path $PackageDir "lib\AutoSwitchCore.psm1"
$HelperSrc    = Join-Path $PackageDir "Toggle-AudioEnhancements.ps1"

$MainScript   = Join-Path $InstallDir "PROX2AutoSwitch.ps1"
$ConfigPath   = Join-Path $InstallDir "config.json"
$SvclPath     = Join-Path $InstallDir "svcl.exe"
$LauncherVbs  = Join-Path $InstallDir "Iniciar-Oculto.vbs"
$LogPath      = Join-Path $InstallDir "autoswitch.log"
$HelperPath   = Join-Path $InstallDir "Toggle-AudioEnhancements.ps1"

$StartupDir   = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "PRO X 2 AutoSwitch.lnk"

$SvclUrl = "https://www.nirsoft.net/utils/svcl-x64.zip"
# Verificado en la pagina oficial de hashes de NirSoft el 2026-08-07.
# Si NirSoft actualiza svcl, este hash cambiara: NO desactives la verificacion.
$ExpectedSha256 = "7ba008e9ece8b3eda323ef01711e4647eb7f40b28dc25f98b2ed6a738810bfcd"
$ZipPath = Join-Path $env:TEMP "svcl-x64.zip"

foreach ($required in @($RuntimeSrc, $UninstallSrc, $VerifySrc, $ModuleSrc, $HelperSrc)) {
    if (-not (Test-Path $required)) {
        throw "Falta un fichero del paquete: $required. Extrae el ZIP completo antes de instalar."
    }
}

# Logica compartida (extraccion de Item ID, validacion de config, debounce).
Import-Module $ModuleSrc -ErrorAction Stop

if (-not [Environment]::Is64BitOperatingSystem) {
    throw "Este paquete esta preparado para Windows x64."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PRO X 2 LIGHTSPEED - AutoSwitch de audio" -ForegroundColor Cyan
Write-Host " Instalacion limpia" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Parar una instalacion anterior, si existe.
$escapedMain = [regex]::Escape($MainScript)
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -match $escapedMain
    } |
    ForEach-Object {
        Write-Host "Deteniendo instancia anterior (PID $($_.ProcessId))..." -ForegroundColor DarkGray
        Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null
    }

Start-Sleep -Milliseconds 500

Write-Host "[1/7] Descargando SoundVolumeCommandLine desde NirSoft..." -ForegroundColor Yellow
Invoke-WebRequest -UseBasicParsing -Uri $SvclUrl -OutFile $ZipPath

$ActualSha256 = (Get-FileHash -Algorithm SHA256 -Path $ZipPath).Hash.ToLowerInvariant()
if ($ActualSha256 -ne $ExpectedSha256) {
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    throw @"
El SHA-256 de svcl-x64.zip no coincide con el verificado al crear este paquete.

Esperado: $ExpectedSha256
Obtenido: $ActualSha256

Esto puede significar que NirSoft ha publicado una version nueva.
No continues desactivando la comprobacion. Verifica el SHA-256 actual en:
https://www.nirsoft.net/hash_check/?software=svcl
y actualiza ExpectedSha256 en este instalador.
"@
}

Write-Host "      SHA-256 correcto." -ForegroundColor Green

Write-Host "[2/7] Instalando SoundVolumeCommandLine..." -ForegroundColor Yellow
Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force
Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $SvclPath)) {
    throw "No se encontro svcl.exe despues de extraer el ZIP."
}

# Copiamos la version fuente del runtime y utilidades.
Copy-Item $RuntimeSrc $MainScript -Force
Copy-Item $UninstallSrc (Join-Path $InstallDir "Desinstalar-PROX2-AutoSwitch.ps1") -Force
Copy-Item $VerifySrc (Join-Path $InstallDir "Verificar-PROX2-AutoSwitch.ps1") -Force
Copy-Item $HelperSrc (Join-Path $InstallDir "Toggle-AudioEnhancements.ps1") -Force
New-Item -ItemType Directory -Path (Join-Path $InstallDir "lib") -Force | Out-Null
Copy-Item $ModuleSrc (Join-Path $InstallDir "lib\AutoSwitchCore.psm1") -Force

# --- Funciones G HUB para la instalacion ---
$script:Ws  = $null

# Timeouts de G HUB (ms): la comprobacion de G HUB del asistente no puede
# colgarse si G HUB acepta la conexion y deja de responder.
$script:ConnectTimeoutMs = 5000
$script:ReceiveTimeoutMs = 5000
$script:RequestTimeoutMs = 10000

# Token de timeout G HUB: definido en lib\AutoSwitchCore.psm1 (importado arriba).

function Close-GHubConnection {
    # El cierre no debe colgar el asistente: si CloseAsync no termina en 1 s
    # (o falla), Abort() + Dispose() garantizan salida.
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
        throw "Timeout al conectar con G HUB ($($script:ConnectTimeoutMs) ms)."
    }
    finally {
        $timeout.Dispose()
    }

    if ($script:Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "No se pudo abrir ws://localhost:9010."
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
        try { $message = $raw | ConvertFrom-Json } catch { continue }

        if (($message.msgId -eq $msgId) -or ($message.path -eq $Path)) {
            return $message
        }
    }
}

# --- Funciones de audio ---
function Get-DefaultColumn {
    param([Parameter(Mandatory=$true)][string]$Column)

    # IMPORTANTE: no usar /Stdout con /GetColumnValue.
    $raw = & $SvclPath /GetColumnValue "DefaultRenderDevice" $Column 2>&1
    return (($raw | Out-String).Trim())
}

function Get-DefaultRenderItemId {
    $text = Get-DefaultColumn "Item ID"

    $id = Get-RenderItemIdFromText -Text $text
    if (-not $id) {
        throw "No pude extraer el Item ID del dispositivo predeterminado. Salida: $text"
    }

    return $id
}

function Get-DefaultRenderName {
    $text = Get-DefaultColumn "Name"
    $lines = @($text -split "(`r`n|`n|`r)") |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" }

    if ($lines.Count -eq 0) { return "<desconocido>" }
    return $lines[-1]
}

function Capture-DefaultOutput {
    param([Parameter(Mandatory=$true)][string]$PromptText)

    Write-Host ""
    Write-Host $PromptText -ForegroundColor Cyan
    [void](Read-Host "Cuando sea la salida predeterminada de Windows, pulsa ENTER")

    $name = Get-DefaultRenderName
    $id   = Get-DefaultRenderItemId

    Write-Host "      Capturado: $name" -ForegroundColor Green
    Write-Host "      Item ID:   $id" -ForegroundColor DarkGray

    return [pscustomobject]@{
        Name   = $name
        ItemId = $id
    }
}

function Test-SetDefault {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Label
    )

    Write-Host ""
    Write-Host "Probando cambio real -> $Label" -ForegroundColor Yellow

    $out = & $SvclPath /Stdout /SetDefault $Id all 2>&1
    $text = ($out | Out-String).Trim()

    if ($text -match "No items found") {
        Write-Host $text -ForegroundColor Red
        return $false
    }

    Start-Sleep -Milliseconds 800
    $actual = Get-DefaultRenderItemId

    if ($actual -ieq $Id) {
        Write-Host "      PRUEBA OK" -ForegroundColor Green
        return $true
    }

    Write-Host "      PRUEBA FALLIDA. Actual: $actual" -ForegroundColor Red
    return $false
}

try {
    # --- Deteccion del modo ---
    # Intentamos primero el modo Logitech G HUB (PRO X 2 y otros Logitech);
    # si no hay G HUB o no aparece un PRO X 2, pasamos al modo universal
    # WindowsEndpoint (lista de endpoints de Windows).
    $DetectionMode = $null
    $ghubHeadset = $null

    Write-Host "[3/7] Detectando el auricular..." -ForegroundColor Yellow

    try {
        Connect-GHub
        $devices = Invoke-GHubGet -Path "/devices/list"
        $deviceInfos = @($devices.payload.deviceInfos)

        $candidates = @($deviceInfos | Where-Object {
            $_.extendedDisplayName -match "PRO\s*X\s*2"
        })

        if ($candidates.Count -gt 0) {
            if ($candidates.Count -eq 1) {
                $ghubHeadset = $candidates[0]
            }
            else {
                Write-Host ""
                Write-Host "Se encontraron varios candidatos:" -ForegroundColor Yellow
                for ($i = 0; $i -lt $candidates.Count; $i++) {
                    Write-Host "[$($i + 1)] $($candidates[$i].extendedDisplayName)"
                }

                do {
                    $choice = Read-Host "Elige el numero del PRO X 2"
                    $parsed = 0
                    $valid = [int]::TryParse($choice, [ref]$parsed) -and
                             $parsed -ge 1 -and
                             $parsed -le $candidates.Count
                } until ($valid)

                $ghubHeadset = $candidates[$parsed - 1]
            }

            Write-Host "      G HUB: $($ghubHeadset.extendedDisplayName)" -ForegroundColor Green
            $DetectionMode = "LogitechGHub"
        }
    }
    catch {
        # G HUB no disponible o sin PRO X 2: se ignora y seguimos con WindowsEndpoint.
        Write-Host "      G HUB no disponible o sin PRO X 2; probando deteccion universal..." -ForegroundColor DarkGray
    }

    if (-not $DetectionMode) {
        # --- Modo universal: elegir headset y fallback desde la lista de endpoints ---
        Write-Host "      Usando la lista de dispositivos de audio de Windows..." -ForegroundColor DarkGray

        $csvText = (& $SvclPath /scomma "" 2>&1 | Out-String).Trim()
        $rows = @(ConvertFrom-SvclCsv -Text $csvText)
        if ($rows.Count -eq 0) {
            throw "No se pudo leer la lista de dispositivos de audio de Windows (svcl /scomma)."
        }

        $renderRows = @($rows | Where-Object {
            $def = Get-CsvColumn -Row $_ -Names @('Default')
            ($null -eq $def) -or ($def -match 'Render')
        })
        if ($renderRows.Count -eq 0) { $renderRows = $rows }

        Write-Host ""
        Write-Host "Dispositivos de salida detectados:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $renderRows.Count; $i++) {
            $name = Get-CsvColumn -Row $renderRows[$i] -Names @('Name', 'DeviceName')
            Write-Host ("  [{0}] {1}" -f ($i + 1), $name)
        }

        $chosenHeadset = $null
        do {
            $choice = Read-Host "Elige el numero del AURICULAR (headset)"
            $parsed = 0
            $valid = [int]::TryParse($choice, [ref]$parsed) -and
                     $parsed -ge 1 -and
                     $parsed -le $renderRows.Count
        } until ($valid)
        $chosenHeadset = $renderRows[$parsed - 1]

        $chosenSpeaker = $null
        do {
            $choice = Read-Host "Elige el numero del dispositivo de FALLBACK (altavoces)"
            $parsed = 0
            $valid = [int]::TryParse($choice, [ref]$parsed) -and
                     $parsed -ge 1 -and
                     $parsed -le $renderRows.Count
        } until ($valid)
        $chosenSpeaker = $renderRows[$parsed - 1]

        $headsetId = Get-CsvColumn -Row $chosenHeadset -Names @('Item ID')
        $speakerId = Get-CsvColumn -Row $chosenSpeaker -Names @('Item ID')

        if (-not (Test-ValidAudioConfig -HeadsetId $headsetId -SpeakerId $speakerId)) {
            throw "Has elegido el mismo dispositivo para headset y fallback. Repite la instalacion."
        }

        $headsetName = Get-CsvColumn -Row $chosenHeadset -Names @('Name', 'DeviceName')
        $speakerName = Get-CsvColumn -Row $chosenSpeaker -Names @('Name', 'DeviceName')

        # Auto-detectar si Windows refleja el estado fisico del headset.
        $before = Get-CsvColumn -Row $chosenHeadset -Names @('State', 'DeviceState')
        Write-Host ""
        Write-Host "Apaga el auricular y pulsa ENTER para comprobar si Windows detecta el cambio..." -ForegroundColor Cyan
        [void](Read-Host)
        $csvText2 = (& $SvclPath /scomma "" 2>&1 | Out-String).Trim()
        $rows2 = @(ConvertFrom-SvclCsv -Text $csvText2)
        $afterRow = $rows2 | Where-Object {
            $id = Get-CsvColumn -Row $_ -Names @('Item ID')
            $null -ne $id -and $id -eq $headsetId
        } | Select-Object -First 1
        $after = if ($afterRow) { Get-CsvColumn -Row $afterRow -Names @('State', 'DeviceState') } else { $null }

        $beforeState = Resolve-EndpointState -State $before
        $afterState  = if ($null -eq $after) { 'Disconnected' } else { Resolve-EndpointState -State $after }

        if ($beforeState -eq 'Connected' -and $afterState -eq 'Disconnected') {
            $DetectionMode = "WindowsEndpoint"
            Write-Host "      Windows refleja el estado fisico (Active -> Unplugged): modo universal." -ForegroundColor Green
        }
        else {
            Write-Host "      Windows NO refleja el estado fisico de este auricular." -ForegroundColor DarkGray
            # Fallback a G HUB solo si es un Logitech y G HUB responde.
            try {
                Connect-GHub
                $devices = Invoke-GHubGet -Path "/devices/list"
                $deviceInfos = @($devices.payload.deviceInfos)
                $logi = @($deviceInfos | Where-Object { $_.extendedDisplayName -match "Logitech|PRO\s*X" })
                if ($logi.Count -gt 0) {
                    $ghubHeadset = $logi[0]
                    $DetectionMode = "LogitechGHub"
                    Write-Host "      Detectado Logitech con G HUB: modo G HUB." -ForegroundColor Green
                }
            }
            catch { }
        }

        if (-not $DetectionMode) {
            throw "Windows no puede detectar el estado fisico de este auricular y no hay metodo compatible (ni G HUB). No se instalara."
        }
    }

    Write-Host ""
    Write-Host "[4/7] Calibrando salidas de Windows..." -ForegroundColor Yellow
    Write-Host "No se guardan IDs antiguos: se capturan los del Windows actual." -ForegroundColor DarkGray

    if ($DetectionMode -eq 'LogitechGHub') {
        # Flujo PRO X 2 original: captura manual del headset y del fallback.
        $headsetOutput = Capture-DefaultOutput @"
PASO A - AURICULARES
Enciende los PRO X 2 y selecciona manualmente en Windows la salida de los auriculares.
"@

        $speakerOutput = Capture-DefaultOutput @"
PASO B - ALTAVOCES
Selecciona manualmente en Windows la salida que quieres usar cuando los PRO X 2 esten apagados.
"@

        if (-not (Test-ValidAudioConfig -HeadsetId $headsetOutput.ItemId -SpeakerId $speakerOutput.ItemId)) {
            throw "Has capturado el mismo dispositivo dos veces. Repite la instalacion."
        }
    }
    else {
        # Modo universal: ya capturamos los IDs de la lista de Windows.
        $headsetOutput = [pscustomobject]@{
            Name   = $headsetName
            ItemId = $headsetId
        }
        $speakerOutput = [pscustomobject]@{
            Name   = $speakerName
            ItemId = $speakerId
        }
    }

    Write-Host ""
    Write-Host "[5/7] Validando cambios de audio antes de instalar..." -ForegroundColor Yellow

    $okHeadset = Test-SetDefault `
        -Id $headsetOutput.ItemId `
        -Label $headsetOutput.Name

    $okSpeaker = Test-SetDefault `
        -Id $speakerOutput.ItemId `
        -Label $speakerOutput.Name

    if (-not ($okHeadset -and $okSpeaker)) {
        throw "Una de las pruebas reales de cambio de salida ha fallado. No se instalara el AutoSwitch."
    }

    $config = [ordered]@{
        Version                = "1.2.0"
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

    # Campos especificos del modo G HUB.
    if ($DetectionMode -eq 'LogitechGHub' -and $ghubHeadset) {
        $config['GHubDisplayName'] = [string]$ghubHeadset.extendedDisplayName
        $config['GHubPort']        = 9010
    }

    # Preguntar si se quieren deshabilitar los audio enhancements del headset
    # ahora (requiere elevacion puntual via UAC).
    Write-Host ""
    Write-Host "Audio Enhancements de Windows:" -ForegroundColor Yellow
    $enhChoice = Read-Host "Quieres deshabilitar los audio enhancements del headset? (s/N)"
    if ($enhChoice -match '^(s|si|sí|y|yes)$') {
        $config['EnhancementsDeviceId'] = [string]$headsetOutput.ItemId
        $config['DisableEnhancementsOnStart'] = $true
        Write-Host "      Se deshabilitaran (puede aparecer una ventana de UAC)..." -ForegroundColor DarkGray
    }

    $config | ConvertTo-Json -Depth 10 |
        Set-Content -Path $ConfigPath -Encoding UTF8

    if ($config['DisableEnhancementsOnStart']) {
        try {
            $helper = Join-Path $InstallDir "Toggle-AudioEnhancements.ps1"
            $proc = Start-Process -FilePath (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$helper`" -DeviceId `"$($config['HeadsetId'])`" -Action Disable" `
                -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
            $proc.WaitForExit()
            if ($proc.ExitCode -eq 0) {
                Write-Host "      Enhancements deshabilitados y verificados." -ForegroundColor Green
            }
            else {
                Write-Warning "El helper de enhancements no confirmo el cambio (codigo $($proc.ExitCode))."
            }
        }
        catch {
            Write-Warning "No se pudieron deshabilitar los enhancements ahora (UAC cancelado o error): $($_.Exception.Message)"
            Write-Host "      Puedes hacerlo luego desde el icono de bandeja." -ForegroundColor DarkGray
        }
    }

    Write-Host "[6/7] Configurando inicio invisible..." -ForegroundColor Yellow

    $PowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $WScriptExe    = Join-Path $env:SystemRoot "System32\wscript.exe"

    if (-not (Test-Path $WScriptExe)) {
        throw "No se encuentra wscript.exe. Este instalador usa WScript para evitar una ventana de PowerShell al iniciar sesion."
    }

    $vbs = @"
Set shell = CreateObject("WScript.Shell")
cmd = Chr(34) & "$PowerShellExe" & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & "$MainScript" & Chr(34)
shell.Run cmd, 0, False
Set shell = Nothing
"@

    Set-Content -Path $LauncherVbs -Value $vbs -Encoding ASCII

    # El acceso directo inicia wscript.exe, no PowerShell directamente.
    # Asi no queda una consola visible al iniciar sesion.
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $WScriptExe
    $Shortcut.Arguments = "`"$LauncherVbs`""
    $Shortcut.WorkingDirectory = $InstallDir
    $Shortcut.IconLocation = "$env:SystemRoot\System32\SndVol.exe,0"
    $Shortcut.Description = "PRO X 2 AutoSwitch - inicio invisible"
    $Shortcut.Save()

    # Arrancar ahora oculto.
    Start-Process -FilePath $WScriptExe -ArgumentList "`"$LauncherVbs`"" -WindowStyle Hidden
    Start-Sleep -Seconds 2

    $running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match $escapedMain } |
        Select-Object -First 1

    Write-Host "[7/7] Finalizando..." -ForegroundColor Yellow
    Write-Host ""

    if ($running) {
        Write-Host "INSTALACION COMPLETADA." -ForegroundColor Green
        Write-Host "AutoSwitch ejecutandose en segundo plano (PID $($running.ProcessId))." -ForegroundColor Green
    }
    else {
        Write-Warning "La instalacion termino, pero no pude confirmar el proceso oculto."
        Write-Host "Ejecuta el verificador incluido en el paquete."
    }

    Write-Host ""
    Write-Host "Auriculares ON  -> $($headsetOutput.Name)"
    Write-Host "Auriculares OFF -> $($speakerOutput.Name)"
    Write-Host ""
    Write-Host "Instalado en: $InstallDir" -ForegroundColor DarkGray
    Write-Host "Log:          $LogPath" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Prueba ahora a encender y apagar los PRO X 2." -ForegroundColor Cyan
}
finally {
    Close-GHubConnection
}

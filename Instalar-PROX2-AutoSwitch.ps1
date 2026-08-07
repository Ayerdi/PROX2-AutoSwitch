#requires -Version 5.1
$ErrorActionPreference = "Stop"

$PackageDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir   = Join-Path $env:LOCALAPPDATA "PROX2AutoSwitch"
$RuntimeSrc   = Join-Path $PackageDir "Runtime-PROX2-AutoSwitch.ps1"
$UninstallSrc = Join-Path $PackageDir "Desinstalar-PROX2-AutoSwitch.ps1"
$VerifySrc    = Join-Path $PackageDir "Verificar-PROX2-AutoSwitch.ps1"

$MainScript   = Join-Path $InstallDir "PROX2AutoSwitch.ps1"
$ConfigPath   = Join-Path $InstallDir "config.json"
$SvclPath     = Join-Path $InstallDir "svcl.exe"
$LauncherVbs  = Join-Path $InstallDir "Iniciar-Oculto.vbs"
$LogPath      = Join-Path $InstallDir "autoswitch.log"

$StartupDir   = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "PRO X 2 AutoSwitch.lnk"

$SvclUrl = "https://www.nirsoft.net/utils/svcl-x64.zip"
# Verificado en la pagina oficial de hashes de NirSoft el 2026-08-07.
# Si NirSoft actualiza svcl, este hash cambiara: NO desactives la verificacion.
$ExpectedSha256 = "7ba008e9ece8b3eda323ef01711e4647eb7f40b28dc25f98b2ed6a738810bfcd"
$ZipPath = Join-Path $env:TEMP "svcl-x64.zip"

foreach ($required in @($RuntimeSrc, $UninstallSrc, $VerifySrc)) {
    if (-not (Test-Path $required)) {
        throw "Falta un fichero del paquete: $required. Extrae el ZIP completo antes de instalar."
    }
}

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

# --- Funciones G HUB para la instalacion ---
$script:Ws  = $null
$script:Cts = $null

function Close-GHubConnection {
    try {
        if ($null -ne $script:Ws -and
            $script:Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $script:Ws.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "fin",
                $script:Cts.Token
            ).GetAwaiter().GetResult() | Out-Null
        }
    } catch {}

    try { if ($null -ne $script:Ws)  { $script:Ws.Dispose() } } catch {}
    try { if ($null -ne $script:Cts) { $script:Cts.Dispose() } } catch {}

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

    $uri = New-Object System.Uri("ws://localhost:9010")
    $script:Ws.ConnectAsync($uri, $script:Cts.Token).GetAwaiter().GetResult() | Out-Null

    if ($script:Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "No se pudo abrir ws://localhost:9010."
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

    $m = [regex]::Match(
        $text,
        '\{0\.0\.0\.00000000\}\.\{[0-9A-Fa-f-]+\}'
    )

    if (-not $m.Success) {
        throw "No pude extraer el Item ID del dispositivo predeterminado. Salida: $text"
    }

    return $m.Value.ToLowerInvariant()
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
    Write-Host "[3/7] Comprobando Logitech G HUB..." -ForegroundColor Yellow
    try {
        Connect-GHub
    }
    catch {
        throw "No puedo conectar con Logitech G HUB en localhost:9010. Abre G HUB y vuelve a ejecutar el instalador. Detalle: $($_.Exception.Message)"
    }

    $devices = Invoke-GHubGet -Path "/devices/list"
    $deviceInfos = @($devices.payload.deviceInfos)

    if ($deviceInfos.Count -eq 0) {
        throw "G HUB no devolvio dispositivos."
    }

    $matches = @($deviceInfos | Where-Object {
        $_.extendedDisplayName -match "PRO\s*X\s*2"
    })

    if ($matches.Count -eq 0) {
        Write-Host ""
        Write-Host "G HUB devuelve estos dispositivos:" -ForegroundColor Yellow
        $deviceInfos |
            Select-Object id, extendedDisplayName, deviceType |
            Format-Table -AutoSize

        throw "No se encontro automaticamente un Logitech PRO X 2."
    }

    if ($matches.Count -eq 1) {
        $ghubHeadset = $matches[0]
    }
    else {
        Write-Host ""
        Write-Host "Se encontraron varios candidatos:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $matches.Count; $i++) {
            Write-Host "[$($i + 1)] $($matches[$i].extendedDisplayName)"
        }

        do {
            $choice = Read-Host "Elige el numero del PRO X 2"
            $parsed = 0
            $valid = [int]::TryParse($choice, [ref]$parsed) -and
                     $parsed -ge 1 -and
                     $parsed -le $matches.Count
        } until ($valid)

        $ghubHeadset = $matches[$parsed - 1]
    }

    Write-Host "      G HUB: $($ghubHeadset.extendedDisplayName)" -ForegroundColor Green

    Write-Host ""
    Write-Host "[4/7] Calibrando salidas de Windows..." -ForegroundColor Yellow
    Write-Host "No se guardan IDs antiguos: se capturan los del Windows actual." -ForegroundColor DarkGray

    $headsetOutput = Capture-DefaultOutput @"
PASO A - AURICULARES
Enciende los PRO X 2 y selecciona manualmente en Windows la salida de los auriculares.
"@

    $speakerOutput = Capture-DefaultOutput @"
PASO B - ALTAVOCES
Selecciona manualmente en Windows la salida que quieres usar cuando los PRO X 2 esten apagados.
"@

    if ($headsetOutput.ItemId -ieq $speakerOutput.ItemId) {
        throw "Has capturado el mismo dispositivo dos veces. Repite la instalacion."
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
        Version          = "1.0.0"
        GHubDisplayName  = [string]$ghubHeadset.extendedDisplayName
        GHubPort         = 9010
        HeadsetName      = [string]$headsetOutput.Name
        HeadsetId        = [string]$headsetOutput.ItemId
        SpeakerName      = [string]$speakerOutput.Name
        SpeakerId        = [string]$speakerOutput.ItemId
        PollMilliseconds = 1500
        OffMissThreshold = 2
        InstalledAt      = (Get-Date).ToString("o")
    }

    $config | ConvertTo-Json -Depth 10 |
        Set-Content -Path $ConfigPath -Encoding UTF8

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

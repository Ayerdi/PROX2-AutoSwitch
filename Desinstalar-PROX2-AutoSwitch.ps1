#requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

$InstallDir   = Join-Path $env:LOCALAPPDATA "PROX2AutoSwitch"
$MainScript   = Join-Path $InstallDir "PROX2AutoSwitch.ps1"
$StartupDir   = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "PRO X 2 AutoSwitch.lnk"

Write-Host ""
Write-Host "=== Desinstalar PRO X 2 AutoSwitch ===" -ForegroundColor Cyan
Write-Host ""

$failed = $false
$removedSomething = $false

function Show-Test {
    param([string]$Label, [bool]$Ok, [string]$Detail)

    if ($Ok) {
        Write-Host "[OK]    $Label" -ForegroundColor Green
    }
    else {
        Write-Host "[FALLO] $Label" -ForegroundColor Red
    }

    if ($Detail) {
        Write-Host "        $Detail" -ForegroundColor DarkGray
    }
}

# 1. Inicio automatico.
$hadShortcut = Test-Path $ShortcutPath
Remove-Item $ShortcutPath -Force -ErrorAction SilentlyContinue
if ($hadShortcut -and -not (Test-Path $ShortcutPath)) {
    $removedSomething = $true
    Show-Test "Inicio automatico" $true "acceso directo eliminado"
}
elseif (-not $hadShortcut) {
    Show-Test "Inicio automatico" $true "no existia (nada que quitar)"
}
else {
    $failed = $true
    Show-Test "Inicio automatico" $false "no se pudo eliminar: $ShortcutPath"
}

# 2. Proceso del runtime.
$matched = @()
if (Test-Path $MainScript) {
    $escaped = [regex]::Escape($MainScript)

    $matched = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessId -ne $PID -and
                $_.CommandLine -match $escaped
            }
    )

    foreach ($proc in $matched) {
        Invoke-CimMethod -InputObject $proc -MethodName Terminate | Out-Null
    }
}

Start-Sleep -Milliseconds 600

$stillRunning = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -match [regex]::Escape($MainScript)
    } |
    Select-Object -First 1

if ($matched.Count -gt 0) {
    if ($stillRunning) {
        $failed = $true
        Show-Test "Proceso AutoSwitch" $false "sigue en ejecucion (PID $($stillRunning.ProcessId))"
    }
    else {
        $removedSomething = $true
        Show-Test "Proceso AutoSwitch" $true "detenido"
    }
}
else {
    Show-Test "Proceso AutoSwitch" $true "no estaba en ejecucion (nada que detener)"
}

# 3. Directorio de instalacion.
# Si se ejecuta desde dentro de InstallDir, cmd hace la limpieza tras terminar
# PowerShell; no podemos verificar el resultado ahora mismo, asi que se indica
# como "programado".
$current = $MyInvocation.MyCommand.Path
$runningFromInstall = $false
if ($current -like "$InstallDir\*") {
    $runningFromInstall = $true
}

if ($runningFromInstall) {
    if (-not (Test-Path $InstallDir)) {
        Show-Test "Directorio de instalacion" $true "no existia (nada que quitar)"
    }
    else {
        $cmd = "timeout /t 2 /nobreak >nul & rmdir /s /q `"$InstallDir`""
        try {
            Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
                -ArgumentList "/c $cmd" `
                -WindowStyle Hidden `
                -WorkingDirectory (Split-Path -Parent $InstallDir) `
                -ErrorAction Stop
            $removedSomething = $true
            Show-Test "Directorio de instalacion" $true "eliminacion programada al salir del desinstalador"
        }
        catch {
            $failed = $true
            Show-Test "Directorio de instalacion" $false "no se pudo programar la eliminacion: $($_.Exception.Message)"
        }
    }
}
else {
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $InstallDir) {
            $failed = $true
            Show-Test "Directorio de instalacion" $false "no se pudo eliminar: $InstallDir"
        }
        else {
            $removedSomething = $true
            Show-Test "Directorio de instalacion" $true "eliminado"
        }
    }
    else {
        Show-Test "Directorio de instalacion" $true "no existia (nada que quitar)"
    }
}

Write-Host ""
if ($failed) {
    Write-Host "Desinstalacion INCOMPLETA. Revisa los FALLO de arriba." -ForegroundColor Red
    exit 1
}
elseif ($removedSomething) {
    Write-Host "AutoSwitch desinstalado." -ForegroundColor Green
}
else {
    Write-Host "Nada que desinstalar: AutoSwitch ya no estaba instalado." -ForegroundColor DarkGray
}

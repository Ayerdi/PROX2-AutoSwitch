#requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

$InstallDir   = Join-Path $env:LOCALAPPDATA "PROX2AutoSwitch"
$MainScript   = Join-Path $InstallDir "PROX2AutoSwitch.ps1"
$StartupDir   = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "PRO X 2 AutoSwitch.lnk"

Write-Host ""
Write-Host "=== Desinstalar PRO X 2 AutoSwitch ===" -ForegroundColor Cyan
Write-Host ""

Remove-Item $ShortcutPath -Force -ErrorAction SilentlyContinue

if (Test-Path $MainScript) {
    $escaped = [regex]::Escape($MainScript)

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -match $escaped
        } |
        ForEach-Object {
            Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null
        }
}

Start-Sleep -Milliseconds 600

# Si se ejecuta desde fuera de InstallDir, puede borrarlo directamente.
# Si se ejecuta desde dentro, cmd hace la limpieza tras terminar PowerShell.
$current = $MyInvocation.MyCommand.Path
if ($current -like "$InstallDir\*") {
    $cmd = "timeout /t 2 /nobreak >nul & rmdir /s /q `"$InstallDir`""
    Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
        -ArgumentList "/c $cmd" `
        -WindowStyle Hidden
}
else {
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "AutoSwitch desinstalado." -ForegroundColor Green

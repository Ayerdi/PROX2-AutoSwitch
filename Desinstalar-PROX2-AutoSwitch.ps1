#requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

$InstallDir   = Join-Path $env:LOCALAPPDATA "PROX2AutoSwitch"
$MainScript   = Join-Path $InstallDir "PROX2AutoSwitch.ps1"
$StartupDir   = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "PRO X 2 AutoSwitch.lnk"

Write-Host ""
Write-Host "=== Uninstall PRO X 2 AutoSwitch ===" -ForegroundColor Cyan
Write-Host ""

$failed = $false
$removedSomething = $false

function Show-Test {
    param([string]$Label, [bool]$Ok, [string]$Detail)

    if ($Ok) {
        Write-Host "[OK]    $Label" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL]  $Label" -ForegroundColor Red
    }

    if ($Detail) {
        Write-Host "        $Detail" -ForegroundColor DarkGray
    }
}

# 1. Autostart.
$hadShortcut = Test-Path $ShortcutPath
Remove-Item $ShortcutPath -Force -ErrorAction SilentlyContinue
if ($hadShortcut -and -not (Test-Path $ShortcutPath)) {
    $removedSomething = $true
    Show-Test "Autostart" $true "shortcut removed"
}
elseif (-not $hadShortcut) {
    Show-Test "Autostart" $true "did not exist (nothing to remove)"
}
else {
    $failed = $true
    Show-Test "Autostart" $false "could not be removed: $ShortcutPath"
}

# 2. Runtime process.
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
        Show-Test "AutoSwitch process" $false "still running (PID $($stillRunning.ProcessId))"
    }
    else {
        $removedSomething = $true
        Show-Test "AutoSwitch process" $true "stopped"
    }
}
else {
    Show-Test "AutoSwitch process" $true "was not running (nothing to stop)"
}

# 3. Install directory.
# If it runs from inside InstallDir, cmd does the cleanup after PowerShell
# exits; we cannot verify the result right now, so it is reported as "scheduled".
$current = $MyInvocation.MyCommand.Path
$runningFromInstall = $false
if ($current -like "$InstallDir\*") {
    $runningFromInstall = $true
}

if ($runningFromInstall) {
    if (-not (Test-Path $InstallDir)) {
        Show-Test "Install directory" $true "did not exist (nothing to remove)"
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
            Show-Test "Install directory" $true "removal scheduled when the uninstaller exits"
        }
        catch {
            $failed = $true
            Show-Test "Install directory" $false "could not schedule removal: $($_.Exception.Message)"
        }
    }
}
else {
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $InstallDir) {
            $failed = $true
            Show-Test "Install directory" $false "could not be removed: $InstallDir"
        }
        else {
            $removedSomething = $true
            Show-Test "Install directory" $true "removed"
        }
    }
    else {
        Show-Test "Install directory" $true "did not exist (nothing to remove)"
    }
}

Write-Host ""
if ($failed) {
    Write-Host "Uninstall INCOMPLETE. Review the FAILs above." -ForegroundColor Red
    exit 1
}
elseif ($removedSomething) {
    Write-Host "AutoSwitch uninstalled." -ForegroundColor Green
}
else {
    Write-Host "Nothing to uninstall: AutoSwitch was not installed." -ForegroundColor DarkGray
}

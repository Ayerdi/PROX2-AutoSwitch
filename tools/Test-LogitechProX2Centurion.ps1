#requires -Version 5.1
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Module = Join-Path $Root "lib\LogitechProX2Centurion.psm1"
if (-not (Test-Path $Module)) { throw "Centurion module not found: $Module" }
Import-Module $Module -Force -ErrorAction Stop

Write-Host ""
Write-Host "=== Logitech PRO X 2 Centurion HID diagnostic ===" -ForegroundColor Cyan
Write-Host "VID 046D / PID 0AF7 / UsagePage FFA0" -ForegroundColor DarkGray
Write-Host "Press Ctrl+C to stop." -ForegroundColor Cyan
Write-Host ""
while ($true) {
    $r = Get-LogitechProX2CenturionState
    $battery = if ([int]$r.BatteryPercent -ge 0) { "$([int]$r.BatteryPercent)%" } else { "n/a" }
    Write-Host ("State={0} Battery={1} OfflineSignature={2}" -f $r.State, $battery, $r.OfflineSignatureSeen)
    if ($r.Error) { Write-Host "Detail: $($r.Error)" -ForegroundColor DarkYellow }
    if ($r.Frames) { Write-Host "Frames: $($r.Frames)" -ForegroundColor DarkGray }
    Start-Sleep -Seconds 1
}

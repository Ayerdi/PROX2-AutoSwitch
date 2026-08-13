#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$module = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\SteelSeriesNova5.psm1'
Import-Module $module -Force

Write-Host 'SteelSeries Arctis Nova 5/5X HID diagnostic' -ForegroundColor Cyan
Write-Host ''

if (-not (Test-SteelSeriesNova5Receiver)) {
    Write-Host 'No compatible Nova 5/5X receiver was found.' -ForegroundColor Red
    exit 2
}

Write-Host 'Compatible receiver found.' -ForegroundColor Green
Write-Host 'Press Ctrl+C to stop. Turn the headset ON and OFF and watch the state.' -ForegroundColor DarkGray
Write-Host ''

$last = $null
while ($true) {
    $state = Get-SteelSeriesNova5State -TimeoutMilliseconds 800
    if ($state -ne $last) {
        $color = switch ($state) {
            'Connected'    { 'Green' }
            'Disconnected' { 'Yellow' }
            default        { 'Red' }
        }
        Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $state) -ForegroundColor $color
        $last = $state
    }
    Start-Sleep -Milliseconds 500
}

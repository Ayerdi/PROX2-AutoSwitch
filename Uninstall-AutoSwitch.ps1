#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$legacy = Join-Path $PSScriptRoot 'Desinstalar-PROX2-AutoSwitch.ps1'
if (-not (Test-Path $legacy)) { throw "Uninstaller entrypoint is missing: $legacy" }
& $legacy @args

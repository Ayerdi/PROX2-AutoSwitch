#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$legacy = Join-Path $PSScriptRoot 'Instalar-PROX2-AutoSwitch.ps1'
if (-not (Test-Path $legacy)) { throw "Installer entrypoint is missing: $legacy" }
& $legacy @args

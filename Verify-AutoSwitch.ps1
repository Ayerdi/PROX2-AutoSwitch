#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$legacy = Join-Path $PSScriptRoot 'Verificar-PROX2-AutoSwitch.ps1'
if (-not (Test-Path $legacy)) { throw "Verification entrypoint is missing: $legacy" }
& $legacy @args

#requires -Version 5.1
$ErrorActionPreference = "Stop"

# PRO X 2 LIGHTSPEED AutoSwitch - instalador de un clic.
# Descarga la ultima version desde GitHub Releases y ejecuta el instalador real.

$Repo = "Ayerdi/PROX2-AutoSwitch"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PRO X 2 LIGHTSPEED - AutoSwitch de audio" -ForegroundColor Cyan
Write-Host " Instalacion de un clic" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Buscando la ultima version..." -ForegroundColor Yellow

$release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ "User-Agent" = "PROX2-AutoSwitch-installer" }

$zipAsset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
if (-not $zipAsset) {
    throw "La release $($release.tag_name) no contiene ningun ZIP."
}

$ZipPath = Join-Path $env:TEMP "PROX2-AutoSwitch-$($release.tag_name).zip"
$ExtractDir = Join-Path $env:TEMP "PROX2-AutoSwitch-extract"

Write-Host "Version $($release.tag_name)" -ForegroundColor Green
Write-Host "Descargando $($zipAsset.name)..." -ForegroundColor Yellow
Invoke-WebRequest -UseBasicParsing -Uri $zipAsset.browser_download_url -OutFile $ZipPath

Write-Host "Extrayendo..." -ForegroundColor Yellow
if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

$Installer = Join-Path $ExtractDir "Instalar-PROX2-AutoSwitch.ps1"
if (-not (Test-Path $Installer)) {
    throw "No se encontro el instalador dentro del ZIP."
}

try {
    & $Installer
}
finally {
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
}

#requires -Version 5.1
$ErrorActionPreference = "Stop"

# PowerShell 5.1 on older .NET may negotiate TLS 1.0/1.1 and fail against
# GitHub/NirSoft. Force TLS 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Audio AutoSwitch one-command bootstrap.
# Downloads the latest GitHub Release ZIP plus its SHA-256 checksum and only
# runs the real installer after the package integrity has been verified.

$Repo = "Ayerdi/PROX2-AutoSwitch"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
$ZipPattern = "PROX2-AutoSwitch-*.zip"
$ChecksumSuffix = ".sha256"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Audio AutoSwitch" -ForegroundColor Cyan
Write-Host " Quick install" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Looking for the latest release..." -ForegroundColor Yellow

$release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ "User-Agent" = "Audio-AutoSwitch-installer" }

$zipAssets = @($release.assets | Where-Object { $_.name -like $ZipPattern })
if ($zipAssets.Count -ne 1) {
    throw "Expected exactly one project ZIP ($ZipPattern) in release $($release.tag_name), but found $($zipAssets.Count)."
}
$zipAsset = $zipAssets[0]

$checksumName = $zipAsset.name + $ChecksumSuffix
$checksumAsset = $release.assets | Where-Object { $_.name -eq $checksumName } | Select-Object -First 1
if (-not $checksumAsset) {
    throw "Release $($release.tag_name) does not publish $checksumName. Integrity cannot be verified, so installation is aborted."
}

$ZipPath = Join-Path $env:TEMP $zipAsset.name
$ChecksumPath = Join-Path $env:TEMP $checksumName
$ExtractDir = Join-Path $env:TEMP "PROX2-AutoSwitch-extract"

try {
    Write-Host "Version $($release.tag_name)" -ForegroundColor Green
    Write-Host "Downloading $($zipAsset.name) and checksum..." -ForegroundColor Yellow
    Invoke-WebRequest -UseBasicParsing -Uri $zipAsset.browser_download_url -OutFile $ZipPath
    Invoke-WebRequest -UseBasicParsing -Uri $checksumAsset.browser_download_url -OutFile $ChecksumPath

    Write-Host "Verifying SHA-256..." -ForegroundColor Yellow
    $expectedLine = (Get-Content -Raw $ChecksumPath).Trim()
    $expectedHash = ($expectedLine -split "\s+")[0].ToLowerInvariant()
    if (-not $expectedHash -or $expectedHash -notmatch '^[0-9a-f]{64}$') {
        throw "The downloaded checksum is not a valid SHA-256 value."
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -Path $ZipPath).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "The ZIP SHA-256 does not match the published checksum. Installation is aborted. Expected=$expectedHash Actual=$actualHash"
    }
    Write-Host "      SHA-256 OK." -ForegroundColor Green

    Write-Host "Extracting..." -ForegroundColor Yellow
    if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

    $Installer = Join-Path $ExtractDir "Instalar-PROX2-AutoSwitch.ps1"
    if (-not (Test-Path $Installer)) {
        # Releases may contain a wrapper directory, so search one level deeper.
        $nested = Get-ChildItem -Path $ExtractDir -Recurse -Filter "Instalar-PROX2-AutoSwitch.ps1" |
            Select-Object -First 1
        if ($nested) { $Installer = $nested.FullName }
    }
    if (-not (Test-Path $Installer)) {
        throw "The installer was not found inside the release ZIP."
    }

    & $Installer
}
finally {
    # Leave no temporary package behind, including on failure.
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $ChecksumPath -Force -ErrorAction SilentlyContinue
    Remove-Item $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
}

#requires -Version 5.1
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'Ayerdi/PROX2-AutoSwitch'
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
$ZipPattern = 'PROX2-AutoSwitch-*.zip'

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Audio AutoSwitch' -ForegroundColor Cyan
Write-Host ' Verified one-command installation' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Looking for the latest stable release...' -ForegroundColor Yellow

$release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ 'User-Agent' = 'Audio-AutoSwitch-installer' }
$zipAssets = @($release.assets | Where-Object { $_.name -like $ZipPattern })
if ($zipAssets.Count -ne 1) { throw "Expected exactly one project ZIP ($ZipPattern) in $($release.tag_name); found $($zipAssets.Count)." }
$zipAsset = $zipAssets[0]
$checksumName = $zipAsset.name + '.sha256'
$checksumAsset = $release.assets | Where-Object { $_.name -eq $checksumName } | Select-Object -First 1
if (-not $checksumAsset) { throw "Release $($release.tag_name) does not publish $checksumName; integrity cannot be verified." }

$ZipPath = Join-Path $env:TEMP $zipAsset.name
$ChecksumPath = Join-Path $env:TEMP $checksumName
$ExtractDir = Join-Path $env:TEMP 'PROX2-AutoSwitch-extract'
try {
    Invoke-WebRequest -UseBasicParsing -Uri $zipAsset.browser_download_url -OutFile $ZipPath
    Invoke-WebRequest -UseBasicParsing -Uri $checksumAsset.browser_download_url -OutFile $ChecksumPath
    $expected = (((Get-Content -Raw $ChecksumPath).Trim()) -split '\s+')[0].ToLowerInvariant()
    if ($expected -notmatch '^[0-9a-f]{64}$') { throw 'Downloaded checksum is not a valid SHA-256 value.' }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $ZipPath).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Release ZIP SHA-256 mismatch. Expected=$expected Got=$actual" }
    if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force
    $installer = Get-ChildItem -Path $ExtractDir -Recurse -Filter 'Install-AutoSwitch.ps1' | Select-Object -First 1
    if (-not $installer) { $installer = Get-ChildItem -Path $ExtractDir -Recurse -Filter 'Instalar-PROX2-AutoSwitch.ps1' | Select-Object -First 1 }
    if (-not $installer) { throw 'No installer entrypoint was found inside the release ZIP.' }
    & $installer.FullName
}
finally {
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $ChecksumPath -Force -ErrorAction SilentlyContinue
    Remove-Item $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
}

#requires -Version 5.1
# SteelSeriesNova5.psm1 - physical-state provider for SteelSeries Arctis Nova 5/5X.
# Uses the upstream HeadsetControl CLI, which queries the receiver over HID.

Set-StrictMode -Version Latest

function Get-ConfigDetectionMode {
    <#
    .SYNOPSIS
        Extended DetectionMode resolver including SteelSeriesNova5.
    .DESCRIPTION
        This module is imported after AutoSwitchCore so this command extends
        the existing resolver without modifying the shared COM-heavy module.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Config)

    $property = $Config.PSObject.Properties['DetectionMode']
    $mode = if ($null -ne $property) { [string]$property.Value } else { $null }

    if ([string]::IsNullOrWhiteSpace($mode)) { return 'LogitechGHub' }
    if ($mode -ieq 'WindowsEndpoint') { return 'WindowsEndpoint' }
    if ($mode -ieq 'LogitechGHub') { return 'LogitechGHub' }
    if ($mode -ieq 'SteelSeriesNova5') { return 'SteelSeriesNova5' }
    return $null
}

function Get-HeadsetControlPortableInfo {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Version = '4.0.0'
        Url = 'https://github.com/Sapd/HeadsetControl/releases/download/4.0.0/headsetcontrol-windows-x86_64.exe'
        Sha256 = 'd78a86cc0f44403d2bcb16294f8f2d91cc2f9f343adb09907a8cef8278309be8'
    }
}

function Install-HeadsetControlPortable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $info = Get-HeadsetControlPortableInfo

    if (Test-Path -LiteralPath $DestinationPath) {
        try {
            $existingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $DestinationPath).Hash.ToLowerInvariant()
            if ($existingHash -eq $info.Sha256) {
                return $DestinationPath
            }
        }
        catch { }
    }

    $tempPath = Join-Path $env:TEMP ('headsetcontrol-{0}-{1}.exe' -f $info.Version, [guid]::NewGuid().ToString('N'))
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $info.Url -OutFile $tempPath -ErrorAction Stop
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $tempPath).Hash.ToLowerInvariant()
        if ($actualHash -ne $info.Sha256) {
            throw "HeadsetControl SHA-256 mismatch. Expected $($info.Sha256), got $actualHash."
        }

        $parent = Split-Path -Parent $DestinationPath
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Move-Item -LiteralPath $tempPath -Destination $DestinationPath -Force
        return $DestinationPath
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-SteelSeriesNova5HeadsetControlJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$JsonText,
        [Parameter(Mandatory = $true)]
        [ValidateSet(0x2232, 0x2253)]
        [int]$ProductId
    )

    if ([string]::IsNullOrWhiteSpace($JsonText)) { return 'Unknown' }

    try { $data = $JsonText | ConvertFrom-Json -ErrorAction Stop }
    catch { return 'Unknown' }

    $devices = @($data.devices)
    if ($devices.Count -ne 1) { return 'Unknown' }

    $device = $devices[0]
    $expectedProduct = ('0x{0:x4}' -f $ProductId)
    if ([string]$device.id_vendor -ine '0x1038' -or
        [string]$device.id_product -ine $expectedProduct) {
        return 'Unknown'
    }

    if ($null -ne $device.battery) {
        $batteryStatus = [string]$device.battery.status
        if ($batteryStatus -ieq 'BATTERY_AVAILABLE' -or
            $batteryStatus -ieq 'BATTERY_CHARGING') {
            return 'Connected'
        }
    }

    if ($null -ne $device.errors) {
        foreach ($property in $device.errors.PSObject.Properties) {
            $message = [string]$property.Value
            if ($message -match '(?i)headset\s+not\s+connected') {
                return 'Disconnected'
            }
        }
    }

    return 'Unknown'
}

function Get-SteelSeriesNova5State {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HeadsetControlPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet(0x2232, 0x2253)]
        [int]$ProductId,
        [ValidateRange(100, 5000)]
        [int]$TimeoutMilliseconds = 1000
    )

    if (-not (Test-Path -LiteralPath $HeadsetControlPath)) { return 'Unknown' }

    $deviceFilter = '0x1038:0x{0:x4}' -f $ProductId
    try {
        $raw = & $HeadsetControlPath --device $deviceFilter --battery --output JSON --timeout $TimeoutMilliseconds 2>&1
        $text = ($raw | Out-String).Trim()
        return Resolve-SteelSeriesNova5HeadsetControlJson -JsonText $text -ProductId $ProductId
    }
    catch { return 'Unknown' }
}

function Get-SteelSeriesNova5ConnectedProductId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HeadsetControlPath,
        [ValidateRange(100, 5000)][int]$TimeoutMilliseconds = 1000
    )

    $connected = @()
    foreach ($productId in @(0x2232, 0x2253)) {
        $state = Get-SteelSeriesNova5State -HeadsetControlPath $HeadsetControlPath -ProductId $productId -TimeoutMilliseconds $TimeoutMilliseconds
        if ($state -eq 'Connected') { $connected += $productId }
    }

    if ($connected.Count -eq 1) { return [int]$connected[0] }
    return $null
}

function Wait-SteelSeriesNova5State {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Connected', 'Disconnected')]
        [string]$Expected,
        [Parameter(Mandatory = $true)][string]$HeadsetControlPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet(0x2232, 0x2253)]
        [int]$ProductId,
        [ValidateRange(1, 60)][int]$TimeoutSeconds = 15,
        [ValidateRange(100, 5000)][int]$PollIntervalMilliseconds = 500,
        [ValidateRange(100, 5000)][int]$ProbeTimeoutMilliseconds = 1000
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastState = 'Unknown'

    do {
        $lastState = Get-SteelSeriesNova5State -HeadsetControlPath $HeadsetControlPath -ProductId $ProductId -TimeoutMilliseconds $ProbeTimeoutMilliseconds
        if ($lastState -eq $Expected) { return $lastState }
        Start-Sleep -Milliseconds $PollIntervalMilliseconds
    } while ((Get-Date) -lt $deadline)

    return $lastState
}

Export-ModuleMember -Function Get-ConfigDetectionMode, Get-HeadsetControlPortableInfo, Install-HeadsetControlPortable, Resolve-SteelSeriesNova5HeadsetControlJson, Get-SteelSeriesNova5State, Get-SteelSeriesNova5ConnectedProductId, Wait-SteelSeriesNova5State

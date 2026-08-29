#requires -Version 5.1
# LogitechGHub.psm1 - bounded local G HUB WebSocket transport and headset resolution.

Set-StrictMode -Version Latest

$core = Join-Path $PSScriptRoot 'AutoSwitchCore.psm1'
if (-not (Get-Module | Where-Object { $_.Path -eq $core })) {
    Import-Module $core -ErrorAction Stop
}

$script:Ws = $null
$script:ReceiveTimeoutMs = 5000
$script:RequestTimeoutMs = 10000

function Close-LogitechGHubConnection {
    [CmdletBinding()]
    param()

    if ($null -ne $script:Ws -and
        $script:Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $closeCts = New-Object System.Threading.CancellationTokenSource
        $closeCts.CancelAfter(1000)
        try {
            $script:Ws.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                'autoswitch',
                $closeCts.Token
            ).GetAwaiter().GetResult() | Out-Null
        }
        catch {
            try { $script:Ws.Abort() } catch { }
        }
        finally {
            $closeCts.Dispose()
        }
    }

    try {
        if ($null -ne $script:Ws) { $script:Ws.Dispose() }
    }
    catch { }

    $script:Ws = $null
}

function Open-LogitechGHubConnection {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 65535)][int]$Port = 9010,
        [ValidateRange(100, 60000)][int]$ConnectTimeoutMs = 5000,
        [ValidateRange(100, 60000)][int]$ReceiveTimeoutMs = 5000,
        [ValidateRange(100, 120000)][int]$RequestTimeoutMs = 10000
    )

    Close-LogitechGHubConnection
    $script:ReceiveTimeoutMs = $ReceiveTimeoutMs
    $script:RequestTimeoutMs = $RequestTimeoutMs
    $script:Ws = New-Object System.Net.WebSockets.ClientWebSocket

    $script:Ws.Options.UseDefaultCredentials = $false
    $script:Ws.Options.SetRequestHeader('Origin', 'file://')
    $script:Ws.Options.SetRequestHeader('Pragma', 'no-cache')
    $script:Ws.Options.SetRequestHeader('Cache-Control', 'no-cache')
    $script:Ws.Options.SetRequestHeader(
        'Sec-WebSocket-Extensions',
        'permessage-deflate; client_max_window_bits'
    )
    $script:Ws.Options.SetRequestHeader('Sec-WebSocket-Protocol', 'json')
    $script:Ws.Options.AddSubProtocol('json')

    $uri = New-Object System.Uri("ws://localhost:$Port")
    $timeout = New-GHubTimeoutToken -Milliseconds $ConnectTimeoutMs
    try {
        $script:Ws.ConnectAsync($uri, $timeout.Token).GetAwaiter().GetResult() | Out-Null
    }
    catch [System.OperationCanceledException] {
        throw "Timed out connecting to G HUB ($ConnectTimeoutMs ms)."
    }
    finally {
        $timeout.Dispose()
    }

    if ($script:Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "Could not connect to Logitech G HUB on localhost:$Port."
    }
}

function Send-LogitechGHubJson {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Object)

    if ($null -eq $script:Ws -or
        $script:Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw 'G HUB WebSocket is not connected.'
    }

    $json = $Object | ConvertTo-Json -Compress -Depth 20
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (,$bytes)

    $timeout = New-GHubTimeoutToken -Milliseconds $script:ReceiveTimeoutMs
    try {
        $script:Ws.SendAsync(
            $segment,
            [System.Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            $timeout.Token
        ).GetAwaiter().GetResult() | Out-Null
    }
    catch [System.OperationCanceledException] {
        throw "Timed out sending a request to G HUB ($($script:ReceiveTimeoutMs) ms)."
    }
    finally {
        $timeout.Dispose()
    }
}

function Receive-LogitechGHubText {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][datetime]$Deadline)

    if ($null -eq $script:Ws -or
        $script:Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw 'G HUB WebSocket is not connected.'
    }

    $buffer = New-Object byte[] 16384
    $stream = New-Object System.IO.MemoryStream

    try {
        do {
            $remainingMs = [int](($Deadline - (Get-Date)).TotalMilliseconds)
            if ($remainingMs -le 0) {
                throw "G HUB request timed out ($($script:RequestTimeoutMs) ms)."
            }

            $fragmentMs = [Math]::Min($script:ReceiveTimeoutMs, $remainingMs)
            $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (,$buffer)
            $timeout = New-GHubTimeoutToken -Milliseconds $fragmentMs
            try {
                $result = $script:Ws.ReceiveAsync(
                    $segment,
                    $timeout.Token
                ).GetAwaiter().GetResult()
            }
            catch [System.OperationCanceledException] {
                throw "Timed out waiting for a G HUB response ($fragmentMs ms)."
            }
            finally {
                $timeout.Dispose()
            }

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw 'G HUB closed the WebSocket.'
            }

            if ($result.Count -gt 0) {
                $stream.Write($buffer, 0, $result.Count)
            }
        } while (-not $result.EndOfMessage)

        return [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-LogitechGHubGet {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $msgId = [guid]::NewGuid().ToString()
    Send-LogitechGHubJson @{
        msgId = $msgId
        verb  = 'GET'
        path  = $Path
    }

    $deadline = (Get-Date).AddMilliseconds($script:RequestTimeoutMs)
    while ($true) {
        if ((Get-Date) -gt $deadline) {
            throw "G HUB request timed out ($($script:RequestTimeoutMs) ms): $Path"
        }

        $raw = Receive-LogitechGHubText -Deadline $deadline
        try {
            $message = $raw | ConvertFrom-Json
        }
        catch {
            continue
        }

        # G HUB can interleave asynchronous events with responses.
        if (($message.msgId -eq $msgId) -or ($message.path -eq $Path)) {
            return $message
        }
    }
}

function Get-LogitechGHubHeadsets {
    [CmdletBinding()]
    param()

    $devices = Invoke-LogitechGHubGet -Path '/devices/list'
    return @(Get-LogitechHeadsetCandidates -DeviceInfos @($devices.payload.deviceInfos))
}

function Resolve-LogitechGHubHeadset {
    <#
    .SYNOPSIS
        Resolve a configured Logitech headset without guessing among multiple devices.
    .DESCRIPTION
        Prefer an exact compatible display-name match. If there is no configured
        name, or it no longer matches, accept a single compatible candidate. Return
        null when there are zero or multiple ambiguous candidates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$DeviceInfos,
        [string]$DisplayName
    )

    $candidates = @(Get-LogitechHeadsetCandidates -DeviceInfos $DeviceInfos)

    if (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
        $match = $candidates |
            Where-Object { [string]$_.extendedDisplayName -ieq $DisplayName } |
            Select-Object -First 1
        if ($match) { return $match }
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    return $null
}

function Get-LogitechGHubBatteryPath {
    [CmdletBinding()]
    param([string]$DisplayName)

    $devices = Invoke-LogitechGHubGet -Path '/devices/list'
    $headset = Resolve-LogitechGHubHeadset `
        -DeviceInfos @($devices.payload.deviceInfos) `
        -DisplayName $DisplayName

    if (-not $headset) {
        throw 'G HUB did not return an unambiguous compatible Logitech headset.'
    }

    return [pscustomobject]@{
        Path        = "/battery/$($headset.id)/state"
        DisplayName = [string]$headset.extendedDisplayName
        DeviceId    = [string]$headset.id
    }
}

Export-ModuleMember -Function Open-LogitechGHubConnection, Close-LogitechGHubConnection, Invoke-LogitechGHubGet, Get-LogitechGHubHeadsets, Resolve-LogitechGHubHeadset, Get-LogitechGHubBatteryPath

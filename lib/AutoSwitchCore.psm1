#requires -Version 5.1
# AutoSwitchCore.psm1 - logica pura y testeable del PRO X 2 AutoSwitch.
# Sin dependencias de G HUB ni de svcl.exe, para poder probarse con Pester.

Set-StrictMode -Version Latest

function Get-RenderItemIdFromText {
    <#
    .SYNOPSIS
        Extrae el Item ID de render valido desde la salida de svcl.exe.
    .DESCRIPTION
        Usa /GetColumnValue (NUNCA /Stdout /GetColumnValue, que contamina la salida).
        Devuelve $null si no hay ningun Item ID de render valido.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $m = [regex]::Match(
        $Text,
        '\{0\.0\.0\.00000000\}\.\{[0-9A-Fa-f-]+\}'
    )

    if (-not $m.Success) {
        return $null
    }

    return $m.Value.ToLowerInvariant()
}

function Resolve-HeadsetState {
    <#
    .SYNOPSIS
        Debounce del estado fisico del PRO X 2.
    .DESCRIPTION
        Devuelve [pscustomobject] con IsOn (bool), Decision (bool: aplicar o no)
        y Misses (contador). Solo se decide OFF tras OffMissThreshold respuestas
        vacias consecutivas. Una respuesta con payload resetea el contador.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$PayloadPresent,
        [Parameter(Mandatory = $true)][int]$Misses,
        [Parameter(Mandatory = $true)][int]$OffMissThreshold
    )

    if ($PayloadPresent) {
        return [pscustomobject]@{
            IsOn      = $true
            Decision  = $true
            Misses    = 0
        }
    }

    $newMisses = $Misses + 1
    if ($newMisses -lt $OffMissThreshold) {
        return [pscustomobject]@{
            IsOn      = $false
            Decision  = $false
            Misses    = $newMisses
        }
    }

    return [pscustomobject]@{
        IsOn      = $false
        Decision  = $true
        Misses    = $newMisses
    }
}

function Test-ValidAudioConfig {
    <#
    .SYNOPSIS
        True si HeadsetId y SpeakerId son distintos.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HeadsetId,
        [Parameter(Mandatory = $true)][string]$SpeakerId
    )

    return ($HeadsetId -ine $SpeakerId)
}

function New-GHubTimeoutToken {
    <#
    .SYNOPSIS
        CancellationTokenSource que se cancela solo pasados $Milliseconds.
    .DESCRIPTION
        Todos los CallAsync del WebSocket usan este token; sin el CancelAfter
        un CloseAsync/ReceiveAsync podria colgar el runtime indefinidamente.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Milliseconds
    )

    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter($Milliseconds)
    return $cts
}

Export-ModuleMember -Function Get-RenderItemIdFromText, Resolve-HeadsetState, Test-ValidAudioConfig, New-GHubTimeoutToken

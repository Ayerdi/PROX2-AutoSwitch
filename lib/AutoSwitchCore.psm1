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

function ConvertFrom-SvclCsv {
    <#
    .SYNOPSIS
        Parsea la salida /scomma de svcl.exe a objetos.
    .DESCRIPTION
        La primera linea de la exportacion es la cabecera de columnas.
        Soporta campos entre comillas dobles y comas internas.
        Devuelve [pscustomobject[]] con una propiedad por columna.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $lines = @(
        $Text -split "(`r`n|`n|`r)" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne "" }
    )

    if ($lines.Count -lt 2) {
        return @()
    }

    $header = ConvertFrom-CsvLine -Line $lines[0]
    if ($header.Count -eq 0) {
        return @()
    }

    $result = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $fields = ConvertFrom-CsvLine -Line $lines[$i]
        $row = [ordered]@{}
        for ($c = 0; $c -lt $header.Count; $c++) {
            $name = $header[$c].Trim()
            if ($name -eq "") { continue }
            $value = ""
            if ($c -lt $fields.Count) { $value = $fields[$c] }
            $row[$name] = $value
        }
        if ($row.Count -gt 0) {
            $result += [pscustomobject]$row
        }
    }

    return ,$result
}

function ConvertFrom-CsvLine {
    <#
    .SYNOPSIS
        Divide una linea CSV simple en campos, respetando comillas dobles.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Line
    )

    $fields = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inQuotes = $false

    for ($i = 0; $i -lt $Line.Length; $i++) {
        $ch = $Line[$i]

        if ($inQuotes) {
            if ($ch -eq '"') {
                if (($i + 1) -lt $Line.Length -and $Line[$i + 1] -eq '"') {
                    [void]$current.Append('"')
                    $i++
                }
                else {
                    $inQuotes = $false
                }
            }
            else {
                [void]$current.Append($ch)
            }
        }
        else {
            if ($ch -eq '"') {
                $inQuotes = $true
            }
            elseif ($ch -eq ',') {
                $fields.Add($current.ToString())
                [void]$current.Clear()
            }
            else {
                [void]$current.Append($ch)
            }
        }
    }

    $fields.Add($current.ToString())
    return $fields.ToArray()
}

function Get-CsvColumn {
    <#
    .SYNOPSIS
        Devuelve el valor de la primera columna cuyo nombre coincida (sin
        distinguir mayusculas) con uno de $Names. Soportan alias porque
        svcl usa 'State' en unas versiones y 'DeviceState' en otras.
        Devuelve $null si no existe ninguna.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Row,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    foreach ($name in $Names) {
        $p = $Row.PSObject.Properties[$name]
        if ($null -ne $p) {
            return [string]$p.Value
        }
    }

    return $null
}

function Resolve-EndpointState {
    <#
    .SYNOPSIS
        Normaliza el estado de un endpoint de Windows a Connected/Disconnected/Unknown.
    .DESCRIPTION
        Active        -> Connected
        Unplugged     -> Disconnected
        NotPresent    -> Disconnected
        roowausente   -> Disconnected
        Disabled      -> Unknown (no cambiar)
        Error / otro  -> Unknown (no cambiar)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$State
    )

    switch ($State.Trim().ToLowerInvariant()) {
        'active' { return 'Connected' }
        'unplugged' { return 'Disconnected' }
        'notpresent' { return 'Disconnected' }
        'disabled' { return 'Unknown' }
        default { return 'Unknown' }
    }
}

function Resolve-DetectedState {
    <#
    .SYNOPSIS
        Debounce del estado detectado (endpoint Windows o payload G HUB).
    .DESCRIPTION
        Igual que Resolve-HeadsetState pero sin asumir nada de G HUB:
        PayloadPresent true -> Connected; false -> Disconnected tras
        OffMissThreshold misses. Devuelve el mismo objeto con IsOn/Decision/Misses.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$PayloadPresent,
        [Parameter(Mandatory = $true)][int]$Misses,
        [Parameter(Mandatory = $true)][int]$OffMissThreshold
    )

    return Resolve-HeadsetState -PayloadPresent $PayloadPresent -Misses $Misses -OffMissThreshold $OffMissThreshold
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

function Get-SvclRenderDevices {
    <#
    .SYNOPSIS
        Filtra la exportacion /scomma de svcl.exe a solo endpoints de salida
        (render) reales: Type='Device' y Direction='Render' (o 'Render' como
        subcadena, segun la version de svcl).
    .DESCRIPTION
        Devuelve [pscustomobject[]] con las filas filtradas. Cada fila conserva
        las columnas reales de svcl: Name, Type, Direction, Device State, Item ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CsvText
    )

    $rows = @(ConvertFrom-SvclCsv -Text $CsvText)
    if ($rows.Count -eq 0) {
        return @()
    }

    $render = @($rows | Where-Object {
        $type = Get-CsvColumn -Row $_ -Names @('Type')
        $dir  = Get-CsvColumn -Row $_ -Names @('Direction')

        $typeOk = $null -eq $type -or $type -match 'Device'
        $dirOk  = $null -ne $dir -and $dir -match 'Render'

        $typeOk -and $dirOk
    })

    if ($render.Count -eq 0) {
        # Fallback defensivo: si la version de svcl no tiene Type/Direction,
        # devolver todas las filas (el llamador filtra por Item ID de todos modos).
        return $rows
    }

    return ,$render
}

function Get-EndpointFxState {
    <#
    .SYNOPSIS
        Lee el estado actual de PKEY_AudioEndpoint_Disable_SysFx de un endpoint
        sin necesitar administrador.
    .DESCRIPTION
        Implementa IMMDeviceEnumerator/IMMDevice/IPropertyStore con las IID/GUID
        reales de Windows Core Audio. Devuelve $true si los enhancements estan
        deshabilitados (SysFx=1), $false si estan habilitados (SysFx=0 o valor
        ausente) y $null si no se pudo leer (endpoint inexistente o error).
        Nunca lanza.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DeviceId
    )

    try {
        $typeName = 'AutoSwitch.CoreAudio'

        if (-not ($typeName -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace AutoSwitch
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PROPERTYKEY
    {
        public Guid fmtid;
        public uint pid;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct PROPVARIANT
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public ushort uiVal;
        [FieldOffset(8)] public uint ulVal;
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IntPtr device);
        int GetDevice(string pwstrId, out IntPtr device);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice
    {
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IntPtr pInterface);
        int OpenPropertyStore(int stgmAccess, out IntPtr ppProperties);
        int GetId(out IntPtr ppstrId);
        int GetState(out int pdwState);
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore
    {
        int GetCount(out uint cProps);
        int GetAt(uint iProp, out PROPERTYKEY pkey);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        int Commit();
    }
}
'@ -ErrorAction Stop
        }

        $enumerator = New-Object AutoSwitch.MMDeviceEnumeratorComObject
        $enumeratorIface = [AutoSwitch.IMMDeviceEnumerator]$enumerator

        $devicePtr = [IntPtr]::Zero
        $hr = $enumeratorIface.GetDevice($DeviceId, [ref]$devicePtr)
        if ($hr -ne 0 -or $devicePtr -eq [IntPtr]::Zero) {
            return $null
        }

        $device = [System.Runtime.InteropServices.Marshal]::GetObjectForIUnknown($devicePtr)
        $deviceIface = [AutoSwitch.IMMDevice]$device

        $storePtr = [IntPtr]::Zero
        $hrStore = $deviceIface.OpenPropertyStore(0, [ref]$storePtr)  # STGM_READ = 0
        if ($hrStore -ne 0 -or $storePtr -eq [IntPtr]::Zero) {
            return $null
        }

        $store = [System.Runtime.InteropServices.Marshal]::GetObjectForIUnknown($storePtr)
        $storeIface = [AutoSwitch.IPropertyStore]$store

        $pkey = New-Object AutoSwitch.PROPERTYKEY
        $pkey.fmtid = [guid]'1da5d803-d492-4edd-8c23-e0c0ffee7f0e'
        $pkey.pid = 5

        $pv = New-Object AutoSwitch.PROPVARIANT
        $hrGet = $storeIface.GetValue([ref]$pkey, [ref]$pv)

        if ($hrGet -ne 0) {
            return $false
        }

        return ($pv.ulVal -ne 0)
    }
    catch {
        return $null
    }
}

function Get-ConfigDetectionMode {
    <#
    .SYNOPSIS
        Resuelve el DetectionMode de una config, con migracion implicita.
    .DESCRIPTION
        Si $Config ya tiene DetectionMode, lo devuelve validado
        ('WindowsEndpoint' o 'LogitechGHub'). Si no existe, devuelve
        'LogitechGHub' (comportamiento de configs v1.1.0 y anteriores).
        Devuelve $null si el valor existente no es valido.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Config
    )

    $mode = $null
    $p = $Config.PSObject.Properties['DetectionMode']
    if ($null -ne $p) {
        $mode = [string]$p.Value
    }

    if ([string]::IsNullOrWhiteSpace($mode)) {
        return 'LogitechGHub'
    }

    if ($mode -ieq 'WindowsEndpoint') { return 'WindowsEndpoint' }
    if ($mode -ieq 'LogitechGHub')    { return 'LogitechGHub' }

    return $null
}

Export-ModuleMember -Function Get-RenderItemIdFromText, Resolve-HeadsetState, Test-ValidAudioConfig, New-GHubTimeoutToken, ConvertFrom-SvclCsv, ConvertFrom-CsvLine, Get-CsvColumn, Resolve-EndpointState, Resolve-DetectedState, Get-SvclRenderDevices, Get-EndpointFxState, Get-ConfigDetectionMode

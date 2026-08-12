#requires -Version 5.1
# AutoSwitchCore.psm1 - pure, testable logic for Audio AutoSwitch.
# No G HUB or svcl.exe dependency is required for Pester tests.

Set-StrictMode -Version Latest

function Get-RenderItemIdFromText {
    <#
    .SYNOPSIS
        Extract a valid render Item ID from svcl.exe output.
    .DESCRIPTION
        Use /GetColumnValue (NEVER /Stdout /GetColumnValue, which contaminates the output).
        Return $null when no valid render Item ID is present.
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
        Debounce physical headset state.
    .DESCRIPTION
        Return a [pscustomobject] with IsOn, Decision (whether to act)
        and Misses. Decide OFF only after OffMissThreshold consecutive
        empty responses. A response with a payload resets the counter.
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
        Parse svcl.exe /scomma output into objects.
    .DESCRIPTION
        The first export line contains the column headers.
        Supports double-quoted fields and embedded commas.
        Returns [pscustomobject[]] with one property per column.
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

    # Native PowerShell ConvertFrom-Csv handles quotes, headers with
    # spaces and fields containing commas reliably.
    try {
        $csv = $lines -join [Environment]::NewLine
        $objects = @($csv | ConvertFrom-Csv)
        if ($objects.Count -eq 0) {
            return @()
        }
        return $objects
    }
    catch {
        return @()
    }
}

function ConvertFrom-CsvLine {
    <#
    .SYNOPSIS
        Split a simple CSV line into fields while respecting double quotes.
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
        Return the value from the first column whose name matches one of
        $Names case-insensitively. Aliases are supported because
        svcl uses 'State' in some versions and 'DeviceState' in others.
        Return $null when none exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Row,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    foreach ($name in $Names) {
        $p = $null
        foreach ($prop in $Row.PSObject.Properties) {
            if ($prop.Name -ieq $name) { $p = $prop; break }
        }
        if ($null -ne $p) {
            return [string]$p.Value
        }
    }

    return $null
}

function Resolve-EndpointState {
    <#
    .SYNOPSIS
        Normalize a Windows endpoint state to Connected/Disconnected/Unknown.
    .DESCRIPTION
        Active        -> Connected
        Unplugged     -> Disconnected
        NotPresent    -> Disconnected
        missing row   -> Disconnected
        Disabled      -> Unknown (do not switch)
        Error / other -> Unknown (do not switch)
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
        Debounce detected state (Windows endpoint or G HUB payload).
    .DESCRIPTION
        Same as Resolve-HeadsetState without assuming G HUB:
        PayloadPresent true -> Connected; false -> Disconnected after
        OffMissThreshold misses. Returns the same IsOn/Decision/Misses object.
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
        True when HeadsetId and SpeakerId are different.
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
        CancellationTokenSource that cancels after $Milliseconds.
    .DESCRIPTION
        All WebSocket async calls use this token; without CancelAfter
        CloseAsync/ReceiveAsync could hang the runtime indefinitely.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Milliseconds
    )

    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter($Milliseconds)
    return $cts
}

function Test-SvclExportValid {
    <#
    .SYNOPSIS
        True when the text is a valid svcl /scomma export.
    .DESCRIPTION
        A valid export must contain at least one data row and headers exposing
        the columns required by the runtime: 'Item ID' and
        'Device State'. Empty, garbage or incomplete-header text is not
        a valid export -> the caller must treat it as 'Unknown' (not
        'Disconnected').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$CsvText
    )

    if ([string]::IsNullOrWhiteSpace($CsvText)) {
        return $false
    }

    $rows = @(ConvertFrom-SvclCsv -Text $CsvText)
    if ($rows.Count -eq 0) {
        return $false
    }

    # The first row must expose the minimum headers required by the runtime.
    $first = $rows[0]
    $hasItemId    = $null -ne $first.PSObject.Properties['Item ID']
    $hasDeviceState = $null -ne $first.PSObject.Properties['Device State']

    return ($hasItemId -and $hasDeviceState)
}

function Get-SvclRenderDevice {
    <#
    .SYNOPSIS
        Filter svcl.exe /scomma export to real render output endpoints
        with Type='Device' and Direction='Render'.
        
    .DESCRIPTION
        Returns [pscustomobject[]] with filtered rows. Each row keeps
        the real svcl columns: Name, Type, Direction, Device State, Item ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$CsvText
    )

    $rows = @(ConvertFrom-SvclCsv -Text $CsvText)
    if ($rows.Count -eq 0) {
        return @()
    }

    # Explicit loop filter (without Where-Object/$_) for predictable behavior.
    $render = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $typeVal = Get-CsvColumn -Row $row -Names @('Type')
        $dirVal  = Get-CsvColumn -Row $row -Names @('Direction')

        if ($typeVal -ieq 'Device' -and $dirVal -ieq 'Render') {
            $render.Add($row)
        }
    }

    return $render.ToArray()
}

function Get-SvclDeviceLabel {
    <#
    .SYNOPSIS
        Build the display label for an svcl row.
    .DESCRIPTION
        svcl separates Name (for example 'Headphones') from Device Name
        (for example '2- Jabra Evolve 65'). When Device Name exists, display
        'Device Name — Name'; otherwise display Name only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Row
    )

    $name = Get-CsvColumn -Row $Row -Names @('Name')
    $deviceName = Get-CsvColumn -Row $Row -Names @('Device Name')

    if ([string]::IsNullOrWhiteSpace($deviceName)) {
        return $name
    }

    if ([string]::IsNullOrWhiteSpace($name) -or $name -ieq $deviceName) {
        return $deviceName
    }

    return "$deviceName — $name"
}

function Find-SvclRenderDeviceByIdentity {
    <#
    .SYNOPSIS
        Find a Render endpoint by stable svcl identity.
    .DESCRIPTION
        Bluetooth may recreate an endpoint and change its Item ID. To
        re-resolve it without confusing two outputs from the same device,
        compare BOTH columns when available: Device Name and Name.
        Return $null when identity is insufficient or no match exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [string]$DeviceName,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($DeviceName) -and
        [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    foreach ($row in $Rows) {
        $typeVal = Get-CsvColumn -Row $row -Names @('Type')
        $dirVal  = Get-CsvColumn -Row $row -Names @('Direction')
        if ($typeVal -ine 'Device' -or $dirVal -ine 'Render') { continue }

        $rowDeviceName = Get-CsvColumn -Row $row -Names @('Device Name')
        $rowName       = Get-CsvColumn -Row $row -Names @('Name')

        $deviceMatches = [string]::IsNullOrWhiteSpace($DeviceName) -or
            ($null -ne $rowDeviceName -and $rowDeviceName.Trim() -ieq $DeviceName.Trim())
        $nameMatches = [string]::IsNullOrWhiteSpace($Name) -or
            ($null -ne $rowName -and $rowName.Trim() -ieq $Name.Trim())

        if ($deviceMatches -and $nameMatches) {
            return $row
        }
    }

    return $null
}

function Get-EndpointFxState {
    <#
    .SYNOPSIS
        Read the current PKEY_AudioEndpoint_Disable_SysFx state for an endpoint
        without requiring administrator privileges.
    .DESCRIPTION
        Read PKEY_AudioEndpoint_Disable_SysFx from the endpoint FxStore through
        IPolicyConfig::GetPropertyValue (the same store where the elevated helper
        writes). Return $true when enhancements are disabled
        (SysFx=1), $false when enabled (SysFx=0), and $null when the state cannot
        be read (missing endpoint or error). Never throws.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DeviceId
    )

    try {
        # Sentinel = a type that is actually declared by Add-Type. 'AutoSwitch.CoreAudio'
        # does not exist and would make Add-Type retry on every call, failing
        # on the second call because the types already exist.
        $typeName = 'AutoSwitch.EndpointFx'

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

    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")]
    public class CPolicyConfigVistaClient { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IntPtr device);
        [PreserveSig] int GetDevice(string pwstrId, out IntPtr device);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPolicyConfig
    {
        [PreserveSig] int GetMixFormat(string pszDeviceName, out IntPtr ppFormat);
        [PreserveSig] int GetDeviceFormat(string pszDeviceName, bool bDefault, out IntPtr ppFormat);
        [PreserveSig] int ResetDeviceFormat(string pszDeviceName);
        [PreserveSig] int SetDeviceFormat(string pszDeviceName, IntPtr pEndpointFormat, IntPtr pMixFormat);
        [PreserveSig] int GetProcessingPeriod(string pszDeviceName, bool bDefault, out IntPtr pmftDefaultPeriod, out IntPtr pmftMinimumPeriod);
        [PreserveSig] int SetProcessingPeriod(string pszDeviceName, IntPtr pmftPeriod);
        [PreserveSig] int GetShareMode(string pszDeviceName, out IntPtr pMode);
        [PreserveSig] int SetShareMode(string pszDeviceName, IntPtr pMode);
        [PreserveSig] int GetPropertyValue(string pszDeviceName, bool bFxStore, ref PROPERTYKEY key, out PROPVARIANT pv);
        [PreserveSig] int SetPropertyValue(string pszDeviceName, bool bFxStore, ref PROPERTYKEY key, ref PROPVARIANT pv);
        [PreserveSig] int SetDefaultEndpoint(string pszDeviceName, int eRole);
        [PreserveSig] int SetEndpointVisibility(string pszDeviceName, bool bVisible);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IntPtr pInterface);
        [PreserveSig] int OpenPropertyStore(int stgmAccess, out IntPtr ppProperties);
        [PreserveSig] int GetId(out IntPtr ppstrId);
        [PreserveSig] int GetState(out int pdwState);
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint cProps);
        [PreserveSig] int GetAt(uint iProp, out PROPERTYKEY pkey);
        [PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        [PreserveSig] int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        [PreserveSig] int Commit();
    }

    public static class EndpointFx
    {
        private static readonly Guid PKEY_AudioEndpoint_Disable_SysFx =
            new Guid("1da5d803-d492-4edd-8c23-e0c0ffee7f0e");
        private const uint PID_SYSFX = 5;

        // Devuelve: 1 = SysFx deshabilitado, 0 = SysFx habilitado,
        //          -1 = read failed (missing endpoint / COM failure).
        // IMPORTANTE: se lee con IPolicyConfig.GetPropertyValue(deviceId,
        // bFxStore=true), el MISMO store donde el helper elevado escribe. El
        // IPropertyStore del endpoint (OpenPropertyStore) NO contiene
        // PKEY_AudioEndpoint_Disable_SysFx, por lo que leeria siempre
        // "habilitados" aunque esten deshabilitados.
        public static int ReadSysFx(string deviceId)
        {
            object comObj = new CPolicyConfigVistaClient();
            IPolicyConfig policy = (IPolicyConfig)comObj;

            PROPERTYKEY pkey = new PROPERTYKEY();
            pkey.fmtid = PKEY_AudioEndpoint_Disable_SysFx;
            pkey.pid = PID_SYSFX;

            PROPVARIANT pv = new PROPVARIANT();
            int hr = policy.GetPropertyValue(deviceId, true, ref pkey, out pv);
            if (hr != 0)
            {
                return -1; // read failed -> unknown state
            }

            return pv.ulVal != 0 ? 1 : 0;
        }
    }
}
'@ -ErrorAction Stop
        }

        $fx = [AutoSwitch.EndpointFx]::ReadSysFx($DeviceId)
        if ($fx -lt 0) {
            return $null
        }
        return ($fx -eq 1)
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

Export-ModuleMember -Function Get-RenderItemIdFromText, Resolve-HeadsetState, Test-ValidAudioConfig, New-GHubTimeoutToken, ConvertFrom-SvclCsv, ConvertFrom-CsvLine, Get-CsvColumn, Resolve-EndpointState, Resolve-DetectedState, Test-SvclExportValid, Get-SvclRenderDevice, Get-SvclDeviceLabel, Find-SvclRenderDeviceByIdentity, Get-EndpointFxState, Get-ConfigDetectionMode

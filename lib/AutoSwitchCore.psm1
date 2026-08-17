#requires -Version 5.1
# AutoSwitchCore.psm1 - pure, testable logic for Audio AutoSwitch.
# No G HUB or third-party audio utility is required for Pester tests.

Set-StrictMode -Version Latest


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



function Get-DeviceColumn {
    <#
    .SYNOPSIS
        Return the value from the first column whose name matches one of
        $Names case-insensitively. Aliases are supported because some
        render rows name the state column 'State' and others 'Device State'.
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



function Get-DeviceLabel {
    <#
    .SYNOPSIS
        Build the display label for a render device row.
    .DESCRIPTION
        A row separates Name (for example 'Headphones') from Device Name
        (for example '2- Jabra Evolve 65'). When Device Name exists, display
        'Device Name — Name'; otherwise display Name only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Row
    )

    $name = Get-DeviceColumn -Row $Row -Names @('Name')
    $deviceName = Get-DeviceColumn -Row $Row -Names @('Device Name')

    if ([string]::IsNullOrWhiteSpace($deviceName)) {
        return $name
    }

    if ([string]::IsNullOrWhiteSpace($name) -or $name -ieq $deviceName) {
        return $deviceName
    }

    return "$deviceName — $name"
}

function Find-RenderDeviceByIdentity {
    <#
    .SYNOPSIS
        Find a Render endpoint by stable device identity.
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
        $typeVal = Get-DeviceColumn -Row $row -Names @('Type')
        $dirVal  = Get-DeviceColumn -Row $row -Names @('Direction')
        if ($typeVal -ine 'Device' -or $dirVal -ine 'Render') { continue }

        $rowDeviceName = Get-DeviceColumn -Row $row -Names @('Device Name')
        $rowName       = Get-DeviceColumn -Row $row -Names @('Name')

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

        // Returns: 1 = SysFx disabled, 0 = SysFx enabled,
        //          -1 = read failed (missing endpoint / COM failure).
        // IMPORTANTE: se lee con IPolicyConfig.GetPropertyValue(deviceId,
        // bFxStore=true), the SAME store written by the elevated helper. The
        // IPropertyStore del endpoint (OpenPropertyStore) NO contiene
        // PKEY_AudioEndpoint_Disable_SysFx, so reading it there would always
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


function Initialize-CoreAudioBackend {
    <#
    .SYNOPSIS
        Compile the in-process Windows Core Audio COM bridge once.
    .DESCRIPTION
        PowerShell 5.1 cannot reliably cast COM RCWs to custom ComImport
        interfaces, so the COM calls live in embedded C#. Enumeration,
        endpoint state and default-device reads use documented Core Audio
        interfaces. Setting the default endpoint reuses the project's
        existing IPolicyConfig interop for Console, Multimedia and
        Communications roles.
    #>
    [CmdletBinding()]
    param()

    if ('AutoSwitch.NativeAudio.CoreAudio' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace AutoSwitch.NativeAudio
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
        [FieldOffset(8)] public IntPtr pointerVal;
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
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, uint stateMask, out IMMDeviceCollection devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int Item(uint index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IntPtr instance);
        [PreserveSig] int OpenPropertyStore(int accessMode, out IPropertyStore properties);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out uint state);
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PROPERTYKEY key);
        [PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
        [PreserveSig] int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
        [PreserveSig] int Commit();
    }

    [ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPolicyConfig
    {
        [PreserveSig] int GetMixFormat(string deviceName, out IntPtr format);
        [PreserveSig] int GetDeviceFormat(string deviceName, bool defaultFormat, out IntPtr format);
        [PreserveSig] int ResetDeviceFormat(string deviceName);
        [PreserveSig] int SetDeviceFormat(string deviceName, IntPtr endpointFormat, IntPtr mixFormat);
        [PreserveSig] int GetProcessingPeriod(string deviceName, bool defaultPeriod, out IntPtr defaultPeriodValue, out IntPtr minimumPeriodValue);
        [PreserveSig] int SetProcessingPeriod(string deviceName, IntPtr period);
        [PreserveSig] int GetShareMode(string deviceName, out IntPtr mode);
        [PreserveSig] int SetShareMode(string deviceName, IntPtr mode);
        [PreserveSig] int GetPropertyValue(string deviceName, bool fxStore, IntPtr key, IntPtr value);
        [PreserveSig] int SetPropertyValue(string deviceName, bool fxStore, IntPtr key, IntPtr value);
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string deviceName, int role);
        [PreserveSig] int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string deviceName, bool visible);
    }

    public sealed class EndpointInfo
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string DeviceName { get; set; }
        public string FriendlyName { get; set; }
        public uint State { get; set; }
        public string StateName { get; set; }
    }

    public sealed class DefaultEndpointIds
    {
        public string Console { get; set; }
        public string Multimedia { get; set; }
        public string Communications { get; set; }
    }

    public static class CoreAudio
    {
        private const int E_RENDER = 0;
        private const uint DEVICE_STATEMASK_ALL = 0x0000000F;
        private const int STGM_READ = 0;
        private const ushort VT_LPWSTR = 31;

        private static readonly Guid FMTID_DEVICE = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0");
        private static readonly Guid FMTID_DEVICE_INTERFACE = new Guid("026e516e-b814-414b-83cd-856d6fef4822");

        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(ref PROPVARIANT value);

        private static void ThrowIfFailed(int hr)
        {
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);
        }

        private static void Release(object value)
        {
            if (value != null && Marshal.IsComObject(value))
            {
                try { Marshal.ReleaseComObject(value); } catch { }
            }
        }

        private static string ReadString(IPropertyStore store, Guid fmtid, uint pid)
        {
            PROPERTYKEY key = new PROPERTYKEY { fmtid = fmtid, pid = pid };
            PROPVARIANT value = new PROPVARIANT();
            int hr = store.GetValue(ref key, out value);
            if (hr < 0) return null;
            try
            {
                if (value.vt == VT_LPWSTR && value.pointerVal != IntPtr.Zero)
                {
                    return Marshal.PtrToStringUni(value.pointerVal);
                }
                return null;
            }
            finally
            {
                PropVariantClear(ref value);
            }
        }

        private static string GetId(IMMDevice device)
        {
            string id;
            ThrowIfFailed(device.GetId(out id));
            return id;
        }

        private static string StateName(uint state)
        {
            switch (state)
            {
                case 0x00000001: return "Active";
                case 0x00000002: return "Disabled";
                case 0x00000004: return "NotPresent";
                case 0x00000008: return "Unplugged";
                default: return "Unknown";
            }
        }

        public static EndpointInfo[] GetRenderEndpoints()
        {
            object enumeratorObject = null;
            IMMDeviceEnumerator enumerator = null;
            IMMDeviceCollection collection = null;
            var result = new List<EndpointInfo>();

            try
            {
                enumeratorObject = new MMDeviceEnumeratorComObject();
                enumerator = (IMMDeviceEnumerator)enumeratorObject;
                ThrowIfFailed(enumerator.EnumAudioEndpoints(E_RENDER, DEVICE_STATEMASK_ALL, out collection));

                uint count;
                ThrowIfFailed(collection.GetCount(out count));
                for (uint i = 0; i < count; i++)
                {
                    IMMDevice device = null;
                    IPropertyStore store = null;
                    try
                    {
                        ThrowIfFailed(collection.Item(i, out device));
                        string id = GetId(device);
                        uint state;
                        ThrowIfFailed(device.GetState(out state));
                        ThrowIfFailed(device.OpenPropertyStore(STGM_READ, out store));

                        string name = ReadString(store, FMTID_DEVICE, 2);       // PKEY_Device_DeviceDesc
                        string adapter = ReadString(store, FMTID_DEVICE_INTERFACE, 2); // PKEY_DeviceInterface_FriendlyName
                        string friendly = ReadString(store, FMTID_DEVICE, 14); // PKEY_Device_FriendlyName

                        if (String.IsNullOrWhiteSpace(name)) name = friendly;
                        if (String.IsNullOrWhiteSpace(adapter)) adapter = friendly;

                        result.Add(new EndpointInfo
                        {
                            Id = id,
                            Name = name,
                            DeviceName = adapter,
                            FriendlyName = friendly,
                            State = state,
                            StateName = StateName(state)
                        });
                    }
                    finally
                    {
                        Release(store);
                        Release(device);
                    }
                }
            }
            finally
            {
                Release(collection);
                Release(enumerator);
                Release(enumeratorObject);
            }

            return result.ToArray();
        }

        public static string GetDefaultRenderEndpointId(int role)
        {
            object enumeratorObject = null;
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            try
            {
                enumeratorObject = new MMDeviceEnumeratorComObject();
                enumerator = (IMMDeviceEnumerator)enumeratorObject;
                ThrowIfFailed(enumerator.GetDefaultAudioEndpoint(E_RENDER, role, out device));
                return GetId(device);
            }
            finally
            {
                Release(device);
                Release(enumerator);
                Release(enumeratorObject);
            }
        }

        public static DefaultEndpointIds GetDefaultRenderEndpointIds()
        {
            return new DefaultEndpointIds
            {
                Console = GetDefaultRenderEndpointId(0),
                Multimedia = GetDefaultRenderEndpointId(1),
                Communications = GetDefaultRenderEndpointId(2)
            };
        }

        private static void ValidateEndpoint(string deviceId)
        {
            object enumeratorObject = null;
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            try
            {
                enumeratorObject = new MMDeviceEnumeratorComObject();
                enumerator = (IMMDeviceEnumerator)enumeratorObject;
                ThrowIfFailed(enumerator.GetDevice(deviceId, out device));
            }
            finally
            {
                Release(device);
                Release(enumerator);
                Release(enumeratorObject);
            }
        }

        public static void SetDefaultEndpointAllRoles(string deviceId)
        {
            if (String.IsNullOrWhiteSpace(deviceId))
                throw new ArgumentException("deviceId must not be empty", "deviceId");

            ValidateEndpoint(deviceId);

            object policyObject = null;
            IPolicyConfig policy = null;
            try
            {
                policyObject = new CPolicyConfigVistaClient();
                policy = (IPolicyConfig)policyObject;
                ThrowIfFailed(policy.SetDefaultEndpoint(deviceId, 0));
                ThrowIfFailed(policy.SetDefaultEndpoint(deviceId, 1));
                ThrowIfFailed(policy.SetDefaultEndpoint(deviceId, 2));
            }
            finally
            {
                Release(policy);
                Release(policyObject);
            }
        }
    }
}
'@ -ErrorAction Stop
}

function Get-CoreAudioRenderDevices {
    [CmdletBinding()]
    param()

    Initialize-CoreAudioBackend
    $defaultId = $null
    try { $defaultId = [AutoSwitch.NativeAudio.CoreAudio]::GetDefaultRenderEndpointId(0) } catch { }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @([AutoSwitch.NativeAudio.CoreAudio]::GetRenderEndpoints())) {
        $isDefault = $false
        if ($defaultId) { $isDefault = $item.Id -ieq $defaultId }
        $rows.Add([pscustomobject][ordered]@{
            'Name'          = [string]$item.Name
            'Type'          = 'Device'
            'Direction'     = 'Render'
            'Device Name'   = [string]$item.DeviceName
            'Friendly Name' = [string]$item.FriendlyName
            'Device State'  = [string]$item.StateName
            'Item ID'       = [string]$item.Id
            'Default'       = $(if ($isDefault) { 'Render' } else { '' })
        })
    }
    return $rows.ToArray()
}

function Get-CoreAudioDefaultRenderDeviceId {
    [CmdletBinding()]
    param()

    Initialize-CoreAudioBackend
    return [string][AutoSwitch.NativeAudio.CoreAudio]::GetDefaultRenderEndpointId(0)
}

function Get-CoreAudioDefaultRenderDeviceIds {
    [CmdletBinding()]
    param()

    Initialize-CoreAudioBackend
    $ids = [AutoSwitch.NativeAudio.CoreAudio]::GetDefaultRenderEndpointIds()
    return [pscustomobject]@{
        Console        = [string]$ids.Console
        Multimedia     = [string]$ids.Multimedia
        Communications = [string]$ids.Communications
    }
}

function Test-CoreAudioDefaultRenderDevice {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DeviceId)

    try {
        $ids = Get-CoreAudioDefaultRenderDeviceIds
        return ($ids.Console -ieq $DeviceId -and
                $ids.Multimedia -ieq $DeviceId -and
                $ids.Communications -ieq $DeviceId)
    }
    catch {
        return $false
    }
}

function Set-CoreAudioDefaultRenderDevice {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DeviceId)

    Initialize-CoreAudioBackend
    [AutoSwitch.NativeAudio.CoreAudio]::SetDefaultEndpointAllRoles($DeviceId)
}


function Get-ConfigDetectionMode {
    <#
    .SYNOPSIS
        Resolve DetectionMode from a config, including implicit migration.
    .DESCRIPTION
        If $Config already has DetectionMode, return the validated value
        ('WindowsEndpoint' or 'LogitechGHub'). If absent, return
        'LogitechGHub' (comportamiento de configs v1.1.0 y anteriores).
        Return $null when an existing value is invalid.
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

    if ($mode -ieq 'WindowsEndpoint')    { return 'WindowsEndpoint' }
    if ($mode -ieq 'LogitechGHub')       { return 'LogitechGHub' }
    if ($mode -ieq 'SteelSeriesNova5')   { return 'SteelSeriesNova5' }

    return $null
}

function Test-LogitechProXDeviceName {
    <#
    .SYNOPSIS
        True if a G HUB extendedDisplayName matches a Logitech PRO X headset
        (PRO X 2, PRO X Wireless, PRO X, etc.). PRO X 2 and PRO X Wireless
        both expose a LIGHTSPEED endpoint that stays Active when off, so the
        G HUB battery signal is the ON/OFF source for all of them.
    .DESCRIPTION
        Logitech mice are named "G PRO X Superlight" etc.; "PRO X" alone is a
        headset family, so require the "PRO X" token and exclude mouse names.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Name -match '(?i)superlight|mouse') { return $false }

    return ($Name -match '\bPRO\s*X(?:\s*2|\s*Wireless)?\b')
}

function Test-LogitechHeadsetDevice {
    <#
    .SYNOPSIS
        True if a G HUB deviceInfo is a Logitech headset (any model).
    .DESCRIPTION
        Uses the G HUB fields when available: deviceType should indicate a
        headset and capabilities.hasBatteryStatus should be true (that is the
        signal the runtime polls). Falls back to the extendedDisplayName for
        older G HUB responses. Excludes obvious non-headsets (mouse, keyboard,
        receiver, dongle, superlight).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Device
    )

    $name = [string]$Device.extendedDisplayName

    # Strong negative hints first.
    if ($name -match '(?i)superlight|mouse|keyboard|receiver|dongle|adapter|hub\b') {
        return $false
    }

    # Battery capability is what the LogitechGHub runtime actually polls, so it
    # is the deciding signal when the structured fields are present.
    $hasBattery = $false
    $capsProp = $Device.PSObject.Properties['capabilities']
    if ($null -ne $capsProp -and $null -ne $capsProp.Value) {
        $bProp = $capsProp.Value.PSObject.Properties['hasBatteryStatus']
        if ($null -ne $bProp) { $hasBattery = [bool]$bProp.Value }
    }

    # Prefer the structured G HUB fields when present.
    $typeProp = $Device.PSObject.Properties['deviceType']
    if ($null -ne $typeProp -and -not [string]::IsNullOrWhiteSpace([string]$typeProp.Value)) {
        $type = [string]$typeProp.Value
        if ($type -match '(?i)mouse|keyboard|receiver|dongle') { return $false }
        if ($type -match '(?i)headset|headphone|audio') {
            # A headset is only usable in LogitechGHub mode if it exposes a
            # battery signal; otherwise the runtime cannot tell ON from OFF.
            return $hasBattery
        }
    }

    if ($hasBattery) { return $true }

    # Fallback: name heuristic (older G HUB responses without fields).
    return ($name -match '(?i)\bheadset\b|\bheadphone\b|PRO\s*X|G733|G533|G435|G335|G935|G933|Astro')
}

Export-ModuleMember -Function Resolve-HeadsetState, Test-ValidAudioConfig, New-GHubTimeoutToken, Get-DeviceColumn, Resolve-EndpointState, Get-DeviceLabel, Find-RenderDeviceByIdentity, Get-EndpointFxState, Get-ConfigDetectionMode, Test-LogitechProXDeviceName, Test-LogitechHeadsetDevice, Initialize-CoreAudioBackend, Get-CoreAudioRenderDevices, Get-CoreAudioDefaultRenderDeviceId, Get-CoreAudioDefaultRenderDeviceIds, Test-CoreAudioDefaultRenderDevice, Set-CoreAudioDefaultRenderDevice

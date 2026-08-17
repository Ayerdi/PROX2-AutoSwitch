#requires -Version 5.1
<#
    Toggle-AudioEnhancements.ps1 - elevated helper to disable/enable the
    audio enhancements of a specific audio endpoint.

    Launched by the runtime (or installer) with -Verb RunAs. Writes
    PKEY_AudioEndpoint_Disable_SysFx (1da5d803-d492-4edd-8c23-e0c0ffee7f0e, 5)
    ONLY for the specified DeviceId, verifies the result and exits with code:
      0 = change applied and verified
      1 = could not apply or verify (UAC cancelled, missing endpoint, ...)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Disable', 'Enable')]
    [string]$Action
)

$ErrorActionPreference = "Stop"

$LogPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "autoswitch.log"

function Write-AutoSwitchLog {
    param([string]$Message)
    try {
        $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    }
    catch { }
}

try {
    $targetValue = if ($Action -eq 'Disable') { 1 } else { 0 }

    # All COM logic lives in C# (where casting to IPolicyConfig is native and
    # reliable). Casting a COM RCW to a custom [ComImport] interface is
    # unreliable in PowerShell 5.1, so this exposes one static method that
    # performs Set + internal verification.
    $source = @'
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

    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")]
    public class CPolicyConfigVistaClient { }

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

    public static class AudioEnhancements
    {
        private static readonly Guid PKEY_AudioEndpoint_Disable_SysFx =
            new Guid("1da5d803-d492-4edd-8c23-e0c0ffee7f0e");
        private const uint PID_SYSFX = 5;

        public static int SetSysFx(string deviceId, bool disable)
        {
            object comObj = new CPolicyConfigVistaClient();
            IPolicyConfig policy = (IPolicyConfig)comObj;

            PROPERTYKEY pkey = new PROPERTYKEY();
            pkey.fmtid = PKEY_AudioEndpoint_Disable_SysFx;
            pkey.pid = PID_SYSFX;

            PROPVARIANT pv = new PROPVARIANT();
            pv.vt = 19; // VT_UI4
            pv.ulVal = disable ? 1u : 0u;

            int hrSet = policy.SetPropertyValue(deviceId, true, ref pkey, ref pv);
            if (hrSet != 0)
            {
                return hrSet; // negativo (error) -> PowerShell detecta != 0
            }

            // Verificar releendo la propiedad.
            PROPVARIANT pvCheck = new PROPVARIANT();
            int hrGet = policy.GetPropertyValue(deviceId, true, ref pkey, out pvCheck);
            if (hrGet != 0)
            {
                return -hrGet; // read failure -> exit 1
            }

            bool effective = pvCheck.ulVal != 0;
            if (effective != disable)
            {
                return -2; // change was not applied (read-back value differs from target)
            }

            return 0;
        }
    }
}
'@

    Add-Type -TypeDefinition $source -ErrorAction Stop

    $hr = [AutoSwitch.AudioEnhancements]::SetSysFx($DeviceId, ($targetValue -eq 1))
    $actionText = if ($Action -eq 'Disable') { 'disabled' } else { 'enabled' }

    if ($hr -eq 0) {
        Write-AutoSwitchLog ("Enhancements {0} on {1} (SysFx={2})." -f $actionText, $DeviceId, $targetValue)
        exit 0
    }

    Write-AutoSwitchLog ("Enhancements: could not {0} on {1}. Result={2} (0x{2:X8})." -f $actionText, $DeviceId, $hr)
    exit 1
}
catch {
    try {
        Write-AutoSwitchLog ("Enhancements: error: {0}" -f $_.Exception.Message)
    }
    catch { }
    exit 1
}

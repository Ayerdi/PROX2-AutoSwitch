#requires -Version 5.1
<#
    Toggle-AudioEnhancements.ps1 - helper ELEVADO para activar/desactivar
    los audio enhancements de un endpoint de audio concreto.

    Se lanza desde el runtime (o el instalador) con -Verb RunAs. Escribe
    PKEY_AudioEndpoint_Disable_SysFx (1da5d803-d492-4edd-8c23-e0c0ffee7f0e, 5)
    SOLO para el DeviceId indicado, verifica el resultado y sale con codigo:
      0 = cambio aplicado y verificado
      1 = no se pudo aplicar o verificar (UAC cancelado, endpoint inexistente, ...)
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

    # IPolicyConfig (CLSID 870af99c-171d-4f9e-af0d-e63df40c2bc9) permite
    # SetPropertyValue sobre el property store de efectos del endpoint.
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
}
'@ -ErrorAction Stop

    $policyConfig = New-Object AutoSwitch.CPolicyConfigVistaClient
    $policy = [AutoSwitch.IPolicyConfig]$policyConfig

    $pkey = New-Object AutoSwitch.PROPERTYKEY
    $pkey.fmtid = [guid]'1da5d803-d492-4edd-8c23-e0c0ffee7f0e'
    $pkey.pid = 5

    # Escribir el valor objetivo en el FxStore del endpoint.
    $pv = New-Object AutoSwitch.PROPVARIANT
    $pv.vt = 19          # VT_UI4
    $pv.uiVal = $targetValue

    $hrSet = $policy.SetPropertyValue($DeviceId, $true, [ref]$pkey, [ref]$pv)
    if ($hrSet -ne 0) {
        Write-AutoSwitchLog ("Enhancements: SetPropertyValue fallo con HRESULT 0x{0:X8} para {1}" -f $hrSet, $DeviceId)
        exit 1
    }

    # Verificar releendo la propiedad.
    $pvCheck = New-Object AutoSwitch.PROPVARIANT
    $hrGet = $policy.GetPropertyValue($DeviceId, $true, [ref]$pkey, [ref]$pvCheck)

    $effective = $false
    if ($hrGet -eq 0) {
        $effective = ($pvCheck.ulVal -ne 0)
    }

    $actionText = if ($Action -eq 'Disable') { 'deshabilitados' } else { 'habilitados' }

    if ($hrGet -ne 0 -or $effective -ne ($targetValue -ne 0)) {
        Write-AutoSwitchLog (
            "Enhancements: no se pudo verificar el cambio ({0}). HRESULT={1} ValorLeido={2}" -f
            $actionText, $hrGet, $effective
        )
        exit 1
    }

    Write-AutoSwitchLog ("Enhancements {0} en {1} (SysFx={2})." -f $actionText, $DeviceId, $effective)
    exit 0
}
catch {
    try {
        Write-AutoSwitchLog ("Enhancements: error: {0}" -f $_.Exception.Message)
    }
    catch { }
    exit 1
}

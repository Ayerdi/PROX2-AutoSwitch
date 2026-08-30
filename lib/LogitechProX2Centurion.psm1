#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:CenturionInitialized = $false

function Initialize-LogitechProX2Centurion {
    if ($script:CenturionInitialized) { return }

    if ('PROX2AutoSwitch.CenturionProvider' -as [type]) {
        $script:CenturionInitialized = $true
        return
    }

    $source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace PROX2AutoSwitch
{
    public sealed class CenturionStateResult
    {
        public string State = "Unknown";
        public int BatteryPercent = -1;
        public bool OfflineSignatureSeen = false;
        public string Error = "";
        public string Frames = "";
    }

    public static class CenturionProvider
    {
        private const ushort VendorId = 0x046D;
        private const ushort ProductId = 0x0AF7;
        private const ushort TargetUsagePage = 0xFFA0;
        private const byte ReportId = 0x51;

        private const uint DigcfPresent = 0x00000002;
        private const uint DigcfDeviceInterface = 0x00000010;
        private const uint GenericRead = 0x80000000;
        private const uint GenericWrite = 0x40000000;
        private const uint FileShareRead = 0x00000001;
        private const uint FileShareWrite = 0x00000002;
        private const uint OpenExisting = 3;

        private static readonly IntPtr InvalidHandle = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)]
        private struct SpDeviceInterfaceData
        {
            public uint Size;
            public Guid InterfaceClassGuid;
            public uint Flags;
            public IntPtr Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct HiddAttributes
        {
            public int Size;
            public ushort VendorId;
            public ushort ProductId;
            public ushort VersionNumber;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct HidpCaps
        {
            public ushort Usage;
            public ushort UsagePage;
            public ushort InputReportByteLength;
            public ushort OutputReportByteLength;
            public ushort FeatureReportByteLength;

            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)]
            public ushort[] Reserved;

            public ushort NumberLinkCollectionNodes;
            public ushort NumberInputButtonCaps;
            public ushort NumberInputValueCaps;
            public ushort NumberInputDataIndices;
            public ushort NumberOutputButtonCaps;
            public ushort NumberOutputValueCaps;
            public ushort NumberOutputDataIndices;
            public ushort NumberFeatureButtonCaps;
            public ushort NumberFeatureValueCaps;
            public ushort NumberFeatureDataIndices;
        }

        private sealed class Endpoint
        {
            public string Path;
            public int InputLength;
            public int OutputLength;
        }

        [DllImport("hid.dll")]
        private static extern void HidD_GetHidGuid(out Guid hidGuid);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_GetAttributes(IntPtr device, ref HiddAttributes attributes);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_GetPreparsedData(IntPtr device, out IntPtr preparsedData);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_FreePreparsedData(IntPtr preparsedData);

        [DllImport("hid.dll")]
        private static extern int HidP_GetCaps(IntPtr preparsedData, out HidpCaps caps);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_SetOutputReport(IntPtr device, byte[] buffer, uint length);

        [DllImport("setupapi.dll", SetLastError = true)]
        private static extern IntPtr SetupDiGetClassDevs(
            ref Guid classGuid,
            IntPtr enumerator,
            IntPtr parentWindow,
            uint flags);

        [DllImport("setupapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiEnumDeviceInterfaces(
            IntPtr set,
            IntPtr deviceInfoData,
            ref Guid interfaceGuid,
            uint memberIndex,
            ref SpDeviceInterfaceData data);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiGetDeviceInterfaceDetail(
            IntPtr set,
            ref SpDeviceInterfaceData data,
            IntPtr detail,
            uint detailSize,
            ref uint requiredSize,
            IntPtr deviceInfoData);

        [DllImport("setupapi.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool WriteFile(
            IntPtr file,
            byte[] buffer,
            uint bytesToWrite,
            out uint bytesWritten,
            IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ReadFile(
            IntPtr file,
            byte[] buffer,
            uint bytesToRead,
            out uint bytesRead,
            IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CancelIoEx(IntPtr file, IntPtr overlapped);

        private static Endpoint FindEndpoint()
        {
            Guid hidGuid;
            HidD_GetHidGuid(out hidGuid);

            IntPtr set = SetupDiGetClassDevs(
                ref hidGuid,
                IntPtr.Zero,
                IntPtr.Zero,
                DigcfPresent | DigcfDeviceInterface);

            if (set == InvalidHandle)
                return null;

            try
            {
                for (uint index = 0; ; index++)
                {
                    SpDeviceInterfaceData data = new SpDeviceInterfaceData();
                    data.Size = (uint)Marshal.SizeOf(typeof(SpDeviceInterfaceData));

                    if (!SetupDiEnumDeviceInterfaces(
                        set,
                        IntPtr.Zero,
                        ref hidGuid,
                        index,
                        ref data))
                        break;

                    uint required = 0;
                    SetupDiGetDeviceInterfaceDetail(
                        set,
                        ref data,
                        IntPtr.Zero,
                        0,
                        ref required,
                        IntPtr.Zero);

                    if (required == 0)
                        continue;

                    IntPtr detail = Marshal.AllocHGlobal((int)required);
                    try
                    {
                        Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);

                        if (!SetupDiGetDeviceInterfaceDetail(
                            set,
                            ref data,
                            detail,
                            required,
                            ref required,
                            IntPtr.Zero))
                            continue;

                        string path = Marshal.PtrToStringUni(
                            new IntPtr(detail.ToInt64() + 4));

                        if (String.IsNullOrEmpty(path))
                            continue;

                        IntPtr handle = CreateFile(
                            path,
                            GenericRead | GenericWrite,
                            FileShareRead | FileShareWrite,
                            IntPtr.Zero,
                            OpenExisting,
                            0,
                            IntPtr.Zero);

                        if (handle == InvalidHandle)
                            continue;

                        try
                        {
                            HiddAttributes attributes = new HiddAttributes();
                            attributes.Size = Marshal.SizeOf(typeof(HiddAttributes));

                            if (!HidD_GetAttributes(handle, ref attributes) ||
                                attributes.VendorId != VendorId ||
                                attributes.ProductId != ProductId)
                                continue;

                            IntPtr preparsedData;
                            if (!HidD_GetPreparsedData(handle, out preparsedData))
                                continue;

                            try
                            {
                                HidpCaps caps;
                                int status = HidP_GetCaps(preparsedData, out caps);
                                if (status == 0x00110000 &&
                                    caps.UsagePage == TargetUsagePage &&
                                    caps.Usage == 0x0001)
                                {
                                    Endpoint endpoint = new Endpoint();
                                    endpoint.Path = path;
                                    endpoint.InputLength = caps.InputReportByteLength > 0
                                        ? caps.InputReportByteLength
                                        : 64;
                                    endpoint.OutputLength = caps.OutputReportByteLength > 0
                                        ? caps.OutputReportByteLength
                                        : 64;
                                    return endpoint;
                                }
                            }
                            finally
                            {
                                HidD_FreePreparsedData(preparsedData);
                            }
                        }
                        finally
                        {
                            CloseHandle(handle);
                        }
                    }
                    finally
                    {
                        Marshal.FreeHGlobal(detail);
                    }
                }
            }
            finally
            {
                SetupDiDestroyDeviceInfoList(set);
            }

            return null;
        }

        private static byte[] ReadOne(IntPtr handle, int length, int timeoutMilliseconds)
        {
            byte[] buffer = new byte[length];
            uint bytesRead = 0;
            using (ManualResetEvent completed = new ManualResetEvent(false))
            {
                Thread cancel = new Thread(delegate()
                {
                    if (!completed.WaitOne(timeoutMilliseconds))
                        CancelIoEx(handle, IntPtr.Zero);
                });
                cancel.IsBackground = true;
                cancel.Start();

                bool ok = ReadFile(
                    handle,
                    buffer,
                    (uint)buffer.Length,
                    out bytesRead,
                    IntPtr.Zero);

                completed.Set();
                cancel.Join(100);

                if (!ok || bytesRead < 1)
                    return null;
            }

            if (bytesRead == buffer.Length)
                return buffer;

            byte[] exact = new byte[bytesRead];
            Buffer.BlockCopy(buffer, 0, exact, 0, (int)bytesRead);
            return exact;
        }

        private static bool IsBatteryResponse(byte[] packet)
        {
            return packet != null &&
                packet.Length >= 13 &&
                packet[0] == ReportId &&
                packet[1] == 0x0B &&
                packet[8] == 0x04 &&
                packet[10] <= 100;
        }

        // Physical OFF signature captured repeatedly from a PRO X 2 LIGHTSPEED
        // (firmware 1.2.2) while its LIGHTSPEED receiver remained attached.
        // A second outer debounce is applied by the PowerShell runtime before
        // any audio output is changed.
        private static bool IsObservedOfflineSignature(byte[] packet)
        {
            return packet != null &&
                packet.Length >= 8 &&
                packet[0] == ReportId &&
                packet[1] == 0x05 &&
                packet[2] == 0x00 &&
                packet[3] == 0xFF &&
                packet[4] == 0x03 &&
                packet[5] == 0x1A &&
                packet[6] == 0x0B &&
                packet[7] == 0x00;
        }

        private static string ToHex(byte[] packet)
        {
            if (packet == null)
                return "<timeout/no-frame>";

            int count = Math.Min(packet.Length, 16);
            StringBuilder builder = new StringBuilder();
            for (int i = 0; i < count; i++)
            {
                if (i > 0)
                    builder.Append(' ');
                builder.Append(packet[i].ToString("X2"));
            }
            if (packet.Length > count)
                builder.Append(" ...");
            return builder.ToString();
        }

        public static CenturionStateResult Query(int readTimeoutMilliseconds, int maxFrames)
        {
            CenturionStateResult result = new CenturionStateResult();
            Endpoint endpoint = FindEndpoint();
            if (endpoint == null)
            {
                result.Error = "Centurion endpoint 046D:0AF7 / FFA0 was not found.";
                return result;
            }

            IntPtr handle = CreateFile(
                endpoint.Path,
                GenericRead | GenericWrite,
                FileShareRead | FileShareWrite,
                IntPtr.Zero,
                OpenExisting,
                0,
                IntPtr.Zero);

            if (handle == InvalidHandle)
            {
                result.Error = "Could not open the Centurion HID endpoint. Win32=" +
                    Marshal.GetLastWin32Error();
                return result;
            }

            try
            {
                if (endpoint.OutputLength < 10 || endpoint.InputLength < 13)
                {
                    result.Error = "Unexpected Centurion HID report sizes.";
                    return result;
                }

                byte[] request = new byte[endpoint.OutputLength];
                request[0] = ReportId;
                request[1] = 0x08;
                request[3] = 0x03;
                request[4] = 0x1A;
                request[6] = 0x03;
                request[8] = 0x04;
                request[9] = 0x0A;

                uint written;
                bool wrote = WriteFile(
                    handle,
                    request,
                    (uint)request.Length,
                    out written,
                    IntPtr.Zero);

                if (!wrote || written != request.Length)
                {
                    if (!HidD_SetOutputReport(handle, request, (uint)request.Length))
                    {
                        result.Error = "Could not send the Centurion query. Win32=" +
                            Marshal.GetLastWin32Error();
                        return result;
                    }
                }

                bool offlineSignatureSeen = false;
                List<string> frames = new List<string>();

                for (int index = 0; index < maxFrames; index++)
                {
                    byte[] frame = ReadOne(handle, endpoint.InputLength, readTimeoutMilliseconds);
                    frames.Add("#" + (index + 1) + " " + ToHex(frame));

                    if (frame == null)
                        break;

                    if (IsBatteryResponse(frame))
                    {
                        result.State = "Connected";
                        result.BatteryPercent = frame[10];
                        result.Frames = String.Join(" | ", frames.ToArray());
                        return result;
                    }

                    if (IsObservedOfflineSignature(frame))
                    {
                        offlineSignatureSeen = true;
                        result.OfflineSignatureSeen = true;
                    }
                }

                result.Frames = String.Join(" | ", frames.ToArray());
                if (offlineSignatureSeen)
                {
                    result.State = "Disconnected";
                    return result;
                }

                result.Error = "No valid battery response and no known OFF signature.";
                return result;
            }
            finally
            {
                CloseHandle(handle);
            }
        }
    }
}
'@

    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
    $script:CenturionInitialized = $true
}

function Test-LogitechProX2CenturionConfig {
    param([Parameter(Mandatory = $true)][object]$Config)

    $displayName = ''
    if ($Config.PSObject.Properties['GHubDisplayName']) {
        $displayName = [string]$Config.GHubDisplayName
    }
    $headsetName = ''
    if ($Config.PSObject.Properties['HeadsetName']) {
        $headsetName = [string]$Config.HeadsetName
    }

    return ($displayName -match '(?i)PRO\s*X\s*2') -or
        ($headsetName -match '(?i)PRO\s*X\s*2')
}

function Get-LogitechProX2CenturionState {
    param(
        [ValidateRange(100, 5000)][int]$ReadTimeoutMilliseconds = 450,
        [ValidateRange(1, 10)][int]$MaxFrames = 4
    )

    Initialize-LogitechProX2Centurion
    return [PROX2AutoSwitch.CenturionProvider]::Query(
        $ReadTimeoutMilliseconds,
        $MaxFrames
    )
}

Export-ModuleMember -Function @(
    'Initialize-LogitechProX2Centurion',
    'Test-LogitechProX2CenturionConfig',
    'Get-LogitechProX2CenturionState'
)

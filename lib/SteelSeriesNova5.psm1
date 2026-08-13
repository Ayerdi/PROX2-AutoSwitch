#requires -Version 5.1
# SteelSeriesNova5.psm1 - physical ON/OFF detection for Arctis Nova 5/5X.
#
# Protocol reference (reverse engineered by HeadsetControl):
#   VID 0x1038
#   PID 0x2232 (Nova 5), 0x2253 (Nova 5X)
#   HID UsagePage 0xFFC0, Usage 0x0001
#   status request: 00 B0
#   response byte[1] == 0x02 => headset offline
#
# No SteelSeries GG or third-party DLL is required. The C# helper uses the
# Windows HID/SetupAPI APIs already present in the operating system.

Set-StrictMode -Version Latest

function Resolve-SteelSeriesNova5Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Data
    )

    # HeadsetControl rejects responses shorter than 16 bytes. Do the same:
    # a malformed/partial response is Unknown, never interpreted as OFF.
    if ($null -eq $Data -or $Data.Length -lt 16) {
        return 'Unknown'
    }

    if ($Data[1] -eq 0x02) {
        return 'Disconnected'
    }

    return 'Connected'
}

function Initialize-SteelSeriesNova5Hid {
    if ('AutoSwitch.SteelSeriesNova5Hid' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace AutoSwitch
{
    public static class SteelSeriesNova5Hid
    {
        private const ushort VID_STEELSERIES = 0x1038;
        private const ushort PID_NOVA5 = 0x2232;
        private const ushort PID_NOVA5X = 0x2253;
        private const ushort USAGE_PAGE = 0xFFC0;
        private const ushort USAGE = 0x0001;

        private const uint DIGCF_PRESENT = 0x00000002;
        private const uint DIGCF_DEVICEINTERFACE = 0x00000010;
        private const uint GENERIC_READ = 0x80000000;
        private const uint GENERIC_WRITE = 0x40000000;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_FLAG_OVERLAPPED = 0x40000000;
        private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)]
        private struct SP_DEVICE_INTERFACE_DATA
        {
            public int cbSize;
            public Guid InterfaceClassGuid;
            public int Flags;
            public IntPtr Reserved;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct SP_DEVICE_INTERFACE_DETAIL_DATA
        {
            public int cbSize;

            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 512)]
            public string DevicePath;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct HIDD_ATTRIBUTES
        {
            public int Size;
            public ushort VendorID;
            public ushort ProductID;
            public ushort VersionNumber;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct HIDP_CAPS
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

        [DllImport("hid.dll")]
        private static extern void HidD_GetHidGuid(out Guid HidGuid);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_GetAttributes(SafeFileHandle HidDeviceObject, ref HIDD_ATTRIBUTES Attributes);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_GetPreparsedData(SafeFileHandle HidDeviceObject, out IntPtr PreparsedData);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_FreePreparsedData(IntPtr PreparsedData);

        [DllImport("hid.dll")]
        private static extern int HidP_GetCaps(IntPtr PreparsedData, out HIDP_CAPS Capabilities);

        [DllImport("setupapi.dll", SetLastError = true)]
        private static extern IntPtr SetupDiGetClassDevs(
            ref Guid ClassGuid,
            IntPtr Enumerator,
            IntPtr hwndParent,
            uint Flags);

        [DllImport("setupapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiEnumDeviceInterfaces(
            IntPtr DeviceInfoSet,
            IntPtr DeviceInfoData,
            ref Guid InterfaceClassGuid,
            uint MemberIndex,
            ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiGetDeviceInterfaceDetail(
            IntPtr DeviceInfoSet,
            ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData,
            ref SP_DEVICE_INTERFACE_DETAIL_DATA DeviceInterfaceDetailData,
            uint DeviceInterfaceDetailDataSize,
            out uint RequiredSize,
            IntPtr DeviceInfoData);

        [DllImport("setupapi.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile);

        private sealed class Candidate : IDisposable
        {
            public SafeFileHandle Handle;
            public HIDP_CAPS Caps;

            public void Dispose()
            {
                if (Handle != null && !Handle.IsInvalid)
                    Handle.Dispose();
            }
        }

        private static bool IsSupportedPid(ushort pid)
        {
            return pid == PID_NOVA5 || pid == PID_NOVA5X;
        }

        private static Candidate OpenReceiver()
        {
            Guid hidGuid;
            HidD_GetHidGuid(out hidGuid);

            IntPtr set = SetupDiGetClassDevs(
                ref hidGuid,
                IntPtr.Zero,
                IntPtr.Zero,
                DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);

            if (set == INVALID_HANDLE_VALUE)
                return null;

            try
            {
                for (uint index = 0; ; index++)
                {
                    SP_DEVICE_INTERFACE_DATA iface = new SP_DEVICE_INTERFACE_DATA();
                    iface.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));

                    if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hidGuid, index, ref iface))
                        break;

                    SP_DEVICE_INTERFACE_DETAIL_DATA detail = new SP_DEVICE_INTERFACE_DETAIL_DATA();
                    detail.cbSize = IntPtr.Size == 8 ? 8 : 6;

                    uint required;
                    uint detailSize = (uint)Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DETAIL_DATA));
                    if (!SetupDiGetDeviceInterfaceDetail(set, ref iface, ref detail, detailSize, out required, IntPtr.Zero))
                        continue;

                    SafeFileHandle handle = CreateFile(
                        detail.DevicePath,
                        GENERIC_READ | GENERIC_WRITE,
                        FILE_SHARE_READ | FILE_SHARE_WRITE,
                        IntPtr.Zero,
                        OPEN_EXISTING,
                        FILE_FLAG_OVERLAPPED,
                        IntPtr.Zero);

                    if (handle == null || handle.IsInvalid)
                    {
                        if (handle != null) handle.Dispose();
                        continue;
                    }

                    HIDD_ATTRIBUTES attrs = new HIDD_ATTRIBUTES();
                    attrs.Size = Marshal.SizeOf(typeof(HIDD_ATTRIBUTES));
                    if (!HidD_GetAttributes(handle, ref attrs) ||
                        attrs.VendorID != VID_STEELSERIES ||
                        !IsSupportedPid(attrs.ProductID))
                    {
                        handle.Dispose();
                        continue;
                    }

                    IntPtr preparsed = IntPtr.Zero;
                    try
                    {
                        if (!HidD_GetPreparsedData(handle, out preparsed) || preparsed == IntPtr.Zero)
                        {
                            handle.Dispose();
                            continue;
                        }

                        HIDP_CAPS caps;
                        // HIDP_STATUS_SUCCESS == 0x00110000.
                        if (HidP_GetCaps(preparsed, out caps) != 0x00110000 ||
                            caps.UsagePage != USAGE_PAGE || caps.Usage != USAGE)
                        {
                            handle.Dispose();
                            continue;
                        }

                        Candidate candidate = new Candidate();
                        candidate.Handle = handle;
                        candidate.Caps = caps;
                        return candidate;
                    }
                    finally
                    {
                        if (preparsed != IntPtr.Zero)
                            HidD_FreePreparsedData(preparsed);
                    }
                }
            }
            finally
            {
                SetupDiDestroyDeviceInfoList(set);
            }

            return null;
        }

        public static bool ReceiverPresent()
        {
            using (Candidate receiver = OpenReceiver())
            {
                return receiver != null;
            }
        }

        private static bool WaitAndComplete(IAsyncResult asyncResult, int timeoutMs, Action<IAsyncResult> complete)
        {
            if (!asyncResult.AsyncWaitHandle.WaitOne(timeoutMs))
                return false;

            complete(asyncResult);
            return true;
        }

        // Returns the raw HID status response, or null when the receiver cannot
        // be queried safely. Callers must treat null as Unknown, never as OFF.
        public static byte[] QueryStatus(int timeoutMs)
        {
            if (timeoutMs < 100) timeoutMs = 100;

            using (Candidate receiver = OpenReceiver())
            {
                if (receiver == null)
                    return null;

                int outputLength = Math.Max(2, (int)receiver.Caps.OutputReportByteLength);
                int inputLength = Math.Max(128, (int)receiver.Caps.InputReportByteLength);

                byte[] request = new byte[outputLength];
                request[0] = 0x00; // report ID
                request[1] = 0xB0; // SteelSeries Nova status request

                byte[] response = new byte[inputLength];

                try
                {
                    using (FileStream stream = new FileStream(receiver.Handle, FileAccess.ReadWrite, 4096, true))
                    {
                        // Ownership moves to FileStream; prevent Candidate from
                        // closing the handle twice.
                        receiver.Handle = null;

                        IAsyncResult write = stream.BeginWrite(request, 0, request.Length, null, null);
                        if (!WaitAndComplete(write, timeoutMs, stream.EndWrite))
                            return null;

                        IAsyncResult read = stream.BeginRead(response, 0, response.Length, null, null);
                        int count = -1;
                        if (!read.AsyncWaitHandle.WaitOne(timeoutMs))
                            return null;
                        count = stream.EndRead(read);

                        if (count <= 0)
                            return null;

                        byte[] exact = new byte[count];
                        Buffer.BlockCopy(response, 0, exact, 0, count);
                        return exact;
                    }
                }
                catch
                {
                    return null;
                }
            }
        }
    }
}
'@ -ErrorAction Stop
}

function Test-SteelSeriesNova5Receiver {
    [CmdletBinding()]
    param()

    try {
        Initialize-SteelSeriesNova5Hid
        return [AutoSwitch.SteelSeriesNova5Hid]::ReceiverPresent()
    }
    catch {
        return $false
    }
}

function Get-SteelSeriesNova5State {
    [CmdletBinding()]
    param(
        [int]$TimeoutMilliseconds = 800
    )

    try {
        Initialize-SteelSeriesNova5Hid
        $data = [AutoSwitch.SteelSeriesNova5Hid]::QueryStatus($TimeoutMilliseconds)
        if ($null -eq $data) {
            return 'Unknown'
        }
        return Resolve-SteelSeriesNova5Status -Data $data
    }
    catch {
        return 'Unknown'
    }
}

Export-ModuleMember -Function Resolve-SteelSeriesNova5Status, Test-SteelSeriesNova5Receiver, Get-SteelSeriesNova5State

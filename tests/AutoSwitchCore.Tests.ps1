#requires -Version 5.1
# Pester tests for lib/AutoSwitchCore.psm1

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\AutoSwitchCore.psm1') -Force
}


Describe 'Resolve-HeadsetState' {
    It 'switches OFF only after OffMissThreshold consecutive empty responses' {
        $state = Resolve-HeadsetState -PayloadPresent $true -Misses 0 -OffMissThreshold 2
        $state.IsOn | Should -Be $true
        $state.Misses | Should -Be 0

        $state = Resolve-HeadsetState -PayloadPresent $false -Misses 0 -OffMissThreshold 2
        $state.IsOn | Should -Be $false
        $state.Decision | Should -Be $false
        $state.Misses | Should -Be 1

        $state = Resolve-HeadsetState -PayloadPresent $false -Misses 1 -OffMissThreshold 2
        $state.IsOn | Should -Be $false
        $state.Decision | Should -Be $true
        $state.Misses | Should -Be 2
    }

    It 'a single empty response followed by a valid payload must not trigger OFF' {
        $state = Resolve-HeadsetState -PayloadPresent $false -Misses 0 -OffMissThreshold 2
        $state.Decision | Should -Be $false

        $state = Resolve-HeadsetState -PayloadPresent $true -Misses $state.Misses -OffMissThreshold 2
        $state.IsOn | Should -Be $true
        $state.Decision | Should -Be $true
        $state.Misses | Should -Be 0
    }

    It 'payload present resets the miss counter' {
        $state = Resolve-HeadsetState -PayloadPresent $true -Misses 5 -OffMissThreshold 2
        $state.Misses | Should -Be 0
        $state.IsOn | Should -Be $true
    }
}

Describe 'Test-ValidAudioConfig' {
    It 'rejects identical headset and speaker Item IDs' {
        Test-ValidAudioConfig -HeadsetId '{0.0.0.00000000}.{1A2B3C4D-5E6F-7890-ABCD-EF1234567890}' -SpeakerId '{0.0.0.00000000}.{1A2B3C4D-5E6F-7890-ABCD-EF1234567890}' | Should -Be $false
    }

    It 'accepts distinct headset and speaker Item IDs' {
        Test-ValidAudioConfig -HeadsetId '{0.0.0.00000000}.{11111111-2222-3333-4444-555555555555}' -SpeakerId '{0.0.0.00000000}.{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}' | Should -Be $true
    }
}

Describe 'New-GHubTimeoutToken' {
    It 'returns a token that cancels itself after the requested interval' {
        $cts = New-GHubTimeoutToken -Milliseconds 50
        $cts.Token.IsCancellationRequested | Should -Be $false

        Start-Sleep -Milliseconds 150
        $cts.Token.IsCancellationRequested | Should -Be $true
        $cts.Dispose()
    }

    It 'accepts and applies a large interval' {
        $cts = New-GHubTimeoutToken -Milliseconds 60000
        $cts.Token.IsCancellationRequested | Should -Be $false
        $cts.Dispose()
    }
}




Describe 'Get-DeviceLabel' {
    It 'combines Device Name and Name when both exist' {
        $row = [pscustomobject]@{ Name = 'Headphones'; 'Device Name' = '2- Jabra Evolve 65' }
        Get-DeviceLabel -Row $row | Should -Be '2- Jabra Evolve 65 — Headphones'
    }

    It 'falls back to Name when Device Name is missing' {
        $row = [pscustomobject]@{ Name = 'Speakers' }
        Get-DeviceLabel -Row $row | Should -Be 'Speakers'
    }

    It 'falls back to Device Name when Name is missing or identical' {
        $row = [pscustomobject]@{ Name = 'Speakers (Application)'; 'Device Name' = 'Speakers (Application)' }
        Get-DeviceLabel -Row $row | Should -Be 'Speakers (Application)'
    }
}

Describe 'Find-RenderDeviceByIdentity' {
    It 'matches the Jabra render endpoint by Device Name + Name' {
        $rows = @(
            [pscustomobject]@{ Type='Device'; Direction='Render'; 'Device Name'='2- Jabra Evolve 65'; Name='Headphones'; 'Item ID'='{0.0.0.00000000}.{ed043b5e-65dc-4ba6-a847-310517ac1849}' }
        )
        $row = Find-RenderDeviceByIdentity -Rows $rows -DeviceName '2- Jabra Evolve 65' -Name 'Headphones'
        $row | Should -Not -BeNullOrEmpty
        $row.'Item ID' | Should -Be '{0.0.0.00000000}.{ed043b5e-65dc-4ba6-a847-310517ac1849}'
    }

    It 'does not confuse two render endpoints from the same device' {
        $rows = @(
            [pscustomobject]@{ Type='Device'; Direction='Render'; 'Device Name'='BT Headset'; Name='Stereo'; 'Item ID'='stereo' },
            [pscustomobject]@{ Type='Device'; Direction='Render'; 'Device Name'='BT Headset'; Name='Hands-Free'; 'Item ID'='handsfree' }
        )
        $row = Find-RenderDeviceByIdentity -Rows $rows -DeviceName 'BT Headset' -Name 'Hands-Free'
        $row.'Item ID' | Should -Be 'handsfree'
    }

    It 'can match by Name alone when Device Name is unavailable' {
        $rows = @([pscustomobject]@{ Type='Device'; Direction='Render'; Name='USB Headphones'; 'Item ID'='usb' })
        $row = Find-RenderDeviceByIdentity -Rows $rows -Name 'USB Headphones'
        $row.'Item ID' | Should -Be 'usb'
    }

    It 'returns null when no stable identity was supplied' {
        $rows = @(
            [pscustomobject]@{ Type='Device'; Direction='Render'; 'Device Name'='2- Jabra Evolve 65'; Name='Headphones'; 'Item ID'='x' }
        )
        Find-RenderDeviceByIdentity -Rows $rows | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-EndpointState' {
    It 'maps Active to Connected' {
        Resolve-EndpointState -State 'Active' | Should -Be 'Connected'
    }

    It 'maps Unplugged and NotPresent to Disconnected' {
        Resolve-EndpointState -State 'Unplugged' | Should -Be 'Disconnected'
        Resolve-EndpointState -State 'NotPresent' | Should -Be 'Disconnected'
    }

    It 'maps Disabled to Unknown (never switch)' {
        Resolve-EndpointState -State 'Disabled' | Should -Be 'Unknown'
    }

    It 'maps any other value to Unknown' {
        Resolve-EndpointState -State 'Error' | Should -Be 'Unknown'
        Resolve-EndpointState -State ' ' | Should -Be 'Unknown'
        Resolve-EndpointState -State 'Active ' | Should -Be 'Connected'
    }
}


Describe 'Get-DeviceColumn' {
    It 'finds a column by exact name' {
        $row = [pscustomobject]@{ Name = 'X'; State = 'Active' }
        Get-DeviceColumn -Row $row -Names @('State') | Should -Be 'Active'
    }

    It 'falls back to alias names (State vs DeviceState)' {
        $row = [pscustomobject]@{ Name = 'X'; DeviceState = 'Unplugged' }
        Get-DeviceColumn -Row $row -Names @('State', 'DeviceState') | Should -Be 'Unplugged'
    }

    It 'returns null when no column matches' {
        $row = [pscustomobject]@{ Name = 'X' }
        Get-DeviceColumn -Row $row -Names @('State', 'DeviceState') | Should -BeNullOrEmpty
    }
}

Describe 'Get-ConfigDetectionMode' {
    It 'returns WindowsEndpoint when set' {
        $cfg = [pscustomobject]@{ DetectionMode = 'WindowsEndpoint'; HeadsetId = 'x' }
        Get-ConfigDetectionMode -Config $cfg | Should -Be 'WindowsEndpoint'
    }

    It 'returns LogitechGHub when set' {
        $cfg = [pscustomobject]@{ DetectionMode = 'LogitechGHub'; HeadsetId = 'x' }
        Get-ConfigDetectionMode -Config $cfg | Should -Be 'LogitechGHub'
    }

    It 'defaults to LogitechGHub for old configs without DetectionMode' {
        $cfg = [pscustomobject]@{ Version = '1.1.0'; HeadsetId = 'x' }
        Get-ConfigDetectionMode -Config $cfg | Should -Be 'LogitechGHub'
    }

    It 'returns null for an invalid value' {
        $cfg = [pscustomobject]@{ DetectionMode = 'Foo'; HeadsetId = 'x' }
        Get-ConfigDetectionMode -Config $cfg | Should -BeNullOrEmpty
    }

    It 'returns SteelSeriesNova5 when set' {
        $cfg = [pscustomobject]@{ DetectionMode = 'SteelSeriesNova5'; HeadsetId = 'x' }
        Get-ConfigDetectionMode -Config $cfg | Should -Be 'SteelSeriesNova5'
    }
}

Describe 'Test-LogitechProXDeviceName' {
    It 'matches PRO X 2' {
        Test-LogitechProXDeviceName -Name 'PRO X 2 Lightspeed Gaming Headset' | Should -Be $true
    }

    It 'matches PRO X Wireless' {
        Test-LogitechProXDeviceName -Name 'PRO X Wireless Gaming Headset' | Should -Be $true
    }

    It 'matches plain PRO X' {
        Test-LogitechProXDeviceName -Name 'PRO X Gaming Headset' | Should -Be $true
    }

    It 'rejects non-PRO-X devices' {
        Test-LogitechProXDeviceName -Name 'G PRO X Superlight Mouse' | Should -Be $false
        Test-LogitechProXDeviceName -Name 'G733 Gaming Headset' | Should -Be $false
    }
}

Describe 'Test-LogitechHeadsetDevice' {
    It 'accepts a G HUB deviceInfo with headset type + battery capability' {
        $dev = [pscustomobject]@{
            extendedDisplayName = 'G733 Wireless Gaming Headset'
            deviceType          = 'headset'
            capabilities        = [pscustomobject]@{ hasBatteryStatus = $true }
        }
        Test-LogitechHeadsetDevice -Device $dev | Should -Be $true
    }

    It 'accepts PRO X 2 and PRO X Wireless by name' {
        $d1 = [pscustomobject]@{ extendedDisplayName = 'PRO X 2 Lightspeed Gaming Headset' }
        Test-LogitechHeadsetDevice -Device $d1 | Should -Be $true

        $d2 = [pscustomobject]@{ extendedDisplayName = 'PRO X Wireless Gaming Headset' }
        Test-LogitechHeadsetDevice -Device $d2 | Should -Be $true
    }

    It 'rejects mice, keyboards, receivers and dongles' {
        $mouse    = [pscustomobject]@{ extendedDisplayName = 'G PRO X Superlight Mouse'; deviceType = 'mouse' }
        $keyboard = [pscustomobject]@{ extendedDisplayName = 'G915 Keyboard';           deviceType = 'keyboard' }
        $receiver = [pscustomobject]@{ extendedDisplayName = 'Lightspeed Receiver';     deviceType = 'receiver' }
        Test-LogitechHeadsetDevice -Device $mouse    | Should -Be $false
        Test-LogitechHeadsetDevice -Device $keyboard | Should -Be $false
        Test-LogitechHeadsetDevice -Device $receiver | Should -Be $false
    }

    It 'rejects a headset-typed device without battery capability' {
        # LogitechGHub mode needs the battery signal to tell ON from OFF.
        $dev = [pscustomobject]@{
            extendedDisplayName = 'G733 Wireless Gaming Headset'
            deviceType          = 'headset'
            capabilities        = [pscustomobject]@{ hasBatteryStatus = $false }
        }
        Test-LogitechHeadsetDevice -Device $dev | Should -Be $false
    }

    It 'accepts a device whose type is not headset but has battery' {
        # Some G HUB responses only expose the battery capability.
        $dev = [pscustomobject]@{
            extendedDisplayName = 'Some Wireless Audio Device'
            deviceType          = 'unknown'
            capabilities        = [pscustomobject]@{ hasBatteryStatus = $true }
        }
        Test-LogitechHeadsetDevice -Device $dev | Should -Be $true
    }
}


Describe 'Native Core Audio bridge' {
    It 'exports the native Core Audio commands' {
        (Get-Command Initialize-CoreAudioBackend -ErrorAction Stop).Name | Should -Be 'Initialize-CoreAudioBackend'
        (Get-Command Get-CoreAudioRenderDevices -ErrorAction Stop).Name | Should -Be 'Get-CoreAudioRenderDevices'
        (Get-Command Get-CoreAudioDefaultRenderDeviceId -ErrorAction Stop).Name | Should -Be 'Get-CoreAudioDefaultRenderDeviceId'
        (Get-Command Set-CoreAudioDefaultRenderDevice -ErrorAction Stop).Name | Should -Be 'Set-CoreAudioDefaultRenderDevice'
    }

    It 'compiles the embedded COM bridge without touching hardware' {
        { Initialize-CoreAudioBackend } | Should -Not -Throw
        ('AutoSwitch.NativeAudio.CoreAudio' -as [type]) | Should -Not -BeNullOrEmpty
    }
}

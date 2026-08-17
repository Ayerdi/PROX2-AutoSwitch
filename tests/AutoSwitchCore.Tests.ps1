#requires -Version 5.1
# Pester tests para lib/AutoSwitchCore.psm1

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\AutoSwitchCore.psm1') -Force
    $script:FixtureCsv = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures\svcl-export.csv')
}

Describe 'Get-RenderItemIdFromText' {
    It 'extracts a valid render Item ID' {
        $text = 'Realtek Audio - Default Render Device' + [char]10 + '{0.0.0.00000000}.{1A2B3C4D-5E6F-7890-ABCD-EF1234567890}'
        $id = Get-RenderItemIdFromText -Text $text
        $id | Should -Be '{0.0.0.00000000}.{1a2b3c4d-5e6f-7890-abcd-ef1234567890}'
    }

    It 'rejects output without a valid render Item ID' {
        Get-RenderItemIdFromText -Text 'No items found' | Should -BeNullOrEmpty
    }

    It 'rejects an Item ID that is not a render device (different device class)' {
        # Render device class must be {0.0.0.00000000}; other classes are not render endpoints.
        Get-RenderItemIdFromText -Text '{1.0.0.00000000}.{1A2B3C4D-5E6F-7890-ABCD-EF1234567890}' | Should -BeNullOrEmpty
    }

    It 'extracts only the Item ID even with /Stdout-style contamination' {
        # Regression: /Stdout /GetColumnValue prefija info extra del item.
        $contaminated = '1 item found:' + [char]10 + 'Device name' + [char]10 + '{0.0.0.00000000}.{1A2B3C4D-5E6F-7890-ABCD-EF1234567890}'
        Get-RenderItemIdFromText -Text $contaminated | Should -Be '{0.0.0.00000000}.{1a2b3c4d-5e6f-7890-abcd-ef1234567890}'
    }
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

Describe 'ConvertFrom-SvclCsv' {
    It 'parses a real svcl export (Name and Device Name are separate)' {
        $rows = ConvertFrom-SvclCsv -Text $script:FixtureCsv
        $rows.Count | Should -Be 5
        $rows[0].Name | Should -Be 'Headphones'
        $rows[0].'Device Name' | Should -Be '2- Jabra Evolve 65'
        $rows[0].Type | Should -Be 'Device'
        $rows[0].Direction | Should -Be 'Render'
        $rows[0].'Device State' | Should -Be 'Active'
        $rows[0].'Item ID' | Should -Be '{0.0.0.00000000}.{ed043b5e-65dc-4ba6-a847-310517ac1849}'
    }

    It 'returns empty for header-only or empty input' {
        ConvertFrom-SvclCsv -Text "Name,Type,Direction" | Should -BeNullOrEmpty
        ConvertFrom-SvclCsv -Text "" | Should -BeNullOrEmpty
    }
}

Describe 'Get-SvclRenderDevice' {
    It 'filters to Device + Direction=Render only' {
        $devices = Get-SvclRenderDevice -CsvText $script:FixtureCsv
        $devices.Count | Should -Be 3
        # Must exclude the microphone (Capture) and application rows.
        ($devices | Where-Object { $_.Name -match 'Microphone' }).Count | Should -Be 0
        ($devices | Where-Object { $_.Name -match 'Application' }).Count | Should -Be 0
    }

    It 'keeps the real column names' {
        $devices = Get-SvclRenderDevice -CsvText $script:FixtureCsv
        $devices[0].PSObject.Properties.Name -contains 'Device State' | Should -Be $true
        $devices[0].PSObject.Properties.Name -contains 'Item ID' | Should -Be $true
        $devices[0].PSObject.Properties.Name -contains 'Type' | Should -Be $true
        $devices[0].PSObject.Properties.Name -contains 'Direction' | Should -Be $true
        $devices[0].PSObject.Properties.Name -contains 'Device Name' | Should -Be $true
    }

    It 'returns empty for empty input' {
        Get-SvclRenderDevice -CsvText "" | Should -BeNullOrEmpty
    }
}

Describe 'Test-SvclExportValid' {
    It 'accepts a real svcl export' {
        Test-SvclExportValid -CsvText $script:FixtureCsv | Should -Be $true
    }

    It 'rejects empty or whitespace-only output' {
        Test-SvclExportValid -CsvText "" | Should -Be $false
        Test-SvclExportValid -CsvText "   " | Should -Be $false
    }

    It 'rejects garbage that is not a svcl export' {
        Test-SvclExportValid -CsvText "No items found" | Should -Be $false
        Test-SvclExportValid -CsvText "ERROR: something went wrong" | Should -Be $false
    }

    It 'rejects a header-only export (no data rows)' {
        Test-SvclExportValid -CsvText "Name,Type,Direction" | Should -Be $false
    }

    It 'rejects an export missing Item ID or Device State' {
        # Header/data rows without the columns required by the runtime.
        Test-SvclExportValid -CsvText "Name,Volume`nSpeakers,50" | Should -Be $false
        Test-SvclExportValid -CsvText "Name,Item ID`nSpeakers,{0.0.0.00000000}.{GUID}" | Should -Be $false
    }
}

Describe 'Get-SvclDeviceLabel' {
    It 'combines Device Name and Name when both exist' {
        $row = [pscustomobject]@{ Name = 'Headphones'; 'Device Name' = '2- Jabra Evolve 65' }
        Get-SvclDeviceLabel -Row $row | Should -Be '2- Jabra Evolve 65 — Headphones'
    }

    It 'falls back to Name when Device Name is missing' {
        $row = [pscustomobject]@{ Name = 'Speakers' }
        Get-SvclDeviceLabel -Row $row | Should -Be 'Speakers'
    }

    It 'falls back to Device Name when Name is missing or identical' {
        $row = [pscustomobject]@{ Name = 'Speakers (Application)'; 'Device Name' = 'Speakers (Application)' }
        Get-SvclDeviceLabel -Row $row | Should -Be 'Speakers (Application)'
    }
}

Describe 'Find-SvclRenderDeviceByIdentity' {
    It 'matches the Jabra render endpoint by Device Name + Name' {
        $rows = @(ConvertFrom-SvclCsv -Text $script:FixtureCsv)
        $row = Find-SvclRenderDeviceByIdentity -Rows $rows -DeviceName '2- Jabra Evolve 65' -Name 'Headphones'
        $row | Should -Not -BeNullOrEmpty
        $row.'Item ID' | Should -Be '{0.0.0.00000000}.{ed043b5e-65dc-4ba6-a847-310517ac1849}'
    }

    It 'does not confuse two render endpoints from the same device' {
        $rows = @(
            [pscustomobject]@{ Type='Device'; Direction='Render'; 'Device Name'='BT Headset'; Name='Stereo'; 'Item ID'='stereo' },
            [pscustomobject]@{ Type='Device'; Direction='Render'; 'Device Name'='BT Headset'; Name='Hands-Free'; 'Item ID'='handsfree' }
        )
        $row = Find-SvclRenderDeviceByIdentity -Rows $rows -DeviceName 'BT Headset' -Name 'Hands-Free'
        $row.'Item ID' | Should -Be 'handsfree'
    }

    It 'can match by Name alone when Device Name is unavailable' {
        $rows = @([pscustomobject]@{ Type='Device'; Direction='Render'; Name='USB Headphones'; 'Item ID'='usb' })
        $row = Find-SvclRenderDeviceByIdentity -Rows $rows -Name 'USB Headphones'
        $row.'Item ID' | Should -Be 'usb'
    }

    It 'returns null when no stable identity was supplied' {
        $rows = @(ConvertFrom-SvclCsv -Text $script:FixtureCsv)
        Find-SvclRenderDeviceByIdentity -Rows $rows | Should -BeNullOrEmpty
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

Describe 'Resolve-DetectedState' {
    It 'applies debounce exactly like Resolve-HeadsetState' {
        $s1 = Resolve-DetectedState -PayloadPresent $false -Misses 0 -OffMissThreshold 2
        $s1.IsOn | Should -Be $false
        $s1.Decision | Should -Be $false
        $s1.Misses | Should -Be 1

        $s2 = Resolve-DetectedState -PayloadPresent $false -Misses 1 -OffMissThreshold 2
        $s2.Decision | Should -Be $true
        $s2.Misses | Should -Be 2

        $s3 = Resolve-DetectedState -PayloadPresent $true -Misses 5 -OffMissThreshold 2
        $s3.IsOn | Should -Be $true
        $s3.Misses | Should -Be 0
    }
}

Describe 'Get-CsvColumn' {
    It 'finds a column by exact name' {
        $row = [pscustomobject]@{ Name = 'X'; State = 'Active' }
        Get-CsvColumn -Row $row -Names @('State') | Should -Be 'Active'
    }

    It 'falls back to alias names (State vs DeviceState)' {
        $row = [pscustomobject]@{ Name = 'X'; DeviceState = 'Unplugged' }
        Get-CsvColumn -Row $row -Names @('State', 'DeviceState') | Should -Be 'Unplugged'
    }

    It 'returns null when no column matches' {
        $row = [pscustomobject]@{ Name = 'X' }
        Get-CsvColumn -Row $row -Names @('State', 'DeviceState') | Should -BeNullOrEmpty
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

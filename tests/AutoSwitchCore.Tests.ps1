#requires -Version 5.1
# Pester tests para lib/AutoSwitchCore.psm1

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\AutoSwitchCore.psm1') -Force
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
        # La clase de dispositivo debe ser {0.0.0.00000000}. Otras clases no son render.
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

#requires -Version 5.1

$module = Join-Path $PSScriptRoot '..\lib\SteelSeriesNova5.psm1'
Import-Module $module -Force

Describe 'SteelSeries Arctis Nova 5 HID status mapping' {
    It 'maps the documented offline marker to Disconnected' {
        $data = New-Object byte[] 16
        $data[1] = 0x02
        Resolve-SteelSeriesNova5Status -Data $data | Should -Be 'Disconnected'
    }

    It 'maps a normal status response to Connected' {
        $data = New-Object byte[] 16
        $data[1] = 0x00
        Resolve-SteelSeriesNova5Status -Data $data | Should -Be 'Connected'
    }

    It 'treats a short response as Unknown' {
        $data = New-Object byte[] 8
        Resolve-SteelSeriesNova5Status -Data $data | Should -Be 'Unknown'
    }
}

Describe 'SteelSeries Arctis Nova 5 native HID bridge' {
    It 'compiles the embedded HID/SetupAPI bridge without touching hardware' {
        { Initialize-SteelSeriesNova5Hid } | Should -Not -Throw
        ('AutoSwitch.SteelSeriesNova5Hid' -as [type]) | Should -Not -BeNullOrEmpty
    }
}

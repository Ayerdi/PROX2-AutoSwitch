#requires -Version 5.1

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\AutoSwitchCore.psm1') -Force
}

Describe 'Atomic configuration persistence' {
    It 'writes valid JSON and can replace an existing config' {
        $path = Join-Path $TestDrive 'config.json'

        Write-AutoSwitchJsonAtomically -InputObject ([ordered]@{
            Version = '1.0.0'
            DetectionMode = 'WindowsEndpoint'
        }) -Path $path

        $first = Get-Content -Raw -Path $path | ConvertFrom-Json
        $first.Version | Should -Be '1.0.0'
        $first.DetectionMode | Should -Be 'WindowsEndpoint'

        Write-AutoSwitchJsonAtomically -InputObject ([ordered]@{
            Version = '1.4.0'
            DetectionMode = 'LogitechGHub'
        }) -Path $path

        $second = Get-Content -Raw -Path $path | ConvertFrom-Json
        $second.Version | Should -Be '1.4.0'
        $second.DetectionMode | Should -Be 'LogitechGHub'
    }

    It 'does not leave temporary or backup files after a successful replacement' {
        $path = Join-Path $TestDrive 'config.json'
        Write-AutoSwitchJsonAtomically -InputObject @{ Value = 1 } -Path $path
        Write-AutoSwitchJsonAtomically -InputObject @{ Value = 2 } -Path $path

        @(Get-ChildItem -Path $TestDrive -Force | Where-Object { $_.Name -ne 'config.json' }).Count | Should -Be 0
    }
}

Describe 'Generic Logitech G HUB candidate selection' {
    It 'keeps compatible headsets and rejects non-headset Logitech devices' {
        $devices = @(
            [pscustomobject]@{
                extendedDisplayName = 'G733 Wireless Gaming Headset'
                deviceType = 'headset'
                capabilities = [pscustomobject]@{ hasBatteryStatus = $true }
            },
            [pscustomobject]@{
                extendedDisplayName = 'G PRO X Superlight Mouse'
                deviceType = 'mouse'
                capabilities = [pscustomobject]@{ hasBatteryStatus = $true }
            },
            [pscustomobject]@{
                extendedDisplayName = 'Lightspeed Receiver'
                deviceType = 'receiver'
                capabilities = [pscustomobject]@{ hasBatteryStatus = $false }
            }
        )

        $candidates = @(Get-LogitechHeadsetCandidates -DeviceInfos $devices)
        $candidates.Count | Should -Be 1
        $candidates[0].extendedDisplayName | Should -Be 'G733 Wireless Gaming Headset'
    }
}

Describe 'Runtime provider regression guards' {
    It 'uses the shared generic Logitech G HUB provider instead of duplicated transport code' {
        $runtime = Get-Content -Raw -Path (Join-Path $PSScriptRoot '..\Runtime-PROX2-AutoSwitch.ps1')
        $installer = Get-Content -Raw -Path (Join-Path $PSScriptRoot '..\Instalar-PROX2-AutoSwitch.ps1')

        $runtime | Should -Match 'LogitechGHub\.psm1'
        $runtime | Should -Match 'Get-LogitechGHubBatteryPath'
        $runtime | Should -Match 'Open-ConfiguredGHubConnection'
        $runtime | Should -Not -Match 'function Connect-GHub'
        $runtime | Should -Not -Match 'function Invoke-GHubGet'
        $runtime | Should -Not -Match 'Test-GHubProX2'
        $runtime | Should -Not -Match 'Get-ProX2BatteryPath'

        $installer | Should -Match 'LogitechGHub\.psm1'
        $installer | Should -Match 'Select-InstallerLogitechHeadset'
        $installer | Should -Not -Match 'function Connect-GHub'
        $installer | Should -Not -Match 'function Invoke-GHubGet'
    }

    It 'keeps SteelSeries available from Reconfigure' {
        $runtime = Get-Content -Raw -Path (Join-Path $PSScriptRoot '..\Runtime-PROX2-AutoSwitch.ps1')
        $runtime | Should -Match 'Test-SteelSeriesNova5Receiver'
        $runtime | Should -Match 'newMode = "SteelSeriesNova5"'
    }

    It 'does not hardcode the installed config version in the installer' {
        $installer = Get-Content -Raw -Path (Join-Path $PSScriptRoot '..\Instalar-PROX2-AutoSwitch.ps1')
        $installer | Should -Match 'Version\s+= \$PackageVersion'
        $installer | Should -Not -Match 'Version\s+= "1\.4\.0"'
    }
}

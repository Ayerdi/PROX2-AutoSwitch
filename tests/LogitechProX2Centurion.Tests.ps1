#requires -Version 5.1

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\LogitechProX2Centurion.psm1') -Force
}

Describe 'Logitech PRO X 2 Centurion provider' {
    It 'exports the public provider commands' {
        (Get-Command Initialize-LogitechProX2Centurion -ErrorAction Stop).Name |
            Should -Be 'Initialize-LogitechProX2Centurion'
        (Get-Command Get-LogitechProX2CenturionState -ErrorAction Stop).Name |
            Should -Be 'Get-LogitechProX2CenturionState'
        (Get-Command Test-LogitechProX2CenturionConfig -ErrorAction Stop).Name |
            Should -Be 'Test-LogitechProX2CenturionConfig'
    }

    It 'recognizes a PRO X 2 G HUB configuration' {
        $config = [pscustomobject]@{
            DetectionMode   = 'LogitechGHub'
            GHubDisplayName = 'PRO X 2 Lightspeed Gaming Headset'
            HeadsetName     = 'Cascos Gaming'
        }

        Test-LogitechProX2CenturionConfig -Config $config | Should -Be $true
    }

    It 'recognizes PRO X 2 from the configured Windows label' {
        $config = [pscustomobject]@{
            DetectionMode = 'LogitechGHub'
            HeadsetName   = 'PRO X 2 LIGHTSPEED — Headphones'
        }

        Test-LogitechProX2CenturionConfig -Config $config | Should -Be $true
    }

    It 'does not select Centurion for other Logitech headsets' {
        $config = [pscustomobject]@{
            DetectionMode   = 'LogitechGHub'
            GHubDisplayName = 'G733 Wireless Gaming Headset'
            HeadsetName     = 'G733 — Headphones'
        }

        Test-LogitechProX2CenturionConfig -Config $config | Should -Be $false
    }
}

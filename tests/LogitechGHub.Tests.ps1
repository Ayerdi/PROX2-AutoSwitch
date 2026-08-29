#requires -Version 5.1

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\LogitechGHub.psm1') -Force
}

function New-TestGHubHeadset {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Id
    )

    return [pscustomobject]@{
        id                  = $Id
        extendedDisplayName = $Name
        deviceType          = 'headset'
        capabilities        = [pscustomobject]@{ hasBatteryStatus = $true }
    }
}

Describe 'Logitech G HUB provider exports' {
    It 'exports the bounded provider surface used by installer and runtime' {
        (Get-Command Open-LogitechGHubConnection -ErrorAction Stop).Name | Should -Be 'Open-LogitechGHubConnection'
        (Get-Command Close-LogitechGHubConnection -ErrorAction Stop).Name | Should -Be 'Close-LogitechGHubConnection'
        (Get-Command Invoke-LogitechGHubGet -ErrorAction Stop).Name | Should -Be 'Invoke-LogitechGHubGet'
        (Get-Command Get-LogitechGHubHeadsets -ErrorAction Stop).Name | Should -Be 'Get-LogitechGHubHeadsets'
        (Get-Command Resolve-LogitechGHubHeadset -ErrorAction Stop).Name | Should -Be 'Resolve-LogitechGHubHeadset'
        (Get-Command Get-LogitechGHubBatteryPath -ErrorAction Stop).Name | Should -Be 'Get-LogitechGHubBatteryPath'
    }
}

Describe 'Resolve-LogitechGHubHeadset' {
    It 'prefers the configured compatible display name when several headsets exist' {
        $g733 = New-TestGHubHeadset -Name 'G733 Wireless Gaming Headset' -Id 'g733'
        $prox = New-TestGHubHeadset -Name 'PRO X 2 Lightspeed Gaming Headset' -Id 'prox2'

        $resolved = Resolve-LogitechGHubHeadset -DeviceInfos @($g733, $prox) -DisplayName 'PRO X 2 Lightspeed Gaming Headset'
        $resolved.id | Should -Be 'prox2'
    }

    It 'accepts a single compatible headset when no configured name is available' {
        $g733 = New-TestGHubHeadset -Name 'G733 Wireless Gaming Headset' -Id 'g733'

        $resolved = Resolve-LogitechGHubHeadset -DeviceInfos @($g733)
        $resolved.id | Should -Be 'g733'
    }

    It 'fails closed instead of guessing when several compatible headsets are ambiguous' {
        $a = New-TestGHubHeadset -Name 'G733 Wireless Gaming Headset' -Id 'a'
        $b = New-TestGHubHeadset -Name 'PRO X Wireless Gaming Headset' -Id 'b'

        Resolve-LogitechGHubHeadset -DeviceInfos @($a, $b) | Should -BeNullOrEmpty
    }

    It 'does not resolve a non-headset Logitech device' {
        $mouse = [pscustomobject]@{
            id                  = 'mouse'
            extendedDisplayName = 'G PRO X Superlight Mouse'
            deviceType          = 'mouse'
            capabilities        = [pscustomobject]@{ hasBatteryStatus = $true }
        }

        Resolve-LogitechGHubHeadset -DeviceInfos @($mouse) | Should -BeNullOrEmpty
    }
}

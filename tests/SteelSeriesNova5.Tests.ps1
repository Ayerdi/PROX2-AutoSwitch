#requires -Version 5.1

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\SteelSeriesNova5.psm1') -Force
}

Describe 'SteelSeries Nova 5 HeadsetControl provider' {
    It 'recognizes SteelSeriesNova5 as a valid detection mode' {
        $cfg = [pscustomobject]@{ DetectionMode = 'SteelSeriesNova5' }
        Get-ConfigDetectionMode -Config $cfg | Should -Be 'SteelSeriesNova5'
    }

    It 'preserves the legacy detection-mode migration default' {
        $cfg = [pscustomobject]@{}
        Get-ConfigDetectionMode -Config $cfg | Should -Be 'LogitechGHub'
    }

    It 'pins HeadsetControl 4.0.0 and its verified portable hash' {
        $info = Get-HeadsetControlPortableInfo
        $info.Version | Should -Be '4.0.0'
        $info.Url | Should -Match '/Sapd/HeadsetControl/releases/download/4\.0\.0/headsetcontrol-windows-x86_64\.exe$'
        $info.Sha256 | Should -Be 'd78a86cc0f44403d2bcb16294f8f2d91cc2f9f343adb09907a8cef8278309be8'
    }

    It 'maps BATTERY_AVAILABLE to Connected' {
        $json = @'
{
  "devices": [
    {
      "id_vendor": "0x1038",
      "id_product": "0x2232",
      "battery": { "status": "BATTERY_AVAILABLE", "level": 76 }
    }
  ]
}
'@
        Resolve-SteelSeriesNova5HeadsetControlJson -JsonText $json -ProductId 0x2232 |
            Should -Be 'Connected'
    }

    It 'maps BATTERY_CHARGING to Connected' {
        $json = @'
{
  "devices": [
    {
      "id_vendor": "0x1038",
      "id_product": "0x2253",
      "battery": { "status": "BATTERY_CHARGING", "level": 42 }
    }
  ]
}
'@
        Resolve-SteelSeriesNova5HeadsetControlJson -JsonText $json -ProductId 0x2253 |
            Should -Be 'Connected'
    }

    It 'maps the Nova offline error to Disconnected' {
        $json = @'
{
  "devices": [
    {
      "id_vendor": "0x1038",
      "id_product": "0x2232",
      "status": "partial",
      "battery": { "status": "BATTERY_UNAVAILABLE", "level": -1 },
      "errors": { "Battery status": "Headset not connected" }
    }
  ]
}
'@
        Resolve-SteelSeriesNova5HeadsetControlJson -JsonText $json -ProductId 0x2232 |
            Should -Be 'Disconnected'
    }

    It 'keeps an unrelated battery error Unknown' {
        $json = @'
{
  "devices": [
    {
      "id_vendor": "0x1038",
      "id_product": "0x2232",
      "status": "partial",
      "battery": { "status": "BATTERY_UNAVAILABLE", "level": -1 },
      "errors": { "Battery status": "Could not open device" }
    }
  ]
}
'@
        Resolve-SteelSeriesNova5HeadsetControlJson -JsonText $json -ProductId 0x2232 |
            Should -Be 'Unknown'
    }

    It 'keeps malformed JSON Unknown' {
        Resolve-SteelSeriesNova5HeadsetControlJson -JsonText '{broken' -ProductId 0x2232 |
            Should -Be 'Unknown'
    }

    It 'rejects a different product ID' {
        $json = @'
{
  "devices": [
    {
      "id_vendor": "0x1038",
      "id_product": "0x2253",
      "battery": { "status": "BATTERY_AVAILABLE", "level": 90 }
    }
  ]
}
'@
        Resolve-SteelSeriesNova5HeadsetControlJson -JsonText $json -ProductId 0x2232 |
            Should -Be 'Unknown'
    }
}

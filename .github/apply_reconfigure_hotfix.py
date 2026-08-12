from pathlib import Path

path = Path("Runtime-PROX2-AutoSwitch.ps1")
raw = path.read_bytes()
has_bom = raw.startswith(b"\xef\xbb\xbf")
decoded = raw.decode("utf-8-sig")
use_crlf = "\r\n" in decoded
text = decoded.replace("\r\n", "\n")

old = '''    $uri = New-Object System.Uri("ws://localhost:$($Config.GHubPort)")'''
new = '''    # WindowsEndpoint configs may never have had GHubPort. Reconfigure can
    # switch such a config to PRO X 2, so use the established default safely.
    $ghubPort = 9010
    if ($Config.PSObject.Properties['GHubPort'] -and $Config.GHubPort) {
        $ghubPort = [int]$Config.GHubPort
    }
    $uri = New-Object System.Uri("ws://localhost:$ghubPort")'''
if old not in text:
    raise SystemExit("Connect-GHub target not found")
text = text.replace(old, new, 1)

old = '''        # Varios PRO X 2: preferir el que coincide con el nombre visible del
        # headset elegido; si no hay coincidencia, el primero.
        $picked = $candidates | Where-Object {
            $_.extendedDisplayName -match [regex]::Escape([string]$comboHeadset.Text)
        } | Select-Object -First 1
        if ($picked) { return $picked }
        return $candidates[0]'''
new = '''        # Multiple PRO X 2 devices: never guess. Ask the user which one to use.
        foreach ($candidate in $candidates) {
            $answer = [System.Windows.Forms.MessageBox]::Show(
                ("Multiple PRO X 2 devices were found in G HUB.`n`nUse this one?`n{0} ({1})" -f $candidate.extendedDisplayName, $candidate.id),
                "Audio AutoSwitch",
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                return $candidate
            }
            if ($answer -eq [System.Windows.Forms.DialogResult]::Cancel) {
                return $null
            }
        }
        return $null'''
if old not in text:
    raise SystemExit("multiple-PRO-X-2 target not found")
text = text.replace(old, new, 1)

old = '''            $Config.HeadsetId   = [string]$newHeadsetId
            $Config.SpeakerId   = [string]$newFallbackId
            $Config.HeadsetName = $newHeadsetName
            $Config.SpeakerName = $newSpeakerName
            $Config.DetectionMode = $newMode
            if ($newGhubName) {
                $Config.GHubDisplayName = $newGhubName
            }
            else {
                $Config.PSObject.Properties.Remove('GHubDisplayName')
            }
            # El endpoint de enhancements debe seguir al nuevo headset.
            $Config.EnhancementsDeviceId = [string]$newHeadsetId'''
new = '''            $Config.HeadsetId   = [string]$newHeadsetId
            $Config.SpeakerId   = [string]$newFallbackId
            $Config.HeadsetName = $newHeadsetName
            $Config.SpeakerName = $newSpeakerName

            # Optional properties may not exist in WindowsEndpoint configs.
            # Add-Member -Force updates existing values and safely creates missing ones.
            $Config | Add-Member -NotePropertyName DetectionMode -NotePropertyValue $newMode -Force
            $Config | Add-Member -NotePropertyName EnhancementsDeviceId -NotePropertyValue ([string]$newHeadsetId) -Force

            if ($newMode -eq 'LogitechGHub') {
                $ghubPortToSave = 9010
                if ($Config.PSObject.Properties['GHubPort'] -and $Config.GHubPort) {
                    $ghubPortToSave = [int]$Config.GHubPort
                }
                $Config | Add-Member -NotePropertyName GHubDisplayName -NotePropertyValue $newGhubName -Force
                $Config | Add-Member -NotePropertyName GHubPort -NotePropertyValue $ghubPortToSave -Force
            }
            else {
                $Config.PSObject.Properties.Remove('GHubDisplayName')
                $Config.PSObject.Properties.Remove('GHubPort')
            }'''
if old not in text:
    raise SystemExit("config-save target not found")
text = text.replace(old, new, 1)

if use_crlf:
    text = text.replace("\n", "\r\n")
encoded = text.encode("utf-8")
if has_bom:
    encoded = b"\xef\xbb\xbf" + encoded
path.write_bytes(encoded)

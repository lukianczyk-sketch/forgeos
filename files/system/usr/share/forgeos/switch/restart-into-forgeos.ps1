# ForgeOS by RL Forge Works - "Restart into ForgeOS" (Job 13e).
# Restarts this PC into ForgeOS ONE time. The normal start-up order is not changed.
# Run by "Restart into ForgeOS.cmd" on the desktop; Windows asks for permission (admin) first.
$ErrorActionPreference = 'Continue'
$list = (bcdedit /enum firmware) -join "`n"
$id = $null
foreach ($block in ($list -split "`n\s*`n")) {
    $isForge = ($block -match '(?im)^path\s+\\EFI\\fedora\\') -or ($block -match '(?im)^description\s+(Fedora|ForgeOS|Bazzite)')
    if ($isForge -and ($block -match '(?im)^identifier\s+(\{[0-9a-f-]+\})')) {
        $id = $Matches[1]
        break
    }
}
if (-not $id) {
    Write-Host 'ForgeOS was not found in the start-up list of this PC.'
    Write-Host 'Pick ForgeOS in the start-up menu instead (press the boot menu key when the PC starts).'
    Read-Host 'Press Enter to close'
    exit 1
}
bcdedit /set '{fwbootmgr}' bootsequence $id | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Windows did not allow the change. Nothing was changed.'
    Read-Host 'Press Enter to close'
    exit 1
}
Write-Host 'Restarting into ForgeOS in 5 seconds. Save your work now.'
shutdown /r /t 5 /c 'Restarting into ForgeOS'

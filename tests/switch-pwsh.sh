#!/usr/bin/env bash
# Runs the Windows "Restart into ForgeOS" script with PowerShell and a fake bcdedit / shutdown (Job 13e test F6).
# Usage: bash tests/switch-pwsh.sh SCRIPT.ps1 WORKDIR
# Prints: "SET {id}" + "RESTART" for a start-up list with ForgeOS, then "NOTFOUND <exit code>" for one without.
set -u
SCRIPT="$1"; W="$2"
cat > "$W/with.txt" <<'EOF'
Firmware Boot Manager
---------------------
identifier              {fwbootmgr}
displayorder            {bootmgr}
                        {6a2b1c3d-1111-2222-3333-444455556666}
timeout                 0

Windows Boot Manager
--------------------
identifier              {bootmgr}
device                  partition=\Device\HarddiskVolume1
path                    \EFI\Microsoft\Boot\bootmgfw.efi
description             Windows Boot Manager

Firmware Application (101fffff)
-------------------------------
identifier              {6a2b1c3d-1111-2222-3333-444455556666}
device                  partition=\Device\HarddiskVolume5
path                    \EFI\fedora\shimx64.efi
description             Fedora
EOF
head -n 13 "$W/with.txt" > "$W/without.txt"
run() {
  LIST="$1" pwsh -NoProfile -NonInteractive -Command "
    function bcdedit { if (\$args[0] -eq '/enum') { Get-Content \$env:LIST } else { Write-Host ('SET ' + \$args[3]); \$global:LASTEXITCODE = 0 } }
    function shutdown { Write-Output 'RESTART' }
    function Read-Host { }
    . '$SCRIPT'"
}
run "$W/with.txt"
run "$W/without.txt" >/dev/null 2>&1
echo "NOTFOUND $?"

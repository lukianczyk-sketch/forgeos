#!/usr/bin/env bash
# Tests for Moving Day (Job 14), case J: the Windows side. "Pack my old PC" runs in PowerShell (CI only) on a fake
# Windows user, then Moving Day reads that Moving Box: files, bookmarks, programs and passwords come over.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-movingday-win.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/movingday-fakes.sh
. "$ROOT/tests/movingday-fakes.sh"
C="$FORGEOS_MD_SHARE/Pack my old PC.cmd"; PS="$FORGEOS_MD_SHARE/pack.ps1"

check J1 'grep -qx "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0ForgeOS Moving Day\\\\pack.ps1\"" "$C" && grep -qx "pause" "$C" && ! LC_ALL=C grep -q "[^ -~]" "$PS" "$C"'
check J2 '! grep -qiE "Remove-Item|\brm\b|del |Set-ItemProperty|New-ItemProperty|reg add|bcdedit|Invoke-WebRequest|Start-BitsTransfer" "$PS" && grep -q "robocopy \$From \$To /E /XJ" "$PS"'

if ! command -v pwsh >/dev/null 2>&1; then
  echo "SKIP J3-J5 (PowerShell is not installed; GitHub's Ubuntu runners have it)"
else
  W="$WORK/disks/sda3"; win_tree "$W"; U="$W/Users/Robert"; S="$WORK/stick"
  mkdir -p "$S/ForgeOS Moving Day"; cp "$PS" "$S/ForgeOS Moving Day/pack.ps1"
  pack() { (cd "$WORK" && FORGEOS_MD_TEST=1 USERPROFILE="$U" LOCALAPPDATA="$U/AppData/Local" APPDATA="$U/AppData/Roaming" \
    ProgramData="$W/ProgramData" USERNAME=Robert COMPUTERNAME=OLDPC ANSWER="$1" pwsh -NoProfile -NonInteractive -Command \
    "function Read-Host { \$env:ANSWER }; . '$S/ForgeOS Moving Day/pack.ps1'" > "$WORK/pack.out" 2>&1); }
  pack n; R=$?
  check J3 '[ "$R" = 1 ] && grep -q "^Nothing was copied." "$WORK/pack.out" && [ ! -e "$S/ForgeOS Moving Box" ]'
  pack y; R=$?; B="$S/ForgeOS Moving Box"
  check J4 '[ "$R" = 0 ] && grep -q "^Done. Plug the stick into the ForgeOS PC" "$WORK/pack.out" && [ -f "$B/Users/Robert/Documents/Taxes/2023.pdf" ] && [ -f "$B/Users/Robert/AppData/Local/Google/Chrome/User Data/Default/Bookmarks" ] && [ -f "$B/Users/Robert/AppData/Roaming/Mozilla/Firefox/Profiles/ab12.default-release/places.sqlite" ] && [ -d "$B/passwords" ] && grep -q "\"made_by\": \"ForgeOS Moving Day\"" "$B/box.json" && ! grep -q "Notepad" "$B/programs.txt" && grep -q "^Excel" "$B/programs.txt"'
  cp "$U/Downloads/Chrome Passwords.csv" "$B/passwords/"
  OUT="$(MD scan "$S")"; OUT2="$(MD move "$S" --user Robert)"; OUT3="$(MD passwords "$S" --user Robert)"
  check J5 'grep -qx "ROOT${T}box${T}$B" <<< "$OUT" && grep -q "^DONE${T}" <<< "$OUT2" && [ -f "$HOME/Documents/Taxes/2023.pdf" ] && grep -q "^BOOKMARKS${T}added${T}3${T}" <<< "$OUT2" && grep -q "^PASSWORDS${T}1${T}2${T}" <<< "$OUT3" && [ "$(find "$U" -newer "$S/ForgeOS Moving Day/pack.ps1" | wc -l)" = 0 ]'
fi

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

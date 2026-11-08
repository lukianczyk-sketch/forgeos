#!/usr/bin/env bash
# Tests for Digital Will (Job 18), cases G-H: PC unlock for family with a REAL locked drive (cryptsetup on a
# LUKS2 test file): the first code needs the disk password, a new envelope swaps the code (the old one stops
# working, your own disk password always keeps working), a wrong disk password, and what the root helper
# refuses. Needs root or password-free sudo for cryptsetup (GitHub's runner has it); skipped otherwise.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-digitalwill-unlock.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
REAL="$(command -v cryptsetup || echo /usr/sbin/cryptsetup)"
if [ "$(id -u)" = 0 ]; then SUDO=""; elif sudo -n true 2>/dev/null; then SUDO="sudo -n"; else
  echo "SKIP G-H (needs root or password-free sudo for cryptsetup)"; exit 0; fi
[ -x "$REAL" ] || { echo "FAIL cryptsetup is needed (sudo apt-get install cryptsetup-bin)"; exit 1; }
# shellcheck source=tests/digitalwill-fakes.sh
. "$ROOT/tests/digitalwill-fakes.sh"
# The real cryptsetup, with a quick key setting for the tests only (the real PC uses its strong default).
printf '#!/usr/bin/env bash\ncase "$1" in luksAddKey|luksFormat) set -- "$1" --pbkdf pbkdf2 --pbkdf-force-iterations 1000 "${@:2}" ;; esac\nexec %s "%s" "$@"\n' "$SUDO" "$REAL" > "$WORK/bin/cs"
chmod +x "$WORK/bin/cs"
export FORGEOS_WILL_CRYPTSETUP="$WORK/bin/cs"
DISK="$WORK/disk.img"
newdisk() { rm -f "$DISK"; truncate -s 24M "$DISK"; printf 'my disk pw\n' | cs luksFormat -q "$DISK"; }
opens() { printf '%s' "$1" > "$WORK/try.key"; cs open --test-passphrase --key-file "$WORK/try.key" "$DISK" > /dev/null 2>&1; }
slots() { cs luksDump "$DISK" | grep -cE "^  [0-9]+: luks2"; }
KEYF="$WORK/var/unlock-$(sed 's/[^A-Za-z0-9]\{1,\}/_/g; s/^_//; s/_$//' <<< "$DISK").key"
code_in() { open_env "$1" "$2"; sed -n 's/.*type the PC unlock code:<br><span class="code">\([a-z ]*\)<.*/\1/p' "$WORK/open/Open me first.html"; }

# G: the first PC unlock code needs the disk password; it opens the drive and the disk password still does
fresh; drives luks; newdisk; answers > /dev/null
check G1 'grep -qx "UNLOCK${T}not-added" <<< "$(DW status)"'
OUT="$(secrets "" "" "" "my disk pw" | DW make --holder Brianna --unlock)"; RC=$?
C1="$(awk -F "$T" '$1 == "CODE" {print $2}' <<< "$OUT")"; E1="$(awk -F "$T" '$1 == "ENVELOPE" {print $2; exit}' <<< "$OUT")"
K1="$(code_in "$E1" "$C1")"
check G2 '[ "$RC" = 0 ] && [ "$(wc -w <<< "$K1")" = 8 ] && opens "$K1" && opens "my disk pw" && [ "$(cat "$KEYF")" = "$K1" ] && [ "$(stat -c %a "$KEYF")" = 600 ] && [ "$(stat -c %a "$WORK/var")" = 700 ] && [ "$(slots)" = 2 ]'
check G3 'grep -qx "UNLOCK${T}added" <<< "$(DW status)" && grep -qx "UNLOCKIN${T}yes" <<< "$(DW status)" && grep -q "PC unlock for family: added." <<< "$(DW report)"'
# a new envelope swaps the code without the disk password
OUT="$(secrets "" "" "" "" | DW make --holder Kasia --unlock)"; RC=$?
C2="$(awk -F "$T" '$1 == "CODE" {print $2}' <<< "$OUT")"; E2="$(awk -F "$T" '$1 == "ENVELOPE" {print $2; exit}' <<< "$OUT")"
K2="$(code_in "$E2" "$C2")"
check G4 '[ "$RC" = 0 ] && [ -n "$K2" ] && [ "$K2" != "$K1" ] && opens "$K2" && ! opens "$K1" && opens "my disk pw" && [ "$(slots)" = 2 ] && [ "$(cat "$KEYF")" = "$K2" ]'
# without --unlock the envelope says nothing about a code, and the drive's lock is not touched
OUT="$(secrets "" "" "" "" | DW make --holder Kasia)"
open_env "$(awk -F "$T" '$1 == "ENVELOPE" {print $2; exit}' <<< "$OUT")" "$(awk -F "$T" '$1 == "CODE" {print $2}' <<< "$OUT")"
check G5 'grep -q "If it asks for a disk password" "$WORK/open/Open me first.html" && opens "$K2" && grep -qx "UNLOCKIN${T}no" <<< "$(DW status)"'

# H: wrong disk password, no password given, what the root helper refuses, a PC with no locked drive
fresh; drives luks; newdisk; answers > /dev/null
H1="$(secrets "" "" "" "not it" | DW make --holder Brianna --unlock)"; RC1=$?
check H1 '[ "$RC1" = 2 ] && [ "$H1" = "That is not the disk password (the one you type when the PC starts). Nothing was changed." ] && [ ! -e "$BOX" ] && [ ! -e "$KEYF" ] && [ "$(slots)" = 1 ] && grep -qx "UNLOCK${T}not-added" <<< "$(DW status)"'
touch "$WORK/pkexec-no"
H2="$(secrets "" "" "" "my disk pw" | DW make --holder Brianna --unlock)"; RC2=$?
check H2 '[ "$RC2" = 1 ] && [ "$H2" = "The PC password was not given, so the PC unlock code was not added." ] && [ "$(slots)" = 1 ]'
rm -f "$WORK/pkexec-no"; U="$FORGEOS_WILL_UNLOCK"
bash "$U" add > /dev/null 2>&1; R1=$?; bash "$U" remove "$DISK" > /dev/null 2>&1; R2=$?
printf 'acid acorn acre aged agent agile aging agony\nmy disk pw\n' | DW root-unlock add "$DISK"; R3=$?
printf 'acid acorn acre aged agent agile aging agony\nmy disk pw\n' | FORGEOS_WILL_ROOT=1 DW root-unlock add /dev/sdb1; R4=$?
printf 'acid; rm -rf /\nmy disk pw\n' | FORGEOS_WILL_ROOT=1 DW root-unlock add "$DISK"; R5=$?
printf 'acid acorn acre aged agent agile aging agony\nmy disk pw\n' | FORGEOS_WILL_ROOT=1 bash "$U" add "$DISK"; R6=$?
check H3 '[ "$R1$R2$R3$R4$R5" = 33333 ] && [ "$R6" = 0 ] && opens "acid acorn acre aged agent agile aging agony" && [ "$(slots)" = 2 ]'
fresh; drives stick; answers > /dev/null
OUT="$(secrets "" "" "" "" | DW make --holder Brianna --unlock)"; RC=$?
check H4 '[ "$RC" = 0 ] && grep -qx "UNLOCK${T}no-luks" <<< "$(DW status)" && grep -q "drive is not locked" <<< "$(DW report)" && ! grep -q "^pkexec" <<< "$(calls)"'

echo
if [ "$failures" -eq 0 ]; then echo "All Digital Will tests G-H passed."; else echo "$failures Digital Will test(s) failed."; fi
exit "$((failures > 0))"

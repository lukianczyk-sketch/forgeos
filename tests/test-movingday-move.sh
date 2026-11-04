#!/usr/bin/env bash
# Tests for Moving Day (Job 14), cases D-F: the move - what is copied where, never overwriting, Windows
# untouched, going on after a stop, the room check, a full drive, and the virus check.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-movingday-move.sh <repo-root>
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
W="$WORK/disks/sda3"
win_tree "$W"
touch -d "2023-04-15 10:00" "$W/Users/Robert/Documents/Taxes/2023.pdf"
mkdir -p "$HOME/Documents"; echo "mine" > "$HOME/Documents/letter.docx"; printf 'a,b\n1,2\n' > "$W/Users/Robert/Documents/passwords.csv"
sums() { (cd "$W" && find . -print0 | sort -z | xargs -0 ls -ld --time-style=+%s | md5sum); }
BEFORE="$(sums)"

# D: everything comes over into the normal folders; junk, links and the password file stay behind
OUT="$(MD move "$W" --user Robert)"; R=$?
check D1 '[ "$R" = 0 ] && grep -qx "DONE${T}7${T}0${T}0${T}42" <<< "$OUT" && grep -qx "Copied 7 files (42 bytes)." <<< "$OUT" && [ -f "$HOME/Documents/passwords.csv" ] && grep -qx "Your old Windows is untouched: nothing on it was changed or deleted." <<< "$OUT"'
check D2 '[ -f "$HOME/Documents/Taxes/2023.pdf" ] && [ -f "$HOME/Documents/notes.txt" ] && [ -f "$HOME/Pictures/cat.jpg" ] && [ -f "$HOME/Music/song.mp3" ] && [ -f "$HOME/Downloads/setup.exe" ] && [ "$(date -r "$HOME/Documents/Taxes/2023.pdf" +%F)" = 2023-04-15 ]'
check D3 '[ "$(cat "$HOME/Documents/letter.docx")" = mine ] && [ "$(cat "$HOME/Documents/letter (from Windows).docx")" = letter ] && [ ! -e "$HOME/Documents/desktop.ini" ] && [ ! -e "$HOME/Documents/~\$letter.docx" ] && [ ! -e "$HOME/Desktop/Word.lnk" ] && [ ! -e "$HOME/Documents/My Music" ] && [ ! -e "$HOME/Downloads/Chrome Passwords.csv" ] && [ -z "$(find "$HOME" -name "*.part")" ]'
check D4 '[ "$BEFORE" = "$(sums)" ] && grep -q "^forgeos-undo snapshot-now Before Moving Day$" "$WORK/calls.log" && grep -q "^forgeos-guard scan .*/Documents/Taxes/2023.pdf" "$WORK/calls.log" && grep -qx "NOTE${T}Undo Button saved a snapshot first." <<< "$OUT"'

# E: going on after a stop: nothing is copied twice, a new file is; the room check; a full drive stops cleanly
: > "$WORK/calls.log"; OUT="$(MD move "$W" --user Robert)"; R=$?
check E1 '[ "$R" = 0 ] && grep -qx "DONE${T}0${T}0${T}0${T}0" <<< "$OUT" && grep -qx "Nothing new to copy: those files were all copied before." <<< "$OUT" && ! grep -q "^forgeos-undo" "$WORK/calls.log" && [ ! -e "$HOME/Documents/letter (from Windows 2).docx" ]'
echo "dog" > "$W/Users/Robert/Pictures/dog.jpg"; OUT="$(MD move "$W" --user Robert --pick Pictures)"
check E2 'grep -qx "DONE${T}1${T}0${T}0${T}4" <<< "$OUT" && [ -f "$HOME/Pictures/dog.jpg" ] && [ ! -e "$HOME/Pictures/cat (from Windows).jpg" ]'
rm "$HOME/Pictures/dog.jpg"; echo "pup" > "$W/Users/Robert/Pictures/pup.jpg"
OUT="$(FORGEOS_MD_FREE=1000 MD move "$W" --user Robert)"; R=$?
check E3 '[ "$R" = 4 ] && grep -q "^Not enough room: this needs 8 bytes" <<< "$OUT" && [ ! -e "$HOME/Pictures/pup.jpg" ] && [ ! -e "$HOME/Pictures/dog.jpg" ]'
OUT="$(python3 -B - "$FORGEOS_MD_LIB" "$W" <<'EOF'
import os, sys
sys.path.insert(0, sys.argv[1])
from movelib import files, scan
udir = scan.user_dir(sys.argv[2], "Robert")
log = files.log_path(sys.argv[2], "Robert")
todo, need = files.plan(udir, scan.folders(udir), log)
real, calls = files.copy_one, []
def full(src, dest):
    calls.append(dest)
    if len(calls) == 2:
        raise files.Full()
    real(src, dest)
files.copy_one = full
res = files.copy_all(todo, log)
print(len(todo), res["full"], len(res["copied"]), len(files.read_log(log)))
EOF
)"
check E4 '[ "$OUT" = "2 True 1 8" ]'

# F: a virus is locked away; no Guard / Undo off are said plainly; wrong use
echo "X5O eicar" > "$W/Users/Robert/Documents/eicar.com"; echo 1 > "$WORK/undo-rc"
OUT="$(MD move "$W" --user Robert --pick Documents)"; R=$?
check F1 '[ "$R" = 1 ] && grep -qx "VIRUS${T}$HOME/Documents/eicar.com${T}Eicar-Test-Signature" <<< "$OUT" && grep -qx "A virus was found and locked away: eicar.com (Eicar-Test-Signature)." <<< "$OUT" && grep -qx "Undo Button is off, so no snapshot was taken first." <<< "$OUT"'
mv "$WORK/bin/forgeos-guard" "$WORK/guard-off"; echo "new" > "$W/Users/Robert/Documents/new.txt"
OUT="$(PATH="$WORK/bin:/usr/bin:/bin" MD move "$W" --user Robert --pick Documents)"
check F2 'grep -qx "Always-On Guard is not on this PC, so the files were not virus-checked." <<< "$OUT" && [ -f "$HOME/Documents/new.txt" ]'
MD move "$W" --user Nobody >/dev/null; R1=$?; MD move "$W" --user Robert --pick Documents,Games >/dev/null 2>&1; R2=$?
MD move "$W" >/dev/null 2>&1; R3=$?; MD move "$W" --user >/dev/null 2>&1; R4=$?
check F3 '[ "$R1$R2$R3$R4" = 3333 ] && MD report | grep -q "^Always-On Guard is not on this PC"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

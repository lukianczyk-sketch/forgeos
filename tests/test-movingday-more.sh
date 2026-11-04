#!/usr/bin/env bash
# Tests for Moving Day (Job 14), cases G-I: bookmarks into Brave, saved passwords (private folder, erased
# after), the programs list with the free ForgeOS way, and making the Moving Box stick.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-movingday-more.sh <repo-root>
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
W="$WORK/disks/sda3"; win_tree "$W"; BF="$HOME/brave/Default/Bookmarks"
bm() { python3 -c "
import json, sys
d = json.load(open(sys.argv[1])); bar = d['roots']['bookmark_bar']['children']
def walk(n): return [n['name']] + sum((walk(c) for c in n.get('children', [])), [])
ids = []
def allids(n): ids.append(n['id']); [allids(c) for c in n.get('children', [])]
[allids(r) for r in d['roots'].values()]
print(' | '.join(sum((walk(c) for c in bar), [])), 'checksum' in d, len(ids) == len(set(ids)))" "$BF"; }

# G: bookmarks
OUT="$(MD move "$W" --user Robert --pick bookmarks)"
check G1 'grep -qx "BOOKMARKS${T}added${T}3${T}$HOME/Documents/Bookmarks from Windows.html" <<< "$OUT" && [ "$(bm)" = "From Windows | Chrome | Bookmarks bar | Kern County | News | KGET | Firefox | Bookmarks Toolbar | Weather False True" ] && grep -q "<DT><A HREF=\"https://www.kget.com/\">KGET</A>" "$HOME/Documents/Bookmarks from Windows.html" && ! grep -q "javascript\|place:" "$BF" "$HOME/Documents/Bookmarks from Windows.html"'
python3 - "$BF" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["roots"]["bookmark_bar"]["children"].insert(0, {"id": "77", "guid": "a", "name": "Mine", "type": "url", "url": "https://mine.example/", "date_added": "0"})
d["checksum"] = "abc"
json.dump(d, open(sys.argv[1], "w"))
EOF
MD move "$W" --user Robert --pick bookmarks >/dev/null
check G2 '[ "$(bm)" = "Mine | From Windows | Chrome | Bookmarks bar | Kern County | News | KGET | Firefox | Bookmarks Toolbar | Weather False True" ] && grep -q "\"checksum\": \"abc\"" "$BF.before-moving-day"'
cp "$BF" "$WORK/bf-before"; ln -s "host-123" "$HOME/brave/SingletonLock"
OUT="$(MD move "$W" --user Robert --pick bookmarks)"
check G3 'grep -q "^BOOKMARKS${T}brave-open${T}3${T}" <<< "$OUT" && cmp -s "$BF" "$WORK/bf-before" && grep -q "Close Brave and run Moving Day again" <<< "$OUT"'
rm "$HOME/brave/SingletonLock"; echo "{broken" > "$W/Users/Robert/AppData/Local/Google/Chrome/User Data/Default/Bookmarks"
OUT="$(MD move "$W" --user Robert --pick bookmarks)"
check G4 'grep -qx "BOOKMARKS${T}unreadable${T}0${T}Chrome" <<< "$OUT" && grep -q "^BOOKMARKS${T}added${T}1${T}" <<< "$OUT" && grep -qx "The Chrome bookmarks could not be read." <<< "$OUT"'

# H: saved passwords - private folder, Brave's page on the clipboard, erased after (by itself after 24 h)
OUT="$(MD passwords "$W" --user Robert)"; R=$?; P="$HOME/Moving Day passwords"
check H1 '[ "$R" = 0 ] && grep -qx "PASSWORDS${T}1${T}2${T}$P" <<< "$OUT" && grep -q "^2 saved passwords are ready to go into Brave." <<< "$OUT" && [ "$(stat -c %a "$P")" = 700 ] && [ "$(stat -c %a "$P/1 Chrome Passwords.csv")" = 600 ]'
check H2 'grep -q "^wl-copy brave://password-manager/settings$" "$WORK/calls.log" && grep -q "^systemd-run --user --on-active=24h --unit=forgeos-movingday-erase --collect forgeos-movingday passwords-done$" "$WORK/calls.log"'
OUT="$(MD passwords-done)"
check H3 '[ "$OUT" = "ERASED${T}1${T}0${NL}The password file was erased." ] && [ ! -e "$P" ] && [ -f "$W/Users/Robert/Downloads/Chrome Passwords.csv" ] && grep -q "^systemctl --user stop forgeos-movingday-erase.timer$" "$WORK/calls.log"'
B="$WORK/stick/ForgeOS Moving Box"; mkdir -p "$B/passwords" "$B/Users/Robert/Documents"; echo '{}' > "$B/box.json"
printf 'url,username,password\nhttps://a.example,me,pw\n' > "$B/passwords/export.csv"; printf 'a,b\n1,2\n' > "$B/passwords/other.csv"
MD passwords "$WORK/stick" --user Robert > /dev/null; OUT="$(MD passwords-done --erase-from "$WORK/stick" --user Robert)"
check H4 'grep -qx "ERASED${T}1${T}1" <<< "$OUT" && [ ! -e "$B/passwords/export.csv" ] && [ -f "$B/passwords/other.csv" ]'
OUT="$(MD passwords "$WORK/stick" --user Robert)"; R=$?; MD passwords-done --erase-from "$WORK/stick" 2>/dev/null; R2=$?
check H5 '[ "$R$R2" = 13 ] && grep -q "^No saved-password files were found." <<< "$OUT"'

# I: programs and the Moving Box stick
OUT="$(MD programs "$W" --user Robert)"; R=$?
check I1 '[ "$R" = 0 ] && grep -q "^PROGRAM${T}Excel${T}builtin${T}org.onlyoffice.desktopeditors${T}Microsoft Office" <<< "$OUT" && grep -q "^PROGRAM${T}Firefox${T}linux${T}org.mozilla.firefox${T}" <<< "$OUT" && grep -qx "UNKNOWN${T}Some Odd Tool" <<< "$OUT" && [ "$(wc -l <<< "$OUT")" = 3 ]'
printf '\xef\xbb\xbfExcel\nMicrosoft Visual C++ 2015 Redistributable (x64)\nSecurity Update for Windows (KB5034441)\nVLC media player\nGoogle Chrome\n' > "$B/programs.txt"
OUT="$(MD programs "$WORK/stick" --user Robert | cut -f 1-3)"
check I2 '[ "$OUT" = "PROGRAM${T}Excel${T}builtin${NL}PROGRAM${T}Google Chrome${T}linux${NL}PROGRAM${T}VLC media player${T}linux" ]'
mkdir -p "$WORK/stick2"; OUT="$(MD pack-stick "$WORK/stick2")"; R=$?; C="$WORK/stick2/Pack my old PC.cmd"; PS="$WORK/stick2/ForgeOS Moving Day/pack.ps1"
check I3 '[ "$R" = 0 ] && grep -q "^PACKED" <<< "$OUT" && [ "$(head -n 1 "$C")" = "@echo off"$'"'"'\r'"'"' ] && [ "$(grep -c $'"'"'\r$'"'"' "$PS")" = "$(wc -l < "$PS")" ] && grep -q "ForgeOS Moving Day.pack.ps1" "$C"'
MD pack-stick "$W" >/dev/null; R1=$?; MD pack-stick "$WORK/none" >/dev/null; R2=$?
check I4 '[ "$R1$R2" = 33 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

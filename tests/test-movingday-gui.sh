#!/usr/bin/env bash
# Tests for Moving Day (Job 14), case K: the Moving Day window (kdialog is faked: it answers questions from
# $WORK/kd, one line per question, and keeps every text it showed in $WORK/shown and asked in $WORK/asked).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-movingday-gui.sh <repo-root>
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
fake kdialog 't=""; txt=""
while [ $# -gt 0 ]; do case "$1" in
  --title|--yes-label|--no-label) shift 2 ;;
  --msgbox|--sorry|--yesno|--warningyesno|--warningcontinuecancel|--menu|--checklist|--radiolist|--password|--textbox|--progressbar|--getexistingdirectory) t="$1"; txt="${2:-}"; break ;;
  *) shift ;;
esac; done
case "$t" in
  --msgbox|--sorry) printf "%s\n" "$txt" >> "$WORK/shown"; exit 0 ;;
  --textbox) cat "$txt" >> "$WORK/shown"; exit 0 ;;
  --progressbar) echo "org.kde.kdialog-1 /ProgressDialog"; exit 0 ;;
esac
a="$(head -n 1 "$WORK/kd" 2>/dev/null)"; sed -i 1d "$WORK/kd" 2>/dev/null
printf "%s\n" "$txt" >> "$WORK/asked"
case "$a" in no|"") exit 1 ;; yes) exit 0 ;; *) printf "%s\n" "$a" ;; esac'
win() { : > "$WORK/calls.log"; : > "$WORK/shown"; : > "$WORK/asked"; printf '%s\n' "${@:2}" > "$WORK/kd"; bash "$GUI" "$1"; }
W="$WORK/disks/sda3"; win_tree "$W"
WINDOWS="$(disk /dev/sda sata "$(part /dev/sda3 ntfs 475.9G Windows "")")"

# K1: the whole move - pick the drive, pick what comes over, passwords into Brave (erased after), programs
lsblk_json "$WINDOWS"
win "" s1 '"Documents" "Pictures" "bookmarks" "passwords" "programs"' yes p1 yes ""
check K1 'grep -qx "Where are your old things?" "$WORK/asked" && grep -q "^What should come over from Robert?" "$WORK/asked" && [ -f "$HOME/Documents/Taxes/2023.pdf" ] && [ -f "$HOME/Pictures/cat.jpg" ] && [ ! -e "$HOME/Music/song.mp3" ]'
check K2 'grep -q "^Copied 4 files" "$WORK/shown" && grep -qx "Your saved passwords are in Brave, and the password file was erased." "$WORK/shown" && [ ! -e "$HOME/Moving Day passwords" ] && grep -q "^setsid -f flatpak run com.brave.Browser$" "$WORK/calls.log" && grep -q "From Windows" "$HOME/brave/Default/Bookmarks"'
check K3 'grep -q "^forgeos-willitrun open open org.onlyoffice.desktopeditors$" "$WORK/calls.log" && grep -qx -- "- Some Odd Tool" "$WORK/shown" && grep -q "forgeos-movingday-mount close /dev/sda3$" "$WORK/calls.log" && [ ! -e "$WORK/mnt/sda3" ]'

# K4: BitLocker - wrong key, try again, right key; then Cancel at the list
lsblk_json "$(disk /dev/sdb usb "$(part /dev/sdb1 BitLocker 931.5G Backup "")")"; mkdir -p "$WORK/disks/sdb1-inside/Users/Ann/Documents"
echo "Ann doc" > "$WORK/disks/sdb1-inside/Users/Ann/Documents/a.txt"; echo "111111-222222" > "$WORK/bitlk-key"
win "" s1 "999999-000000" yes "111111-222222" no
check K4 'grep -q "^This drive is locked with BitLocker." "$WORK/asked" && grep -q "Try again?" "$WORK/asked" && grep -q "^What should come over from Ann?" "$WORK/asked" && [ "$(grep -c "^cryptsetup open" "$WORK/calls.log")" = 2 ] && [ ! -e "$HOME/Documents/a.txt" ]'

# K5: nothing found -> make a Moving Box stick; Brave still open at the bookmarks step
lsblk_json ""; mkdir -p "$WORK/stick2"
win "" stick "$WORK/stick2"
check K5 'grep -q "^No Windows drive or Moving Box was found." "$WORK/asked" && [ -f "$WORK/stick2/Pack my old PC.cmd" ] && grep -q "^Done. On the old Windows PC" "$WORK/shown"'
lsblk_json "$WINDOWS"; ln -s host-1 "$HOME/brave/SingletonLock"
win "" s1 '"bookmarks"' no
check K6 'grep -q "^Please close Brave first" "$WORK/asked" && grep -q "Close Brave and run Moving Day again" "$WORK/shown"'
rm "$HOME/brave/SingletonLock"

# K7: first run asks once, only when Windows is found; the password file from last time is offered for erasing
lsblk_json ""; win --first-run yes
check K7 '[ ! -s "$WORK/asked" ] && [ -e "$XDG_STATE_HOME/forgeos/movingday/offered" ]'
lsblk_json "$WINDOWS"; win --first-run yes; R1="$(wc -c < "$WORK/asked")"; rm "$XDG_STATE_HOME/forgeos/movingday/offered"; win --first-run no
check K8 '[ "$R1" = 0 ] && grep -q "^Welcome to ForgeOS!" "$WORK/asked" && [ "$(wc -l < "$WORK/asked")" = 4 ]'
MD passwords "$W" --user Robert >/dev/null; win "" yes ""
check K9 'grep -q "^The password file from last time is still here." "$WORK/asked" && [ ! -e "$HOME/Moving Day passwords" ]'
bash "$GUI" --nope 2>/dev/null; R1=$?; mv "$WORK/bin/kdialog" "$WORK/bin/kd-off"; PATH="$WORK/bin:/usr/bin:/bin" bash "$GUI" 2>/dev/null; R2=$?
check K10 '[ "$R1$R2" = 33 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

#!/usr/bin/env bash
# Tests for Why Is It Slow? (Job 20), case L: the window with a pretend kdialog - the red / yellow list, a fix,
# "Fix the safe ones", Close and Restart ask first, Free up space, Choose what starts, "It was slow a few
# minutes ago", the report for a family helper, wrong use.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-slow-gui.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/slow-fakes.sh
. "$ROOT/tests/slow-fakes.sh"
export FORGEOS_SLOW_PING=9.9.9.9
# kdialog answers from $WORK/kd-queue, one line each: "EXIT-CODE ANSWER" (| = a new line; no line left = Cancel).
# Every call is logged with its text, and --textbox files are copied to $WORK/textbox-N.
fake kdialog 'for a in "$@"; do printf "%s\n" "$a"; done >> "$WORK/kd-args"; echo "----" >> "$WORK/kd-args"
prev=""; for a in "$@"; do [ "$prev" = --textbox ] && cp "$a" "$WORK/textbox-$(ls "$WORK" | grep -c "^textbox-")"; prev="$a"; done
[ "$1 $2 $3" = "--title Why Is It Slow? --passivepopup" ] && exit 0
line="$(head -n 1 "$WORK/kd-queue" 2>/dev/null)"; sed -i 1d "$WORK/kd-queue" 2>/dev/null
[ -n "$line" ] || exit 1; echo "${line#* }" | tr "|" "\n"; exit "${line%% *}"'
win() { : > "$WORK/calls.log"; rm -f "$WORK/kd-args" "$WORK"/textbox-*; printf '%s\n' "$@" > "$WORK/kd-queue"; timeout 60 bash "$GUI" "${ARGS[@]}" >/dev/null 2>&1; echo $?; }
ARGS=()

# L1-L2: the list (worst first, colors) and a fix; the menu offers a button only for problems with a fix
mk temp "$WORK/sys" coretemp 96; echo power-saver > "$WORK/power-mode"
RC="$(win "0 fix2")"
check L1 '[ "$RC" = 0 ] && grep -q "^<b>Found 2 things slowing your PC</b> (worst first):<br><br><span style=\"color:#c62828\"><b>RED</b></span> Your PC is hot (96 degrees C)" "$WORK/kd-args" && grep -q "<b>YELLOW</b></span> Power saver mode is on" "$WORK/kd-args"'
check L2 '! grep -qx "fix1" "$WORK/kd-args" && grep -qx "Fix: Switch to Balanced" "$WORK/kd-args" && [ "$(cat "$WORK/power-mode")" = balanced ] && grep -qx "Power mode is now Balanced." "$WORK/kd-args" && [ "$(grep -c "^--menu$" "$WORK/kd-args")" = 2 ]'

# L3: Fix the safe ones - the power mode and pausing Find Anything, nothing else
normal_pc; echo power-saver > "$WORK/power-mode"; mk uptime "$WORK/proc" 30
prog 5001 comm=python3 cpu=60 "cmdline=/usr/bin/python3 -B /usr/bin/forgeos-find index"
RC="$(win "0 safe" "0 ")"
check L3 '[ "$RC" = 0 ] && [ "$(cat "$WORK/power-mode")" = balanced ] && grep -qx "systemctl --user stop forgeos-find-index.service" "$WORK/calls.log" && grep -q "^Power mode is now Balanced.<br>Find Anything is paused" "$WORK/kd-args" && ! grep -q "qdbus" "$WORK/calls.log"'

# L4-L5: Close and Restart ask first - "Cancel" / "Later" change nothing
normal_pc; app com.brave.Browser Brave; mk uptime "$WORK/proc" 30
prog 2001 comm=brave cpu=150 rss=900 cgroup=/user.slice/app-flatpak-com.brave.Browser-1.scope
RC="$(win "0 fix1" "1 " "0 fix2" "1 ")"
check L4 '[ "$RC" = 0 ] && grep -qx "Close Brave?<br><br>Unsaved work in it may be lost. Save first if you can." "$WORK/kd-args" && [ ! -e "$LOGF" ]'
check L5 'grep -qx "Restart the PC now?<br><br>Save your work first. Open programs are asked to close." "$WORK/kd-args" && grep -qx "Later" "$WORK/kd-args" && ! grep -q "qdbus" "$WORK/calls.log"'

# L6: Free up space - the picked things only; a big download goes to the Trash
normal_pc; mkdir -p "$HOME/.local/share/Trash/files" "$HOME/Downloads"
head -c 3000000 /dev/zero > "$HOME/.local/share/Trash/files/a"
head -c 5000 /dev/zero > "$HOME/Downloads/old movie.mp4"; touch -d "200 days ago" "$HOME/Downloads/old movie.mp4"
ARGS=(--space); RC="$(FORGEOS_SLOW_BIG=4000 win "0 trash|big1" "0 ")"
check L6 '[ "$RC" = 0 ] && grep -qx "Empty the Trash (2 MB)" "$WORK/kd-args" && grep -qx "Move to Trash: old movie.mp4 (0 MB, not opened for 200 days)" "$WORK/kd-args" && [ -e "$WORK/trashed/old movie.mp4" ] && [ ! -e "$HOME/.local/share/Trash/files/a" ] && ! grep -q "^flatpak" "$WORK/calls.log" && grep -q "^The Trash is empty.$" "$WORK/textbox-0"'

# L7: Choose what starts - unticked programs are switched off, ticked ones on
printf '[Desktop Entry]\nType=Application\nName=Discord\n' > "$WORK/xdg-autostart/discord.desktop"
printf '[Desktop Entry]\nType=Application\nName=Steam\n' > "$WORK/xdg-autostart/steam.desktop"
ARGS=(--startup); RC="$(win "0 steam" "0 ")"
check L7 '[ "$RC" = 0 ] && [ "$(SL startup | tr "\n" " ")" = "APP${T}discord${T}Discord${T}off APP${T}steam${T}Steam${T}on " ] && grep -q "^Discord will not start with the PC any more" "$WORK/textbox-0"'

# L8: It was slow a few minutes ago
ARGS=(--earlier); RC="$(win "0 60" "0 ")"
check L8 '[ "$RC" = 0 ] && grep -qx "In the last hour" "$WORK/kd-args" && grep -qx "Nothing was slowing the PC in the last 60 minutes." "$WORK/kd-args"'

# L9: the report for a family helper is saved in Documents
ARGS=(); RC="$(win "0 report" "0 ")"
R="$HOME/Documents/Why-Is-It-Slow-report.txt"
check L9 '[ "$RC" = 0 ] && grep -q "^Why Is It Slow? report - " "$R" && grep -qx "Your PC looks fine right now - nothing is slowing it down." "$R" && grep -qx "Earlier today: Nothing was slowing the PC in the last 1440 minutes." "$R"'

# L10: wrong use
ARGS=(--bogus); RC="$(win)"
check L10 '[ "$RC" = 3 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Why Is It Slow? tests L passed."; else echo "$failures Why Is It Slow? test(s) failed."; fi
exit "$((failures > 0))"

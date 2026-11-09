#!/usr/bin/env bash
# Tests for Why Is It Slow? (Job 20), case M: the files - setup lines, run bits, Python 3.10, clean files, the
# menu entry, the sample timer, the ties into Forge Helper (rule, tool, look, window, "still slow" note,
# KRunner) and the CI.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-slow-files.sh <repo-root>
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
SYS="$ROOT/files/system"; A="$SYS/usr/share/applications/forgeos-slow.desktop"; LIB="$FORGEOS_SLOW_LIB/slowlib"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"; HL="$SYS/usr/lib/forgeos-helper"; CI="$ROOT/.github/workflows/tests.yml"
S="$SYS/usr/lib/systemd/user/forgeos-slow-sample.service"; TM="$SYS/usr/lib/systemd/user/forgeos-slow-sample.timer"
HELP="$SYS/usr/share/forgeos/helper/help/why-is-it-slow.md"

check M1 'grep -qx "chmod 0755 /usr/bin/forgeos-slow /usr/bin/forgeos-slow-gui" "$SETUP" && grep -qx "systemctl --global enable forgeos-slow-sample.timer" "$SETUP" && [ -x "$ENGINE" ] && [ -x "$GUI" ]'
check M2 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "$ENGINE" "$HL"/helperlib/*.py && [ "$(ls "$LIB" | tr "\n" " ")" = "__init__.py checks.py cli.py fixes.py history.py hot.py judge.py more.py net.py procs.py rules.py space.py startup.py " ]'
check M3 '(for f in "$ENGINE" "$GUI" "$SYS/usr/libexec/forgeos-slow-screens" "$LIB"/*.py "$A" "$S" "$TM" "$HELP" "$HL/helperlib/looks2.py" "$ROOT"/tests/*slow*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  not clean: $f"; exit 1; }; done)'
check M4 'grep -qx "Exec=/usr/bin/forgeos-slow-gui" "$A" && grep -qx "Name=Why Is It Slow?" "$A" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A"; }'
check M5 'grep -qx "ExecStart=/usr/bin/forgeos-slow sample" "$S" && grep -qx "Nice=19" "$S" && grep -qx "OnUnitActiveSec=5min" "$TM" && grep -qx "WantedBy=timers.target" "$TM"'
# M6: Forge Helper - the rule (before the other PC problems), the tool, the window, the help card, test questions
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import actions, rules, tools
for q in ['why is my computer so slow', 'my internet is really slow tonight', 'everything is laggy', 'I have no sound',
          'my computer froze', 'is my hard drive dying', 'how do I print']:
    hit = rules.match(q); print(hit[0] if hit else '-')
print(list(tools.TOOLS).index('why_slow') == list(tools.TOOLS).index('find_my_pc') + 1, actions.WINDOWS.get('slow'))" "$HL")"
check M6 '[ "$(tr "\n" " " <<< "$ROUTES")" = "why_slow why_slow why_slow pc_question pc_question drive_health help_answer True forgeos-slow-gui " ] && head -n 1 "$HELP" | grep -qx "# Why Is It Slow?: find out why the PC is slow and fix it" && [ "$(grep -c "\"why_slow\"" "$SYS/usr/share/forgeos/helper/tests/tools-2.jsonl")" = 4 ]'
# M7: the look runs the real report; the "still slow" note only when forgeos-slow quick says so
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import looks
text, acts, _ = looks.LOOK['why_slow']('')
print(acts[0][0], acts[0][1], acts[0][2]); print(text)" "$HL")"
check M7 'sed -n 1p <<< "$OUT" | grep -qx "open slow Open Why Is It Slow?" && grep -qx "Your PC looks fine right now - nothing is slowing it down." <<< "$OUT"'
NOTE="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import checks
print(checks.check_slow())" "$HL")"
mk temp "$WORK/sys" coretemp 95; NOW="$(date +%s)"
for s in -600 -300 0; do FORGEOS_SLOW_NOW=$((NOW + s)) SL sample; done
NOTE2="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import checks
print(checks.check_slow())" "$HL")"
check M8 '[ "$NOTE" = None ] && [ "$NOTE2" = "('"'"'slow'"'"', '"'"'Your PC has been slow for 15 minutes because the PC was too hot (95 degrees C) and slowed itself down. Want to see why and fix it?'"'"', '"'"'open'"'"', '"'"'slow'"'"', '"'"'Show me'"'"')" ] && grep -q "check_hog(), check_slow(), check_backup()" "$HL/helperlib/watch.py"'
check M9 'grep -q "\"why_slow\": \"check this PC for what is slowing it\"" "$SYS/usr/libexec/forgeos-helper-krunner"'
check M10 '(for t in test-slow test-slow-more test-slow-fix test-slow-space test-slow-history test-slow-gui test-slow-safe test-slow-files; do grep -q "bash tests/$t.sh .$" "$CI" || exit 1; done)'

echo
if [ "$failures" -eq 0 ]; then echo "All Why Is It Slow? tests M passed."; else echo "$failures Why Is It Slow? test(s) failed."; fi
exit "$((failures > 0))"

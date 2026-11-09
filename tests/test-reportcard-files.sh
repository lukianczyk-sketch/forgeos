#!/usr/bin/env bash
# Tests for PC Report Card (Job 21), case M: setup lines, run bits, Python 3.10, clean files, menu entry, the
# timer, the lines it reads from the other tools, the ties into Forge Helper, and the CI.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-reportcard-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/card-fakes.sh
. "$ROOT/tests/card-fakes.sh"
SYS="$ROOT/files/system"; L="$SYS/usr/lib"; A="$SYS/usr/share/applications/forgeos-reportcard.desktop"
LIB="$FORGEOS_CARD_LIB/cardlib"; SETUP="$ROOT/files/scripts/forgeos-setup.sh"; HL="$L/forgeos-helper"
U="$SYS/usr/lib/systemd/user/forgeos-reportcard-monthly"; HELP="$SYS/usr/share/forgeos/helper/help/pc-report-card.md"

check M1 'grep -qx "chmod 0755 /usr/bin/forgeos-reportcard /usr/bin/forgeos-reportcard-gui" "$SETUP" && grep -qx "systemctl --global enable forgeos-reportcard-monthly.timer" "$SETUP" && [ -x "$ENGINE" ] && [ -x "$GUI" ]'
check M2 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "$ENGINE" "$HL"/helperlib/*.py && [ "$(ls "$LIB" | tr "\n" " ")" = "__init__.py cli.py drives.py grade.py keep.py more.py pdf.py ready.py safety.py " ]'
check M3 '(for f in "$ENGINE" "$GUI" "$LIB"/*.py "$A" "$U".* "$HELP" "$HL/helperlib/looks2.py" "$ROOT"/tests/*reportcard* "$ROOT"/tests/card-fakes.sh; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  not clean: $f"; exit 1; }; done)'
check M4 'grep -qx "Exec=/usr/bin/forgeos-reportcard-gui" "$A" && grep -qx "Name=PC Report Card" "$A" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A"; }'
check M5 'grep -qx "ExecStart=/usr/bin/forgeos-reportcard monthly" "$U.service" && grep -qx "Nice=19" "$U.service" && grep -qx "OnStartupSec=10min" "$U.timer" && grep -qx "OnCalendar=\*-\*-\* 10:00" "$U.timer" && ! grep -q "Persistent" "$U.timer" && grep -qx "KillMode=process" "$U.service" && grep -qx "WantedBy=timers.target" "$U.timer"'
# M6-M7: the lines it reads are still what the other tools print
check M6 'grep -qF "print(\"SERVICE\\t%s\" % (\"running\" if running else \"stopped\"))" "$L/forgeos-guard/guardlib/cli.py" && grep -qF "print(\"GUARD\\twebsites\\t%s\\t%d\\t%s\"" "$L/forgeos-guard/guardlib/cli.py" && grep -qF "print(\"VIRUSLIST\\t%s\"" "$L/forgeos-guard/guardlib/cli.py" && grep -qF "print(\"INTERNET\\t%s\" % (\"cut\" if f[\"cut\"] else \"normal\"))" "$L/forgeos-tripwire/tripwirelib/cli.py" && grep -qF "print(\"SERVICE\\t%s\" % (\"on\" if f[\"on\"] else \"off\"))" "$L/forgeos-techguard/techguardlib/cli.py"'
check M7 'grep -qF "print(\"UPDATES\\t%s\" % g[\"updater\"])" "$L/forgeos-autopilot/autopilotlib/report.py" && grep -qF "print(\"FIRMWARE\\t%d\\t%s\\t%s\"" "$L/forgeos-autopilot/autopilotlib/report.py" && grep -qF "print(\"CHECKED\\t%d\\t%s\" % (int(r[\"checked\"]), r[\"level\"]))" "$L/forgeos-drivehealth/drivelib/report.py" && grep -qF "\"BACKUP\\tset\\t%s\" % dash(b[\"days\"])" "$L/forgeos-drivehealth/drivelib/report.py" && grep -qF "rows.append((\"ENVELOPE\", day(st[\"made\"]), str(envelope_age(st))" "$L/forgeos-digitalwill/willlib/report.py" && grep -qF "print(\"SETUP\\t\" + (\"yes\" if s.get(\"setup\") else \"no\"))" "$L/forgeos-locate/locatelib/report.py" && grep -qF "Undo Button: ON — \$count snapshots, from" "$SYS/usr/bin/forgeos-undo" && grep -qF "store.write_json(\"last-sweep.json\", result)" "$L/forgeos-ghost/ghostlib/sweep.py" && grep -qF "log_line start \"\$kind\" \"\$key\" \"\$name\"" "$SYS/usr/bin/forgeos-privacy"'
# M8: Forge Helper - rule (emergencies still win), tool, window, KRunner, help card, questions
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import actions, rules, tools
for q in ['how healthy is my pc', 'show me my pc report card', 'what grade does my computer get', 'is my laptop healthy',
          'is my computer healthy enough to run cyberpunk', 'is my hard drive dying', 'why is my computer so slow', 'how do I print',
          'my pc health warning says ransomware', 'is my computer healthy or hacked']:
    hit = rules.match(q); print(hit[0] if hit else '-')
t = list(tools.TOOLS); print(t.index('report_card') == t.index('why_slow') + 1, actions.WINDOWS.get('reportcard'))" "$HL")"
check M8 '[ "$(tr "\n" " " <<< "$ROUTES")" = "report_card report_card report_card report_card - drive_health why_slow help_answer ransomware cleansweep_scan True forgeos-reportcard-gui " ] && head -n 1 "$HELP" | grep -qx "# PC Report Card: how healthy is my PC?" && [ "$(grep -c "\"report_card\"" "$SYS/usr/share/forgeos/helper/tests/tools-2.jsonl")" = 3 ] && grep -qF "\"report_card\": \"show your PC Report Card\"" "$SYS/usr/libexec/forgeos-helper-krunner"'
# M9: the look runs the real report card; will_it_run (now in looks2.py) still works
healthy_pc
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import looks
text, acts, _ = looks.LOOK['report_card']('')
print(text.splitlines()[0]); print(acts); print(looks.LOOK['will_it_run'].__module__)" "$HL")"
check M9 '[ "$(sed -n 1p <<< "$OUT")" = "PC Report Card: A - Excellent" ] && [ "$(sed -n 2p <<< "$OUT")" = "[('"'"'open'"'"', '"'"'reportcard'"'"', '"'"'Open PC Report Card'"'"')]" ] && [ "$(sed -n 3p <<< "$OUT")" = helperlib.looks2 ]'
check M10 '(for t in "" -drives -more -keep -gui -files; do grep -qx "          bash tests/test-reportcard$t.sh ." "$ROOT/.github/workflows/tests.yml" || exit 1; done)'

echo
if [ "$failures" -eq 0 ]; then echo "All PC Report Card tests M passed."; else echo "$failures test(s) failed."; fi
exit "$((failures > 0))"

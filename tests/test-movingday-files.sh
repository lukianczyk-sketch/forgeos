#!/usr/bin/env bash
# Tests for Moving Day (Job 14), case L: the build files - run bits, polkit rule, menu entry + first-run
# autostart, Forge Helper's new tool + help card, the CI step, small LF-only files without tabs (Cline limit).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-movingday-files.sh <repo-root>
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
A="$SYS/usr/share/applications"; P="$SYS/usr/share/polkit-1/actions/org.forgeos.movingday.policy"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"; HL="$SYS/usr/lib/forgeos-helper"; LIB="$FORGEOS_MD_LIB/movelib"

check L1 'grep -q "^chmod 0755 .* /usr/libexec/forgeos-switch-winsetup /usr/bin/forgeos-movingday /usr/bin/forgeos-movingday-gui /usr/libexec/forgeos-movingday-mount\( \|$\)" "$SETUP" && [ -x "$ENGINE" ] && [ -x "$GUI" ] && [ -x "$FORGEOS_MD_MOUNT" ]'
POL="$(python3 -c "
import sys, xml.dom.minidom as m
d = m.parse(sys.argv[1])
for a in d.getElementsByTagName('action'):
    get = lambda t: a.getElementsByTagName(t)[0].firstChild.data
    path = [x.firstChild.data for x in a.getElementsByTagName('annotate')][0]
    print(a.getAttribute('id'), get('allow_active'), get('allow_any'), get('allow_inactive'), path)" "$P")"
check L2 '[ "$POL" = "org.forgeos.movingday.mount auth_admin_keep auth_admin auth_admin /usr/libexec/forgeos-movingday-mount" ]'
check L3 'grep -qx "Exec=/usr/bin/forgeos-movingday-gui" "$A/forgeos-movingday.desktop" && grep -qx "Exec=/usr/bin/forgeos-movingday-gui --first-run" "$SYS/etc/xdg/autostart/forgeos-movingday-firstrun.desktop" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A/forgeos-movingday.desktop" "$SYS/etc/xdg/autostart/forgeos-movingday-firstrun.desktop"; }'
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import actions, rules, tools
for q in ['move my files from my old computer', 'copy everything from the windows drive', 'open moving day',
          'restart into windows', 'where did my tax papers go', 'will excel run on this']:
    hit = rules.match(q); print(hit[0] if hit else '-')
print('moving_day' in tools.TOOLS, actions.WINDOWS.get('movingday'))" "$HL")"
check L4 '[ "$(tr "\n" " " <<< "$ROUTES")" = "moving_day moving_day moving_day switch_windows find will_it_run True forgeos-movingday-gui " ] && head -n 1 "$SYS/usr/share/forgeos/helper/help/moving-day.md" | grep -qx "# Moving Day: bring your things over from Windows"'
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import looks
act = looks.LOOK['moving_day']('')[1][0]; print(act[0], act[1], act[2])" "$HL")"
check L5 '[ "$OUT" = "open movingday Open Moving Day" ] && grep -q "\"tool\": \"moving_day\"" "$SYS/usr/share/forgeos/helper/tests/tools-2.jsonl"'
check L6 '(for f in "$ENGINE" "$GUI" "$FORGEOS_MD_MOUNT" "$FORGEOS_MD_SCREENS" "$LIB"/*.py "$FORGEOS_MD_SHARE"/* "$A"/forgeos-movingday.desktop "$P" "$SYS"/etc/xdg/autostart/forgeos-movingday-firstrun.desktop "$SYS"/usr/share/forgeos/helper/help/moving-day.md "$ROOT"/tests/*movingday*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  too big, CRLF, tab or no last newline: $f"; exit 1; }; done)'
check L7 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]" "$LIB"/*.py "$ENGINE" && [ "$(ls "$LIB" | tr "\n" " ")" = "__init__.py bookmarks.py brave.py cli.py files.py move.py passwords.py programs.py scan.py sources.py stick.py " ]'
check L8 '(for t in test-movingday test-movingday-move test-movingday-more test-movingday-win test-movingday-gui test-movingday-files; do grep -q "bash tests/$t.sh ." "$ROOT/.github/workflows/tests.yml" || exit 1; done)'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

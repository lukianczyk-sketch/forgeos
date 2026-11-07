#!/usr/bin/env bash
# Tests for Fake Tech Support Guard (Job 17), case M: the files - setup lines, run bits, Python 3.10, menu
# entries and the Ctrl+Alt+K key, polkit rules, the user unit, and the ties into Forge Helper, Family Mode,
# Scam Shield and the CI.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-techguard-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/techguard-fakes.sh
. "$ROOT/tests/techguard-fakes.sh"
SYS="$ROOT/files/system"; A="$SYS/usr/share/applications"; P="$SYS/usr/share/polkit-1/actions/org.forgeos.techguard.policy"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"; HL="$SYS/usr/lib/forgeos-helper"; LIB="$FORGEOS_TG_LIB/techguardlib"
UU="$SYS/usr/lib/systemd/user/forgeos-techguard.service"; FL="$SYS/usr/lib/forgeos-family/familylib"

check M1 'grep -qx "chmod 0755 /usr/bin/forgeos-techguard /usr/bin/forgeos-techguard-gui /usr/libexec/forgeos-techguard-money /usr/libexec/forgeos-techguard-trust" "$SETUP" && grep -qx "systemctl --global enable forgeos-techguard.service" "$SETUP" && [ -x "$ENGINE" ] && [ -x "$GUI" ] && [ -x "$FORGEOS_TG_MONEY" ] && [ -x "$FORGEOS_TG_TRUST" ]'
check M2 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "$ENGINE" && [ "$(ls "$LIB" | tr "\n" " ")" = "__init__.py actions.py alarm.py apps.py cli.py kick.py money.py notes.py procs.py screen.py watch.py " ]'
check M3 '(for f in "$ENGINE" "$GUI" "$FORGEOS_TG_MONEY" "$FORGEOS_TG_TRUST" "$SYS"/usr/libexec/forgeos-techguard-screens "$LIB"/*.py "$P" "$UU" "$A"/forgeos-techguard.desktop "$A"/forgeos-kickout.desktop "$SYS"/usr/share/forgeos/techguard/* "$SYS"/usr/share/forgeos/helper/help/tech-support-guard.md "$ROOT"/tests/*techguard*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  not clean: $f"; exit 1; }; done)'
check M4 'grep -qx "Exec=/usr/bin/forgeos-techguard-gui" "$A/forgeos-techguard.desktop" && grep -qx "Exec=/usr/bin/forgeos-techguard-gui --kick" "$A/forgeos-kickout.desktop" && grep -qx "X-KDE-Shortcuts=Ctrl+Alt+K" "$A/forgeos-kickout.desktop" && grep -qx "Name=Kick them out" "$A/forgeos-kickout.desktop" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A/forgeos-techguard.desktop" "$A/forgeos-kickout.desktop"; }'
POL="$(python3 -c "
import sys, xml.dom.minidom as m
d = m.parse(sys.argv[1])
for a in d.getElementsByTagName('action'):
    get = lambda t: a.getElementsByTagName(t)[0].firstChild.data
    path = [x.firstChild.data for x in a.getElementsByTagName('annotate')][0]
    print(a.getAttribute('id'), get('allow_active'), get('allow_any'), get('allow_inactive'), path)" "$P")"
check M5 '[ "$POL" = "org.forgeos.techguard.money yes auth_admin auth_admin /usr/libexec/forgeos-techguard-money
org.forgeos.techguard.trust auth_admin auth_admin auth_admin /usr/libexec/forgeos-techguard-trust" ]'
check M6 'grep -qx "ExecStart=/usr/bin/forgeos-techguard watch" "$UU" && grep -qx "WantedBy=graphical-session.target" "$UU" && grep -qx "Restart=always" "$UU"'
# M8: Forge Helper - the rule, the tool, the window, the help card, the test questions
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import actions, rules, tools
for q in ['a man on the phone wants me to install anydesk', 'someone is controlling my mouse', 'kick them out',
          'microsoft called and said my computer has a virus', 'I want remote help', 'all my files are encrypted']:
    hit = rules.match(q); print(hit[0] if hit else '-')
print('tech_support' in tools.TOOLS, actions.WINDOWS.get('techguard'))" "$HL")"
check M8 '[ "$(tr "\n" " " <<< "$ROUTES")" = "tech_support tech_support tech_support scam_check family_call ransomware True forgeos-techguard-gui " ] && head -n 1 "$SYS/usr/share/forgeos/helper/help/tech-support-guard.md" | grep -qx "# Fake Tech Support Guard: stops a stranger from taking over your PC" && [ "$(grep -c "\"tool\": \"tech_support\"" "$SYS/usr/share/forgeos/helper/tests/tools-2.jsonl")" = 5 ]'
fresh
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import looks
text, acts, _ = looks.LOOK['tech_support']('')
print(acts[0][0], acts[0][1], acts[0][2]); print(text)" "$HL")"
check M9 'sed -n 1p <<< "$OUT" | grep -qx "open techguard Open Fake Tech Support Guard" && grep -q "Fake Tech Support Guard is ON" <<< "$OUT" && grep -q "Ctrl+Alt+K" <<< "$OUT"'
# M10: Family Mode lists the guard and puts a "Kick them out" desktop icon; Scam Shield points to Ctrl+Alt+K; CI runs every test
check M10 'grep -q "(\"forgeos-techguard.service\", \"Fake Tech Support Guard - stops a stranger from taking over this PC\")" "$FL/guards.py" && grep -q "(\"forgeos-kickout.desktop\", \"Kick them out\")" "$FL/cli.py" && grep -q "^remote ~ .*(Ctrl+Alt+K kicks them out)\.$" "$SYS/usr/share/forgeos/scamshield-words.txt"'
check M11 '(for t in test-techguard test-techguard-more test-techguard-money test-techguard-kick test-techguard-gui test-techguard-files; do grep -q "bash tests/$t.sh .$" "$ROOT/.github/workflows/tests.yml" || exit 1; done)'

echo
if [ "$failures" -eq 0 ]; then echo "All Fake Tech Support Guard tests M passed."; else echo "$failures Fake Tech Support Guard test(s) failed."; fi
exit "$((failures > 0))"

#!/usr/bin/env bash
# Tests for Digital Will (Job 18), case L: the files - setup lines, run bits, Python 3.10, clean files, the
# menu entry, polkit (always asks for the PC password), the reminder timer, 7-Zip in the image, the word list
# and the lists, and the ties into Forge Helper and the CI.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-digitalwill-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/digitalwill-fakes.sh
. "$ROOT/tests/digitalwill-fakes.sh"
A="$SYS/usr/share/applications/forgeos-digitalwill.desktop"; P="$SYS/usr/share/polkit-1/actions/org.forgeos.digitalwill.policy"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"; HL="$SYS/usr/lib/forgeos-helper"; LIB="$FORGEOS_WILL_LIB/willlib"
U="$SYS/usr/lib/systemd/user/forgeos-digitalwill-remind"; SH="$FORGEOS_WILL_SHARE"; X="$SYS/usr/libexec/forgeos-digitalwill"

check L1 'grep -qx "chmod 0755 /usr/bin/forgeos-digitalwill /usr/bin/forgeos-digitalwill-gui /usr/libexec/forgeos-digitalwill-unlock" "$SETUP" && grep -qx "systemctl --global enable forgeos-digitalwill-remind.timer" "$SETUP" && [ -x "$ENGINE" ] && [ -x "$GUI" ] && [ -x "$X-unlock" ]'
check L2 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "$ENGINE" && [ "$(ls "$LIB" | tr "\n" " ")" = "__init__.py actions.py cards.py cli.py draft.py pack.py pages.py remind.py report.py unlock.py words.py " ]'
check L3 '(for f in "$ENGINE" "$GUI" "$X"-* "$LIB"/*.py "$P" "$U".* "$A" "$SH"/* "$SYS"/usr/share/forgeos/helper/help/digital-will.md "$ROOT"/tests/*digitalwill*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  not clean: $f"; exit 1; }; done)'
check L4 'grep -qx "Exec=/usr/bin/forgeos-digitalwill-gui" "$A" && grep -qx "Name=Digital Will" "$A" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A"; }'
POL="$(python3 -c "
import sys, xml.dom.minidom as m
d = m.parse(sys.argv[1])
for a in d.getElementsByTagName('action'):
    get = lambda t: a.getElementsByTagName(t)[0].firstChild.data
    path = [x.firstChild.data for x in a.getElementsByTagName('annotate')][0]
    print(a.getAttribute('id'), get('allow_active'), get('allow_any'), get('allow_inactive'), path)" "$P")"
check L5 '[ "$POL" = "org.forgeos.digitalwill.unlock auth_admin auth_admin auth_admin /usr/libexec/forgeos-digitalwill-unlock" ]'
check L6 'grep -qx "ExecStart=/usr/bin/forgeos-digitalwill tick" "$U.service" && grep -qx "Type=oneshot" "$U.service" && grep -qx "OnUnitActiveSec=1d" "$U.timer" && grep -qx "WantedBy=timers.target" "$U.timer"'
check L7 'grep -qx "        - 7zip               # Digital Will (Job 18): 7z locks the Emergency Envelope (AES-256) and tests it" "$ROOT/recipes/common-modules.yml"'
# L8: the word list (EFF Short Wordlist, 1,295 words, no repeats), the account list and the company checklist
WL="$(grep -hv "^#" "$SH"/words-1.txt "$SH"/words-2.txt | tr " " "\n" | grep -c .)"
check L8 '[ "$WL" = 1295 ] && [ "$(grep -hv "^#" "$SH"/words-*.txt | tr " " "\n" | grep . | sort -u | wc -l)" = 1295 ] && head -n 2 "$SH/words-1.txt" | grep -q "EFF Short Wordlist 1 (eff.org/dice) by the Electronic Frontier Foundation, CC BY 3.0 US" && [ "$(grep -vc "^#" "$SH/accounts.txt")" = 23 ] && [ "$(grep -vc "^#" "$SH/legacy.txt")" = 5 ] && ! grep -v "^#" "$SH/legacy.txt" | cut -d "~" -f 3 | grep -v "^ https://[a-z./0-9?=-]* $\|^ - $"'
# L9: Forge Helper - the rule, the tool, the window, the help card, the test questions
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import actions, rules, tools
for q in ['if i die how will my family get into my computer', 'I want to make a digital will', 'what happens to my facebook when I pass away',
          'will my game run on this pc', 'a man on the phone wants to get into my computer', 'my computer died']:
    hit = rules.match(q); print(hit[0] if hit else '-')
print('digital_will' in tools.TOOLS, actions.WINDOWS.get('digitalwill'))" "$HL")"
check L9 '[ "$(tr "\n" " " <<< "$ROUTES")" = "digital_will digital_will digital_will will_it_run tech_support - True forgeos-digitalwill-gui " ] && head -n 1 "$SYS/usr/share/forgeos/helper/help/digital-will.md" | grep -qx "# Digital Will: lets your family get into your PC and accounts if something happens to you" && [ "$(grep -c "\"tool\": \"digital_will\"" "$SYS/usr/share/forgeos/helper/tests/tools-2.jsonl")" = 3 ]'
fresh; answers > /dev/null
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import looks
text, acts, _ = looks.LOOK['digital_will']('')
print(acts[0][0], acts[0][1], acts[0][2]); print(text)" "$HL")"
check L10 'sed -n 1p <<< "$OUT" | grep -qx "open digitalwill Open Digital Will" && grep -q "Trusted people: Brianna, Kasia." <<< "$OUT" && grep -q "No Emergency Envelope made yet" <<< "$OUT"'
check L11 '(for t in test-digitalwill test-digitalwill-make test-digitalwill-more test-digitalwill-unlock test-digitalwill-remind test-digitalwill-gui test-digitalwill-files; do grep -q "bash tests/$t.sh .$" "$ROOT/.github/workflows/tests.yml" || exit 1; done) && grep -q "sudo apt-get install -y --no-install-recommends desktop-file-utils 7zip cryptsetup-bin$" "$ROOT/.github/workflows/tests.yml"'

echo
if [ "$failures" -eq 0 ]; then echo "All Digital Will tests L passed."; else echo "$failures Digital Will test(s) failed."; fi
exit "$((failures > 0))"

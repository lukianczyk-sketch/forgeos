#!/usr/bin/env bash
# Tests for Find My PC (Job 19), case K: the files - setup lines, run bits, Python 3.10, clean files, the menu
# entry, polkit (always the PC password), the services, the packages in the image, the settings, the ties into
# Forge Helper, and the CI.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-locate-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/locate-fakes.sh
. "$ROOT/tests/locate-fakes.sh"
A="$SYS/usr/share/applications/forgeos-locate.desktop"; P="$SYS/usr/share/polkit-1/actions/org.forgeos.locate.policy"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"; HL="$SYS/usr/lib/forgeos-helper"; LIB="$FORGEOS_LOC_LIB/locatelib"
S="$SYS/usr/lib/systemd/system/forgeos-locate.service"; U="$SYS/usr/lib/systemd/user/forgeos-locate-alert.service"
X="$SYS/usr/libexec/forgeos-locate"; HELP="$SYS/usr/share/forgeos/helper/help/find-my-pc.md"; CI="$ROOT/.github/workflows/tests.yml"

check K1 'grep -qx "chmod 0755 /usr/bin/forgeos-locate /usr/bin/forgeos-locate-gui /usr/libexec/forgeos-locate-root" "$SETUP" && grep -qx "systemctl enable forgeos-locate.service" "$SETUP" && grep -qx "systemctl --global enable forgeos-locate-alert.service" "$SETUP" && [ -x "$ENGINE" ] && [ -x "$GUI" ] && [ -x "$X-root" ]'
check K2 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "$ENGINE" && [ "$(ls "$LIB" | tr "\n" " ")" = "__init__.py alert.py cli.py commands.py relay.py report.py seal.py setup.py watch.py where.py " ]'
check K3 '(for f in "$ENGINE" "$GUI" "$X"-* "$LIB"/*.py "$P" "$S" "$U" "$A" "$HELP" "$FORGEOS_LOC_SHARE"/* "$ROOT"/docs/find/* "$ROOT"/docs/.nojekyll "$ROOT"/tests/*locate*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  not clean: $f"; exit 1; }; done)'
check K4 'grep -qx "Exec=/usr/bin/forgeos-locate-gui" "$A" && grep -qx "Name=Find My PC" "$A" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A"; }'
POL="$(python3 -c "
import sys, xml.dom.minidom as m
d = m.parse(sys.argv[1])
for a in d.getElementsByTagName('action'):
    get = lambda t: a.getElementsByTagName(t)[0].firstChild.data
    path = [x.firstChild.data for x in a.getElementsByTagName('annotate')][0]
    print(a.getAttribute('id'), get('allow_active'), get('allow_any'), get('allow_inactive'), path)" "$P")"
check K5 '[ "$POL" = "org.forgeos.locate.root auth_admin auth_admin auth_admin /usr/libexec/forgeos-locate-root" ]'
check K6 'grep -qx "ExecStart=/usr/bin/forgeos-locate watch" "$S" && grep -qx "WantedBy=multi-user.target" "$S" && grep -qx "StateDirectory=forgeos-locate" "$S" && grep -qx "RuntimeDirectoryMode=0755" "$S" && grep -qx "ExecStart=/usr/bin/forgeos-locate alert-watch" "$U" && grep -qx "WantedBy=graphical-session.target" "$U"'
check K7 'grep -qx "        - qrencode           # Find My PC (Job 19): the QR code your phone scans to set up" "$ROOT/recipes/common-modules.yml" && grep -qx "        - python3-cryptography  # Find My PC (Job 19): AES-256-GCM, the lock between this PC and your phone" "$ROOT/recipes/common-modules.yml"'
check K8 'python3 -c "
import json, sys
s = json.load(open(sys.argv[1]))
assert sorted(s) == [\"geo\", \"ip\", \"page\", \"relay\"] and all(v.startswith(\"https://\") for v in s.values())
assert s[\"relay\"] == \"https://ntfy.sh\" and s[\"page\"] == \"https://lukianczyk-sketch.github.io/forgeos/find/\"" "$FORGEOS_LOC_SHARE/settings.json"'
# K9: Forge Helper - the rule (first, before the AI), the tool, the window, the help card, the test questions
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import actions, rules, tools
for q in ['my laptop was stolen', 'how do I find my laptop if I lose it', 'someone stole my computer', 'where is my computer',
          'find my photos from the trip', 'my laptop is missing a key', 'if i die how will my family get into my computer']:
    hit = rules.match(q); print(hit[0] if hit else '-')
print('find_my_pc' in tools.TOOLS, actions.WINDOWS.get('locate'))" "$HL")"
check K9 '[ "$(tr "\n" " " <<< "$ROUTES")" = "find_my_pc find_my_pc find_my_pc - find - digital_will True forgeos-locate-gui " ] && head -n 1 "$HELP" | grep -qx "# Find My PC: find, ring and lock this PC from your phone if it is lost or stolen" && [ "$(grep -c "\"tool\": \"find_my_pc\"" "$SYS/usr/share/forgeos/helper/tests/tools-2.jsonl")" = 3 ]'
fresh
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import looks
text, acts, _ = looks.LOOK['find_my_pc']('')
print(acts[0][0], acts[0][1], acts[0][2]); print(text)" "$HL")"
check K10 'sed -n 1p <<< "$OUT" | grep -qx "open locate Open Find My PC" && grep -q "Find My PC is not set up yet" <<< "$OUT"'
check K11 '(for t in test-locate test-locate-watch test-locate-commands test-locate-alert test-locate-gui test-locate-page test-locate-files; do grep -q "bash tests/$t.sh .$" "$CI" || exit 1; done) && grep -q "sudo apt-get install -y --no-install-recommends desktop-file-utils python3-cryptography$" "$CI"'

echo
if [ "$failures" -eq 0 ]; then echo "All Find My PC tests K passed."; else echo "$failures Find My PC test(s) failed."; fi
exit "$((failures > 0))"

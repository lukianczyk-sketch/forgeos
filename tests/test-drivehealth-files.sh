#!/usr/bin/env bash
# Tests for Drive Death Warning (Job 15), case K: the build files - run bits + timers in forgeos-setup.sh,
# smartmontools in the image, systemd units, polkit rule, menu entry, Forge Helper's new tool + help card,
# the CI step, small LF-only files without tabs (Cline limit).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-drivehealth-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/drivehealth-fakes.sh
. "$ROOT/tests/drivehealth-fakes.sh"
SYS="$ROOT/files/system"; A="$SYS/usr/share/applications"; P="$SYS/usr/share/polkit-1/actions/org.forgeos.drivehealth.policy"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"; HL="$SYS/usr/lib/forgeos-helper"; LIB="$FORGEOS_DH_LIB/drivelib"
SU="$SYS/usr/lib/systemd/system"; UU="$SYS/usr/lib/systemd/user"

check K1 'grep -q "^chmod 0755 .* /usr/libexec/forgeos-movingday-mount /usr/bin/forgeos-drivehealth /usr/bin/forgeos-drivehealth-gui /usr/libexec/forgeos-drivehealth-check\( .*\)\?$" "$SETUP" && grep -qx "systemctl enable forgeos-drivehealth.timer" "$SETUP" && grep -qx "systemctl --global enable forgeos-drivehealth-notify.timer" "$SETUP"'
check K2 '[ -x "$ENGINE" ] && [ -x "$GUI" ] && [ -x "$FORGEOS_DH_CHECKER" ] && grep -q "^        - smartmontools " "$ROOT/recipes/common-modules.yml"'
check K3 'grep -qx "ExecStart=/usr/bin/forgeos-drivehealth system-check --timer" "$SU/forgeos-drivehealth.service" && grep -qx "StateDirectory=forgeos-drivehealth" "$SU/forgeos-drivehealth.service" && grep -qx "ProtectHome=read-only" "$SU/forgeos-drivehealth.service" && grep -qx "OnBootSec=10min" "$SU/forgeos-drivehealth.timer" && grep -qx "Persistent=true" "$SU/forgeos-drivehealth.timer"'
check K4 'grep -qx "ExecStart=/usr/bin/forgeos-drivehealth tick" "$UU/forgeos-drivehealth-notify.service" && grep -qx "OnStartupSec=12min" "$UU/forgeos-drivehealth-notify.timer" && grep -qx "OnUnitActiveSec=2h" "$UU/forgeos-drivehealth-notify.timer"'
POL="$(python3 -c "
import sys, xml.dom.minidom as m
d = m.parse(sys.argv[1])
for a in d.getElementsByTagName('action'):
    get = lambda t: a.getElementsByTagName(t)[0].firstChild.data
    path = [x.firstChild.data for x in a.getElementsByTagName('annotate')][0]
    print(a.getAttribute('id'), get('allow_active'), get('allow_any'), get('allow_inactive'), path)" "$P")"
check K5 '[ "$POL" = "org.forgeos.drivehealth.check yes auth_admin auth_admin /usr/libexec/forgeos-drivehealth-check" ]'
check K6 'grep -qx "Exec=/usr/bin/forgeos-drivehealth-gui" "$A/forgeos-drivehealth.desktop" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A/forgeos-drivehealth.desktop"; }'
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import actions, rules, tools
for q in ['is my hard drive dying', 'my computer makes a clicking noise from the drive', 'is my ssd healthy',
          'check my drive health', 'my drive is full', 'update my drivers', 'copy everything from the windows drive']:
    hit = rules.match(q); print(hit[0] if hit else '-')
print('drive_health' in tools.TOOLS, actions.WINDOWS.get('drivehealth'))" "$HL")"
check K7 '[ "$(tr "\n" " " <<< "$ROUTES")" = "drive_health drive_health drive_health drive_health pc_question drivers moving_day True forgeos-drivehealth-gui " ] && head -n 1 "$SYS/usr/share/forgeos/helper/help/drive-health.md" | grep -qx "# Drive Health: a warning before a drive dies"'
normal_pc; DH system-check >/dev/null
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import looks
text, acts, _ = looks.LOOK['drive_health']('')
print(acts[0][0], acts[0][1], acts[0][2]); print(text)" "$HL")"
check K8 'sed -n 1p <<< "$OUT" | grep -qx "open drivehealth Open Drive Health" && grep -q "Samsung SSD 990 PRO 1TB (NVMe SSD, 1 TB): Good" <<< "$OUT" && grep -q "\"tool\": \"drive_health\"" "$SYS/usr/share/forgeos/helper/tests/tools-2.jsonl"'
check K9 '(for f in "$ENGINE" "$GUI" "$FORGEOS_DH_CHECKER" "$LIB"/*.py "$A"/forgeos-drivehealth.desktop "$P" "$SU"/forgeos-drivehealth.* "$UU"/forgeos-drivehealth-notify.* "$SYS"/usr/share/forgeos/helper/help/drive-health.md "$ROOT"/tests/*drivehealth*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  too big, CRLF, tab or no last newline: $f"; exit 1; }; done)'
check K10 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "$ENGINE" && [ "$(ls "$LIB" | tr "\n" " ")" = "__init__.py backup.py btrfs.py check.py cli.py disks.py judge.py report.py selftest.py smart.py tick.py " ]'
check K11 '(for t in test-drivehealth test-drivehealth-danger test-drivehealth-more test-drivehealth-tick test-drivehealth-gui test-drivehealth-files; do grep -q "bash tests/$t.sh ." "$ROOT/.github/workflows/tests.yml" || exit 1; done)'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

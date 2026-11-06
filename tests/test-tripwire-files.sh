#!/usr/bin/env bash
# Tests for Ransomware Tripwire (Job 16), case N: every file is there and small enough for the Rabbit Team,
# menu entry, polkit rules, systemd units, setup lines, the trusted list, and the ties into Forge Helper,
# Family Mode and the CI workflow.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-tripwire-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
SYS="$ROOT/files/system"
LIB="$SYS/usr/lib/forgeos-tripwire/tripwirelib"
ENGINE="$SYS/usr/bin/forgeos-tripwire"; GUI="$SYS/usr/bin/forgeos-tripwire-gui"
HELP="$SYS/usr/libexec/forgeos-tripwire-helper"; REL="$SYS/usr/libexec/forgeos-tripwire-release"
P="$SYS/usr/share/polkit-1/actions/org.forgeos.tripwire.policy"; D="$SYS/usr/share/applications/forgeos-tripwire.desktop"
S="$SYS/usr/lib/systemd/system/forgeos-tripwire.service"; U="$SYS/usr/lib/systemd/user/forgeos-tripwire-alert.service"
L="$SYS/etc/forgeos/tripwire-trusted.list"; C="$SYS/usr/share/forgeos/helper/help/ransomware-tripwire.md"
HL="$SYS/usr/lib/forgeos-helper/helperlib"; SETUP="$ROOT/files/scripts/forgeos-setup.sh"
MODS="__init__ actions alert bait cli detect incident kernel procs restore scramble watch"

check N1 '(for m in $MODS; do [ -f "$LIB/$m.py" ] || exit 1; done; for f in "$ENGINE" "$GUI" "$HELP" "$REL" "$P" "$D" "$S" "$U" "$L" "$C"; do [ -f "$f" ] || exit 1; done) && [ "$(ls "$LIB" | grep -c "\.py$")" = 12 ]'
check N2 '(for f in "$ENGINE" "$GUI" "$HELP" "$REL" "$LIB"/*.py "$P" "$D" "$S" "$U" "$L" "$C" "$ROOT"/tests/*tripwire*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  too big, CRLF, tab or no last newline: $f"; exit 1; }; done)'
check N3 'python3 -B -c "import ast,sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "$ENGINE"'
if command -v desktop-file-validate >/dev/null 2>&1; then
  check N4 'desktop-file-validate "$D" && grep -qx "Exec=/usr/bin/forgeos-tripwire-gui" "$D"'
else
  echo "SKIP N4 desktop-file-validate is not installed"
fi
check N5 'python3 -c "import sys, xml.dom.minidom as m; m.parse(sys.argv[1])" "$P" && [ "$(grep -c "<allow_active>yes</allow_active>" "$P")" = 1 ] && [ "$(grep -c "<allow_active>auth_admin</allow_active>" "$P")" = 1 ] && grep -q "exec.path\">/usr/libexec/forgeos-tripwire-helper<" "$P" && grep -q "exec.path\">/usr/libexec/forgeos-tripwire-release<" "$P"'
check N6 'grep -qx "ExecStart=/usr/bin/forgeos-tripwire watch" "$S" && grep -qx "Restart=always" "$S" && grep -qx "WantedBy=multi-user.target" "$S" && grep -qx "RuntimeDirectoryPreserve=yes" "$S" && grep -qx "ExecStart=/usr/bin/forgeos-tripwire alert-watch" "$U" && grep -qx "WantedBy=graphical-session.target" "$U"'
check N7 'grep -q "/usr/bin/forgeos-tripwire /usr/bin/forgeos-tripwire-gui /usr/libexec/forgeos-tripwire-helper /usr/libexec/forgeos-tripwire-release$" "$SETUP" && grep -qx "systemctl enable forgeos-tripwire.service" "$SETUP" && grep -qx "systemctl --global enable forgeos-tripwire-alert.service" "$SETUP"'
check N8 '! grep -v "^#" "$L" | grep -v "^/usr/" | grep -v "^/app/" | grep -q . && ! grep -Eq "python|bash|wine|7z|zip|gpg|openssl|rsync|rclone" <(grep -v "^#" "$L")'
check N9 'grep -q "\"ransomware\": " "$HL/tools.py" && grep -q "forgeos-tripwire\", \"report\"" "$HL/looks.py" && grep -q "\"tripwire\": \"forgeos-tripwire-gui\"" "$HL/actions.py" && grep -q "forgeos-tripwire.service" "$SYS/usr/lib/forgeos-family/familylib/guards.py"'
check N10 'python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import rules
for q in [\"all my files are encrypted and there is a ransom note\", \"is my pc safe from ransomware\", \"my photos won'"'"'t open, they were scrambled\"]:
    assert rules.match(q)[0] == \"ransomware\", q
assert rules.match(\"I think I have a virus\")[0] == \"cleansweep_scan\"
" "$SYS/usr/lib/forgeos-helper"'
check N11 '(for t in tripwire tripwire-more tripwire-bait tripwire-restore tripwire-actions tripwire-gui tripwire-kernel tripwire-files; do grep -q "bash tests/test-$t.sh \.$" "$ROOT/.github/workflows/tests.yml" || exit 1; done)'
check N12 'grep -q "^words: .*ransomware" "$C" && [ "$(head -n 1 "$C")" = "# Ransomware Tripwire: stops a program that scrambles your files" ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

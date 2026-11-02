#!/usr/bin/env bash
# Tests for Driver & BIOS Autopilot (Job 13d), case Q: the build files - run bits, the user timer, menu entry,
# the fwupd packages, Family Mode's guard list, Forge Helper's new tool and help card, the BIOS maker pages,
# the CI step, Python that parses, small LF-only files without tabs (Cline limit).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-autopilot-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/autopilot-fakes.sh
. "$ROOT/tests/autopilot-fakes.sh"
SYS="$ROOT/files/system"; U="$SYS/usr/lib/systemd/user"; LIB="$FORGEOS_AP_LIB/autopilotlib"; A="$SYS/usr/share/applications"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"; M="$ROOT/recipes/common-modules.yml"; SH="$FORGEOS_AP_SHARE"
HL="$SYS/usr/lib/forgeos-helper"

check Q1 'grep -q "^chmod 0755 .* /usr/libexec/forgeos-helper-krunner /usr/bin/forgeos-autopilot /usr/bin/forgeos-autopilot-gui$" "$SETUP" && grep -qx "systemctl enable fwupd-refresh.timer" "$SETUP" && grep -qx "systemctl --global enable forgeos-autopilot.timer" "$SETUP"'
check Q2 'grep -qx "ExecStart=/usr/bin/forgeos-autopilot tick" "$U/forgeos-autopilot.service" && grep -qx "Type=oneshot" "$U/forgeos-autopilot.service" && grep -qx "Nice=19" "$U/forgeos-autopilot.service" && grep -qx "TimeoutStartSec=3h" "$U/forgeos-autopilot.service" && grep -qx "OnStartupSec=2min" "$U/forgeos-autopilot.timer" && grep -qx "OnUnitActiveSec=6h" "$U/forgeos-autopilot.timer" && grep -qx "WantedBy=timers.target" "$U/forgeos-autopilot.timer"'
check Q3 'grep -qx "Exec=/usr/bin/forgeos-autopilot-gui" "$A/forgeos-autopilot.desktop" && grep -qx "Name=Drivers & BIOS" "$A/forgeos-autopilot.desktop" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A/forgeos-autopilot.desktop"; }'
check Q4 'grep -q "^        - fwupd  *# Driver & BIOS Autopilot" "$M" && grep -q "^        - fwupd-efi  *# Driver & BIOS Autopilot" "$M" && grep -q "(\"forgeos-autopilot.timer\", \"Drivers & BIOS" "$SYS/usr/lib/forgeos-family/familylib/guards.py"'
# Forge Helper: driver questions go to the new tool (not "driver's license"), which opens the window
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import actions, rules, tools
for q in ['are my drivers up to date', 'is my BIOS up to date?', 'new firmware for my dock', 'where is the photo of my driver\'s license']:
    hit = rules.match(q); print(hit[0] if hit else '-')
print('drivers' in tools.TOOLS, actions.WINDOWS.get('autopilot'))" "$HL")"
check Q5 '[ "$(tr "\n" " " <<< "$ROUTES")" = "drivers drivers drivers find True forgeos-autopilot-gui " ] && grep -q "^def drivers(_arg):" "$HL/helperlib/looks.py" && head -n 2 "$SYS/usr/share/forgeos/helper/help/drivers-bios.md" | grep -qx "# Drivers & BIOS"'
fake forgeos-autopilot 'echo "Drivers: up to date (they update by themselves with ForgeOS)."; printf "DEVICES\t0\n"; exit 0'
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import looks
text, acts, level = looks.LOOK['drivers']('')
print(text); print(acts)" "$HL")"
check Q6 'grep -qx "Drivers: up to date (they update by themselves with ForgeOS)." <<< "$OUT" && grep -qx "\[(.open., .autopilot., .Open Drivers & BIOS.)\]" <<< "$OUT" && ! grep -q DEVICES <<< "$OUT"'
# BIOS maker pages: https only, one per line, every known maker; advice list has no unchecked entries yet
check Q7 '! grep -v "^#" "$SH/makers.txt" | grep -v "^[a-z-]* ~ [A-Za-z]* ~ https://[a-z.]*/[^ ]*$" | grep -q . && [ "$(grep -vc "^#" "$SH/makers.txt")" -ge 8 ] && ! grep -v "^#" "$SH/known-devices.txt" | grep -q .'
check Q8 'python3 -c "import ast,sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]" "$ENGINE" "$LIB"/*.py && [ "$(head -n 1 "$ENGINE")" = "#!/usr/bin/python3" ] && [ ! -e "$LIB/__pycache__" ] && grep -q "sys.dont_write_bytecode = True" "$ENGINE"'
check Q9 '(for f in "$ENGINE" "$GUI" "$FORGEOS_AP_SCREENS" "$LIB"/*.py "$A"/forgeos-autopilot.desktop "$U"/forgeos-autopilot.* "$SH"/*.txt "$SYS"/usr/share/forgeos/helper/help/drivers-bios.md "$ROOT"/tests/*autopilot*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  too big, CRLF, tab or no last newline: $f"; exit 1; }; done)'
check Q10 '(for t in test-autopilot test-autopilot-devices test-autopilot-boot test-autopilot-fw test-autopilot-bios test-autopilot-notes test-autopilot-gui test-autopilot-files; do grep -q "bash tests/$t.sh ." "$ROOT/.github/workflows/tests.yml" || exit 1; done)'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

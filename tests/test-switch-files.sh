#!/usr/bin/env bash
# Tests for Install & Switch (Job 13e), case H: the build files - run bits, the package, polkit rules, menu
# entries + autostart, the installer ISO workflow, Forge Helper's new tool + help card, the CI step,
# small LF-only files without tabs (Cline limit).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-switch-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/switch-fakes.sh
. "$ROOT/tests/switch-fakes.sh"
A="$SYS/usr/share/applications"; P="$SYS/usr/share/polkit-1/actions/org.forgeos.switch.policy"; ISO="$ROOT/.github/workflows/iso.yml"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"; HL="$SYS/usr/lib/forgeos-helper"

check H1 'grep -q "^chmod 0755 .* /usr/bin/forgeos-autopilot-gui /usr/bin/forgeos-switch /usr/bin/forgeos-switch-gui /usr/libexec/forgeos-switch-boot /usr/libexec/forgeos-switch-winsetup\( \|$\)" "$SETUP" && grep -q "^        - efibootmgr  *# Install & Switch" "$ROOT/recipes/common-modules.yml"'
POL="$(python3 -c "
import sys, xml.dom.minidom as m
d = m.parse(sys.argv[1])
for a in d.getElementsByTagName('action'):
    get = lambda t: a.getElementsByTagName(t)[0].firstChild.data
    path = [x.firstChild.data for x in a.getElementsByTagName('annotate')][0]
    print(a.getAttribute('id'), get('allow_active'), get('allow_any'), path)" "$P")"
check H2 'grep -qx "org.forgeos.switch.boot yes auth_admin /usr/libexec/forgeos-switch-boot" <<< "$POL" && grep -qx "org.forgeos.switch.winsetup auth_admin_keep auth_admin /usr/libexec/forgeos-switch-winsetup" <<< "$POL"'
check H3 'grep -qx "Exec=/usr/bin/forgeos-switch-gui" "$A/forgeos-switch.desktop" && grep -qx "Exec=/usr/bin/forgeos-switch-gui --windows" "$A/forgeos-restart-windows.desktop" && grep -qx "Exec=/usr/bin/forgeos-switch first-run" "$SYS/etc/xdg/autostart/forgeos-switch-firstrun.desktop" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A/forgeos-switch.desktop" "$A/forgeos-restart-windows.desktop" "$SYS/etc/xdg/autostart/forgeos-switch-firstrun.desktop"; }'
YML="$(python3 -c "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True) or d.get('on')
j = d['jobs']['iso']
w = [s for s in j['steps'] if str(s.get('uses', '')).startswith('jasonn3/build-container-installer')][0]['with']
up = [s for s in j['steps'] if str(s.get('uses', '')).startswith('actions/upload-artifact')][0]['with']
print('dispatch' if 'workflow_dispatch' in on else '-', on['push']['tags'][0], ' '.join(j['strategy']['matrix']['image']))
print(w['image_repo'], w['image_name'], w['image_tag'], w['variant'], w['version'], w['enrollment_password'])
print(up['if-no-files-found'], up['compression-level'], j['permissions']['contents'])" "$ISO" 2>&1)"
check H4 '[ "$(sed -n 1p <<< "$YML")" = "dispatch v* forgeos forgeos-nvidia" ] && [ "$(sed -n 2p <<< "$YML")" = "ghcr.io/lukianczyk-sketch \${{ matrix.image }} latest Kinoite 44 universalblue" ] && [ "$(sed -n 3p <<< "$YML")" = "error 0 read" ] && grep -q "uses: jasonn3/build-container-installer@v1.5.0$" "$ISO" && grep -q "secure_boot_key_url: https://github.com/ublue-os/akmods/raw/main/certs/public_key.der$" "$ISO"'
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import actions, rules, tools
for q in ['restart into windows', 'how do I get back to Windows 11', 'will this windows program run', 'is my bios up to date']:
    hit = rules.match(q); print(hit[0] if hit else '-')
print('switch_windows' in tools.TOOLS, actions.WINDOWS.get('switch'))" "$HL")"
check H5 '[ "$(tr "\n" " " <<< "$ROUTES")" = "switch_windows switch_windows will_it_run drivers True forgeos-switch-gui " ] && head -n 1 "$SYS/usr/share/forgeos/helper/help/windows-forgeos.md" | grep -qx "# Windows and ForgeOS on one PC"'
fake forgeos-switch 'printf "EFI\\tyes\\nWINDOWS\\tfound\\t0000\\n"'
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import looks
act = looks.LOOK['switch_windows']('')[1][0]; print(act[0], act[1], act[2])" "$HL")"
check H6 '[ "$OUT" = "open switch Open Windows & ForgeOS" ]'
check H7 '(for f in "$ENGINE" "$GUI" "$FORGEOS_SWITCH_BOOT" "$FORGEOS_SWITCH_WINSETUP" "$FORGEOS_SWITCH_SRC"/* "$A"/forgeos-switch.desktop "$A"/forgeos-restart-windows.desktop "$P" "$ISO" "$SYS"/usr/share/forgeos/helper/help/windows-forgeos.md "$ROOT"/tests/*switch*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  too big, CRLF, tab or no last newline: $f"; exit 1; }; done)'
check H8 '(for t in test-switch test-switch-win test-switch-gui test-switch-files; do grep -q "bash tests/$t.sh ." "$ROOT/.github/workflows/tests.yml" || exit 1; done)'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

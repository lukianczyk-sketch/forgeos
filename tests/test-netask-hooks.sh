#!/usr/bin/env bash
# Tests for Ask Before Connecting (Job 24), case G: the recipe (packages + the build script
# in the right order), OpenSnitch's protocol file, Forge Helper routing and buttons, the PC Report Card note, CI steps.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-netask-hooks.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
SYS="$ROOT/files/system"; LIB="$SYS/usr/lib/forgeos-netask/netlib"; SH="$SYS/usr/share/forgeos/netask"
HL="$SYS/usr/lib/forgeos-helper"; SETUP="$ROOT/files/scripts/forgeos-setup.sh"; INST="$ROOT/files/scripts/install-opensnitch.sh"
D="$SYS/usr/share/applications/forgeos-netask.desktop"; SVC="$SYS/usr/lib/systemd/system/forgeos-netask.service"
HELP="$SYS/usr/share/forgeos/helper/help/ask-before-connecting.md"; T=$'\t'
mkdir -p "$WORK/bin"; export PATH="$WORK/bin:$PATH" PYTHONDONTWRITEBYTECODE=1
EXE=("$SYS/usr/bin/forgeos-netask" "$SYS/usr/bin/forgeos-netask-gui" "$SYS/usr/libexec/forgeos-netask-service")
check G1 'M="$ROOT/recipes/common-modules.yml"; grep -q "^        - python3-grpcio " "$M" && grep -q "^        - python3-protobuf " "$M" && grep -q "^        - python3-grpcio-tools " "$M" && [ "$(grep -n "install-opensnitch.sh" "$M" | cut -d: -f1)" -lt "$(grep -n "      - forgeos-setup.sh" "$M" | cut -d: -f1)" ] && [ "$(grep -n "      - install-ollama.sh" "$M" | cut -d: -f1)" -lt "$(grep -n "install-opensnitch.sh" "$M" | cut -d: -f1)" ]'
# G2: the protocol file is OpenSnitch's (the fields we use have the right numbers); nothing sends anything away
check G2 'P="$SH/ui.proto"; grep -q "map<string, string> process_checksums = 13;" "$P" && grep -q "repeated StringInt process_tree = 14;" "$P" && grep -q "Operator operator = 9;" "$P" && grep -q "repeated Event events = 17;" "$P" && grep -q "rpc AskRule (Connection) returns (Rule) {}" "$P" && ! grep -rqE "urllib|http\.client|^import requests|\"(curl|wget)\"" "$LIB"'
# G3: Forge Helper: internet questions go here; Wi-Fi trouble, slowness and website blocking still go elsewhere
printf '#!/bin/bash\ncase "$1" in why) echo "Bottles: Blocked."; printf "WHY\\tflatpak:x\\tblock\\n" ;; report) echo "Ask Before Connecting is on." ;; esac\n' > "$WORK/bin/forgeos-netask"; chmod +x "$WORK/bin/forgeos-netask"
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import actions, looks2, rules, tools
for q in ['is something on my computer using the internet?', 'unblock Bottles', 'why cant Bottles connect', 'block steam from the internet',
          'my wifi is not working', 'why cant I connect to the internet', 'my internet is slow', 'someone on anydesk is in my pc']:
    hit = rules.match(q); print(hit[0] if hit else '-')
t = list(tools.TOOLS); print(t.index('net_access') == t.index('explain_error') + 1, actions.WINDOWS.get('netask'))
print(looks2.net_access('unblock Bottles')[1]); print(actions.check_action('net_allow', 'Bottles'), actions.do('net_allow', 'a;b')[0])" "$HL")"
check G3 '[ "$(sed -n 1,9p <<< "$ROUTES" | tr "\n" " ")" = "net_access net_access net_access net_access pc_question pc_question why_slow tech_support True forgeos-netask-gui " ] && sed -n 10p <<< "$ROUTES" | grep -qF "[('"'"'net_allow'"'"', '"'"'Bottles'"'"', '"'"'Allow Bottles to use the internet'"'"'), ('"'"'open'"'"', '"'"'netask'"'"'" && [ "$(sed -n 11p <<< "$ROUTES")" = "None 2" ] && grep -qF "\"net_access\": \"check which apps use the internet\"" "$SYS/usr/libexec/forgeos-helper-krunner" && [ "$(grep -c "\"tool\": \"net_access\"" "$SYS/usr/share/forgeos/helper/tests/more.jsonl")" = 3 ]'
# G4: PC Report Card: the Safety grade notes when Ask Before Connecting is off or not running
printf '#!/bin/bash\nprintf "SERVICE\\toff\\nLOCKDOWN\\toff\\n"\n' > "$WORK/bin/forgeos-netask"
S1="$(python3 -B -c "import sys; sys.path.insert(0, sys.argv[1]); from cardlib import safety; s = safety.safety(); print(s['why'], s['tool'])" "$SYS/usr/lib/forgeos-reportcard")"
check G4 '[ "$S1" = "Ask Before Connecting is off (new programs can use the internet without asking). netask" ] && grep -q "|locate|netask) cmd=(\"forgeos-\$1-gui\")" "$SYS/usr/bin/forgeos-reportcard-gui"'
check G5 '(for t in "" -kinds -more -answers -gui -safety -tricks -files -hooks; do grep -qx "          bash tests/test-netask$t.sh ." "$ROOT/.github/workflows/tests.yml" || exit 1; done)'

echo
if [ "$failures" -eq 0 ]; then echo "All Ask Before Connecting tests G passed."; else echo "$failures test(s) failed."; fi
exit "$((failures > 0))"

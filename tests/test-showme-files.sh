#!/usr/bin/env bash
# Tests for Show Me How (Job 22), case L: the files are all there and clean, the menu entry + shortcut, the
# KWin overlay talks to the same D-Bus name as the engine (and lets clicks through), Forge Helper routing
# (emergencies still win), the build script, the CI steps.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-showme-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/showme-fakes.sh
. "$ROOT/tests/showme-fakes.sh"
SYS="$ROOT/files/system"; LIB="$FORGEOS_SHOWME_LIB/showlib"; SH="$FORGEOS_SHOWME_SHARE"; HL="$FORGEOS_HELPER_LIB"
A="$SYS/usr/share/applications/forgeos-showme.desktop"; HELP="$SYS/usr/share/forgeos/helper/help/show-me-how.md"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"; QMLF="$SH/overlay.qml"

check L1 'grep -qx "chmod 0755 /usr/bin/forgeos-showme /usr/bin/forgeos-showme-gui" "$SETUP" && [ -x "$ENGINE" ] && [ -x "$GUI" ]'
check L2 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "$ENGINE" "$HL"/helperlib/*.py && [ "$(ls "$LIB" | tr "\n" " ")" = "__init__.py ai.py cli.py guides.py screen.py session.py show.py walk.py " ]'
check L3 '(for f in "$ENGINE" "$GUI" "$LIB"/*.py "$A" "$HELP" "$QMLF" "$SH"/guides/*.txt "$HL"/helperlib/*.py "$ROOT"/tests/*showme*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  not clean: $f"; exit 1; }; done)'
check L4 'grep -qx "Exec=/usr/bin/forgeos-showme-gui" "$A" && grep -qx "Name=Show Me How" "$A" && grep -qx "X-KDE-Shortcuts=Meta+Shift+H" "$A" && [ "$(grep -l "X-KDE-Shortcuts=Meta+Shift+H" "$SYS"/usr/share/applications/*.desktop | wc -l)" = 1 ] && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A"; }'
# L5: the overlay: clicks go through, the same D-Bus name/path/method as the engine, never a Window tied to KWin's
check L5 'grep -q "property bool outputOnly: true" "$QMLF" && grep -q "Qt.WindowTransparentForInput" "$QMLF" && grep -q "transientParent: null" "$QMLF" && grep -q "service: \"org.forgeos.ShowMe\"" "$QMLF" && grep -q "path: \"/ShowMe\"" "$QMLF" && grep -q "method: \"State\"" "$QMLF" && grep -q "^NAME = \"org.forgeos.ShowMe\"" "$LIB/__init__.py" && grep -q "^PATH = \"/ShowMe\"" "$LIB/__init__.py" && grep -q "w.caption === \"Show Me How\"" "$QMLF" && grep -q "^TITLE = \"Show Me How\"" "$LIB/session.py" && [ "$(grep -c "{" "$QMLF")" = "$(grep -c "}" "$QMLF")" ]'
# L6: Show Me How never clicks or types: no input tools anywhere in its code
check L6 '! grep -rqE "ydotool|xdotool|wtype|dotool|uinput|libinput|keyboard\.press|--type" "$LIB" "$ENGINE" "$GUI" "$QMLF"'
# L7: Forge Helper: "show me how" goes to Show Me How; emergencies, Undo, bigger text, calling the helper,
# slowness and the report card still win; help keeps working
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import rules, tools
for q in ['show me how to print', 'walk me through setting up email', 'where do i click to add a printer',
          'can you show me how to make the text bigger', 'show me how to call my daughter', 'show me how to fix my slow pc', 'show me how to get rid of anydesk someone is in my computer',
          'show me how to get my deleted photo back', 'how do I print', 'show me my pc report card',
          'show me how to check if this email is a scam', 'my laptop was stolen show me how to find it']:
    hit = rules.match(q); print(hit[0] if hit else '-')
t = list(tools.TOOLS); print(t.index('show_me') == t.index('report_card') + 1)" "$HL")"
check L7 '[ "$(tr "\n" " " <<< "$ROUTES")" = "show_me show_me show_me text_bigger family_call why_slow tech_support undo_open help_answer report_card scam_check find_my_pc True " ] && grep -qF "\"show_me\": \"show you on the screen where to click\"" "$SYS/usr/libexec/forgeos-helper-krunner" && [ "$(grep -c "\"show_me\"" "$SYS/usr/share/forgeos/helper/tests/tools-2.jsonl")" = 3 ]'
# L8: every help card a guide shows exists (the guide name = the help card name)
check L8 '(for g in "$SH"/guides/*.txt; do n="$(basename "$g" .txt)"; [ -f "$SYS/usr/share/forgeos/helper/help/$n.md" ] || { echo "  no help card for $n"; exit 1; }; done)'
check L9 '(for t in "" -walk -steps -ai -dbus -gui -real -files; do grep -qx "          bash tests/test-showme$t.sh ." "$ROOT/.github/workflows/tests.yml" || exit 1; done) && grep -q "poppler-utils python3-dbus python3-gi dbus$" "$ROOT/.github/workflows/tests.yml"'

echo
if [ "$failures" -eq 0 ]; then echo "All Show Me How tests L passed."; else echo "$failures test(s) failed."; fi
exit "$((failures > 0))"

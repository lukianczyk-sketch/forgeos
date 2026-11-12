#!/usr/bin/env bash
# Tests for Plain-English Errors (Job 23), case G: the files are all there and clean, the menu entries + the
# Meta+Shift+E shortcut, the watcher service turned on for everyone, Forge Helper routing (emergencies, Show Me
# How and the other PC problems still win), its fix buttons, the build script, the CI steps.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-errors-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/errors-fakes.sh
. "$ROOT/tests/errors-fakes.sh"
SYS="$ROOT/files/system"; LIB="$FORGEOS_ERRORS_LIB/errlib"; SH="$FORGEOS_ERRORS_SHARE"; HL="$FORGEOS_HELPER_LIB"
A="$SYS/usr/share/applications/forgeos-errors.desktop"; B="$SYS/usr/share/applications/forgeos-errors-history.desktop"
HELP="$SYS/usr/share/forgeos/helper/help/plain-english-errors.md"; SVC="$SYS/usr/lib/systemd/user/forgeos-errors-watch.service"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"

check G1 'grep -qx "chmod 0755 /usr/bin/forgeos-errors /usr/bin/forgeos-errors-gui" "$SETUP" && grep -qx "systemctl --global enable forgeos-errors-watch.service" "$SETUP" && [ -x "$ENGINE" ] && [ -x "$GUI" ]'
check G2 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "$ENGINE" && [ "$(ls "$LIB" | tr "\n" " ")" = "__init__.py ai.py cli.py explain.py fixes.py history.py library.py scam.py system.py watch.py " ]'
check G3 '(for f in "$ENGINE" "$GUI" "$LIB"/*.py "$A" "$B" "$HELP" "$SVC" "$SH"/library/*.txt "$HL"/helperlib/*.py "$ROOT"/tests/*errors*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  not clean: $f"; exit 1; }; done)'
check G4 'grep -qx "Exec=/usr/bin/forgeos-errors-gui --explain" "$A" && grep -qx "Name=Explain This Error" "$A" && grep -qx "X-KDE-Shortcuts=Meta+Shift+E" "$A" && [ "$(grep -lx "X-KDE-Shortcuts=Meta+Shift+E" "$SYS"/usr/share/applications/*.desktop | wc -l)" = 1 ] && grep -qx "Exec=/usr/bin/forgeos-errors-gui" "$B" && grep -qx "Name=What Went Wrong" "$B" && { ! command -v desktop-file-validate >/dev/null || { desktop-file-validate "$A" && desktop-file-validate "$B"; }; }'
check G5 'grep -qx "ExecStart=/usr/bin/forgeos-errors watch" "$SVC" && grep -qx "WantedBy=graphical-session.target" "$SVC" && grep -qx "PartOf=graphical-session.target" "$SVC"'
# G6: nothing in it sends anything anywhere or clicks for you; the AI is reached only through Forge Helper's local link
check G6 '! grep -rqE "urllib|requests|socket|http\.client|curl|wget|ydotool|xdotool|wtype" "$LIB" "$ENGINE" "$GUI" && ! grep -rqE "empty-trash|rm -rf|gio trash" "$LIB/fixes.py"'
# G7: Forge Helper: errors go to Plain-English Errors; scams, strangers, Show Me How, slowness and help still win
ROUTES="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import rules, tools, actions
for q in ['what does this error mean', 'I keep getting an error MSVCP140.dll was not found', 'ERR_NAME_NOT_RESOLVED',
          'what does error code 0x80070005 mean', 'a pop up says error virus call this number', 'show me how to fix this error',
          'someone on anydesk says my pc has errors', 'my pc is slow and shows errors', 'how do I print', 'my wifi is not working',
          'my wifi is not working and shows an error', 'word shows an error message']:
    hit = rules.match(q); print(hit[0] if hit else '-')
t = list(tools.TOOLS); print(t.index('explain_error') == t.index('show_me') + 1, actions.WINDOWS.get('errors'))" "$HL")"
check G7 '[ "$(tr "\n" " " <<< "$ROUTES")" = "explain_error explain_error explain_error explain_error scam_check show_me tech_support why_slow help_answer pc_question pc_question explain_error True forgeos-errors-gui " ] && grep -qF "\"explain_error\": \"explain this error in plain words\"" "$SYS/usr/libexec/forgeos-helper-krunner" && [ "$(grep -c "\"tool\": \"explain_error\"" "$SYS/usr/share/forgeos/helper/tests/more.jsonl")" = 3 ]'
# G8: Forge Helper's answer: the card's words, and only fix buttons the helper itself knows
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import looks2
for q in ['ERR_INTERNET_DISCONNECTED', 'Printer HP stopped: Filter failed', 'zzzz']:
    text, acts, level = looks2.explain_error(q); print(text.splitlines()[0], acts)" "$HL")"
check G8 'grep -qx "The internet is not connected \[('"'"'pc_fix'"'"', '"'"'restart-internet'"'"', '"'"'Turn the internet connection off and on again'"'"'), ('"'"'showme'"'"', '"'"'wifi'"'"', '"'"'Show me where to click'"'"'), ('"'"'open'"'"', '"'"'errors'"'"', '"'"'Open What Went Wrong'"'"')\]" <<< "$OUT" && grep -q "^The printer could not understand the print job \[('"'"'showme'"'"', '"'"'add-printer'"'"'" <<< "$OUT" && grep -q "^Copy the error.s words and paste them here" <<< "$OUT"'
check G9 'head -n 1 "$HELP" | grep -qx "# Plain-English Errors: what an error message means and what to do" && (for t in "" -ai -watch -fix -gui -dbus -files; do grep -qx "          bash tests/test-errors$t.sh ." "$ROOT/.github/workflows/tests.yml" || exit 1; done) && ER check > /dev/null'

echo
if [ "$failures" -eq 0 ]; then echo "All Plain-English Errors tests G passed."; else echo "$failures test(s) failed."; fi
exit "$((failures > 0))"

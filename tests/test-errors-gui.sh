#!/usr/bin/env bash
# Tests for Plain-English Errors (Job 23), case E: the window. A card shows the plain words with Fix it /
# Show me where to click / Close; Fix it runs that one checked fix and marks it fixed; a serious card is a
# warning; What Went Wrong lists the last 30 days in plain words; Meta+Shift+E explains the screen.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-errors-gui.sh <repo-root>
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
export FORGEOS_ERRORS_ENGINE="$ENGINE"
G() { bash "$GUI" "$@"; }
dialog() { grep "^kdialog" "$WORK/calls.log" | sed -n "${1:-1}p"; }

# E1: a card with a fix and a guide: the plain words, Fix it: <label> / Show me where to click / Close
fresh; ER explain "ERR_INTERNET_DISCONNECTED" > /dev/null; echo 2 > "$WORK/kdialog-code"
G --card web-no-internet
check E1 'grep -q -- "--yesnocancel The internet is not connected" <<< "$(dialog)" && grep -qx "Is it serious? Needs a look soon." <<< "$(calls)" && grep -q -- " --yes-label Fix it: Turn the internet connection off and on again --no-label Show me where to click --cancel-label Close$" <<< "$(calls)"'
# E2: no fix on that card (it has only a guide) -> Show me / Close; Show me starts the walk
fresh; ER explain "The Wi-Fi network could not be found" > /dev/null; echo 0 > "$WORK/kdialog-code"
G --card wifi-not-found
check E2 'grep -q -- "--yesno The Wi-Fi network is out of reach" <<< "$(dialog)" && grep -q -- " --yes-label Show me where to click --no-label Close$" <<< "$(calls)" && waitfor "^forgeos-showme guide wifi"'
# E3: Fix it -> that one fix runs, a short note shows, and the error is marked fixed
fresh; ER explain "ERR_INTERNET_DISCONNECTED" > /dev/null
G --card web-no-internet
check E3 'waitfor "^forgeos-askpc fix restart-internet" && grep -q "fixed" <<< "$(ER recent | grep web-no-internet)" && waitfor "passivepopup Done: restart-internet"'
# E4: Show me (the second button) starts the guide; Close does nothing
fresh; ER explain "ERR_INTERNET_DISCONNECTED" > /dev/null; echo 1 > "$WORK/kdialog-code"
G --card web-no-internet
echo 2 > "$WORK/kdialog-code"; G --card web-no-internet
check E4 'waitfor "^forgeos-showme guide wifi" && ! grep -q "^forgeos-askpc" "$WORK/calls.log" && [ "$(grep -c "^forgeos-showme" "$WORK/calls.log")" = 1 ]'
# E5: a serious card (a scam) is a warning with its one fix; a card with nothing to do is a plain message
fresh; ER explain "Your PC is infected. Call 1-888-555-0199 now" > /dev/null; echo 2 > "$WORK/kdialog-code"
G --card "$(grep -o "scam-fake-error/[0-9a-f]*" "$HIST" | head -n 1)"
ER explain "404 Not Found" > /dev/null; G --card web-404
check E5 'grep -q -- "--warningyesno This is a scam, not a real error" <<< "$(dialog 1)" && grep -q -- " --yes-label Fix it: Close all web browsers now (the scary page too) --no-label Close$" <<< "$(calls)" && grep -q -- "--msgbox That web page does not exist" <<< "$(dialog 2)"'
# E6: What Went Wrong: newest first, plain levels, explain-now first; picking one opens its card
fresh; ER explain "ERR_TOO_MANY_REDIRECTS" > /dev/null; ER explain "I/O error, dev sda" > /dev/null; ER fixed web-redirects
echo drive-io-error > "$WORK/say/pick"; echo 0 > "$WORK/kdialog-code"
G
check E6 'grep -q -- "--menu What went wrong on this PC in the last 30 days" <<< "$(dialog 1)" && grep -q " explain Explain an error on my screen now (Meta+Shift+E) drive-io-error .* - The drive had trouble reading or writing (SERIOUS) web-redirects .* - The website is going in circles (fixed)$" <<< "$(calls)" && grep -q -- "--warningyesno The drive had trouble" <<< "$(dialog 2)" && waitfor "^forgeos-drivehealth-gui"'
# E7: Meta+Shift+E: the error on the screen gets its card; nothing found = a plain message
fresh; screen "Printer HP stopped: Filter failed@100,100"; echo 2 > "$WORK/kdialog-code"
G --explain
rm -f "$WORK/screen.tsv"; G --explain
check E7 'grep -q -- "--yesnocancel The printer could not understand the print job" <<< "$(dialog 1)" && grep -q -- "--msgbox I could not read the screen." <<< "$(dialog 2)"'
# E8: an empty history says so; wrong use = 3; no kdialog = 3
fresh; rm -f "$WORK/say/pick"; G
G --card > /dev/null 2>&1; A=$?; G --bogus > /dev/null 2>&1; B=$?
PATH="/usr/bin:/bin" FORGEOS_ERRORS_ENGINE=true bash "$GUI" > /dev/null 2>&1; C=$?
if command -v kdialog > /dev/null 2>&1; then C=3; fi
check E8 'grep -q " none Nothing went wrong in the last 30 days.$" <<< "$(calls)" && [ "$A$B$C" = 333 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Plain-English Errors tests E passed."; else echo "$failures test(s) failed."; fi
exit "$((failures > 0))"

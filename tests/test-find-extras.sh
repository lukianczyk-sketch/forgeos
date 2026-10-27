#!/usr/bin/env bash
# Tests for Find Anything (Job 11), cases O-T: the window, menu entry, background update, build files.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-find-extras.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/find-fakes.sh
. "$ROOT/tests/find-fakes.sh"
GUI="$ROOT/files/system/usr/bin/forgeos-find-gui"
U="$ROOT/files/system/usr/lib/systemd/user"
D="$ROOT/files/system/usr/share/applications/forgeos-find.desktop"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"
C="$ROOT/recipes/common-modules.yml"
LIB="$ROOT/files/system/usr/lib/forgeos-find/findlib"

# O: empty list: the window offers to build it, then shows what was found; "Open it" opens the file
printf 'walmart receipt\n' > "$WORK/input"
printf '1\nopen\n' > "$WORK/menu"
: > "$WORK/calls.log"
FAKE_YES=0 bash "$GUI"; RC=$?
check O1 '[ "$RC" -eq 0 ] && grep -q "^kdialog .*--yesno Find Anything has not made its search list yet" "$WORK/calls.log" && [ -s "$DB" ]'
check O2 'grep -q "^xdg-open $H/Pictures/receipt.jpg$" "$WORK/calls.log" && grep -q "^receipt.jpg  -  $H/Pictures" "$WORK/shown" && grep -qx "again" "$WORK/shown"'

# P: "Show it in its folder" opens Dolphin on that file; "Back" goes back to the results
: > "$WORK/calls.log"; : > "$WORK/shown"
printf 'shopping list\n' > "$WORK/input"
printf '1\nback\n1\nfolder\n' > "$WORK/menu"
bash "$GUI"
check P1 'grep -q "^dolphin --select $H/Documents/list.txt$" "$WORK/calls.log" && ! grep -q "^xdg-open" "$WORK/calls.log"'
check P2 'grep -q "^Looking for: shopping list" "$WORK/shown" && [ "$(grep -c "^Pick a file:$" "$WORK/shown")" -ge 2 ]'

# Q: nothing found, a new search, an empty question, and saying "Not now" to building the list
: > "$WORK/shown"
printf 'purple walrus\n   \nshopping list\n' > "$WORK/input"
printf 'again\n' > "$WORK/menu"
bash "$GUI"
check Q1 'grep -q "^Nothing found for: purple walrus" "$WORK/shown" && grep -q "^Please type what you are looking for.$" "$WORK/shown" && grep -q "^Looking for: shopping list" "$WORK/shown"'
mv "$DB" "$WORK/db-saved"
: > "$WORK/calls.log"
printf 'shopping list\n' > "$WORK/input"
FAKE_YES=1 bash "$GUI"
check Q2 'grep -q "^kdialog .*--yesno" "$WORK/calls.log" && [ "$(python3 "$FIND" status | head -n 1)" = "Files in the search list: 0" ]'
mv "$WORK/db-saved" "$DB"
# Without kdialog the window says so and stops.
mkdir -p "$WORK/nobin"
PATH="$WORK/nobin" "$(command -v bash)" "$GUI" 2>/dev/null; RC=$?
check Q3 '[ "$RC" -eq 3 ]'

# R: the menu entry
if command -v desktop-file-validate >/dev/null 2>&1; then
  check R1 'desktop-file-validate "$D"'
else
  echo "SKIP R1 (desktop-file-validate is not installed)"
fi
check R2 'grep -qx "Name=Find Anything" "$D" && grep -qx "Exec=/usr/bin/forgeos-find-gui" "$D" && grep -qx "Categories=Utility;FileTools;" "$D" && grep -q "^Keywords=.*ocr;" "$D"'

# S: the background update is gentle: lowest priority, idle disk use, not on battery, hourly
check S1 'grep -qx "Type=oneshot" "$U/forgeos-find-index.service" && grep -qx "ExecStart=/usr/bin/forgeos-find index --quiet" "$U/forgeos-find-index.service"'
check S2 'grep -qx "Nice=19" "$U/forgeos-find-index.service" && grep -qx "IOSchedulingClass=idle" "$U/forgeos-find-index.service" && grep -qx "CPUSchedulingPolicy=idle" "$U/forgeos-find-index.service" && grep -qx "ConditionACPower=true" "$U/forgeos-find-index.service"'
check S3 'grep -qx "OnStartupSec=10min" "$U/forgeos-find-index.timer" && grep -qx "OnUnitActiveSec=1h" "$U/forgeos-find-index.timer" && grep -qx "WantedBy=timers.target" "$U/forgeos-find-index.timer"'

# T: build files: run bits, timer on for every user, the free packages, every file small and LF only
check T1 'grep -q "^chmod 0755 .* /usr/bin/forgeos-find /usr/bin/forgeos-find-gui\( \|$\)" "$SETUP" && grep -qx "systemctl --global enable forgeos-find-index.timer" "$SETUP"'
check T2 '(for p in tesseract tesseract-langpack-eng poppler-utils python3; do grep -q "^        - $p  *# Find Anything (Job 11)" "$C" || exit 1; done)'
check T3 'python3 -c "import ast,sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]" "$FIND" "$LIB"/*.py'
check T4 '(for f in "$FIND" "$GUI" "$LIB"/*.py "$U"/forgeos-find-index.* "$D" "$ROOT"/tests/*find*.sh; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  too big, CRLF or no last newline: $f"; exit 1; }; done)'
check T5 '[ ! -e "$LIB/__pycache__" ] && head -n 1 "$FIND" | grep -qx "#!/usr/bin/python3"'
# T6: with the free PDF/OCR tools missing, files are still found by name and status says what is missing
PATH="$WORK/nobin" "$(command -v python3)" "$FIND" index --full --quiet
OUT="$(F status)"
check T6 'grep -q "Note: .*PDF text needs poppler-utils.*photo text needs tesseract" <<< "$OUT" && [ "$(first "$(F search --kind photo receipt)")" = "$H/Pictures/receipt.jpg" ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Find Anything tests (O-T) passed."; else echo "$failures Find Anything test(s) failed."; exit 1; fi

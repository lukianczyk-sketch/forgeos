#!/usr/bin/env bash
# Tests for Always-On Guard (Job 13b), case I: Email Guard checks one email - scam words, the private
# AI's second look, a virus attachment, a zip with a program, a web-page attachment, links in HTML.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-guard-mail.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'stop_clamd; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/guard-fakes.sh
. "$ROOT/tests/guard-fakes.sh"
command -v clamscan >/dev/null 2>&1 || { echo "FAIL clamscan is needed (apt-get install clamav)"; exit 1; }
M="$WORK/m"; mkdir -p "$M"

# I: one email at a time (check-mail)
mkmail "Bank <alerts@bank-secure.example>" "Your account is locked" "SCAMWORD buy gift cards now" > "$M/1.eml"
OUT="$(G check-mail "$M/1.eml")"; RC=$?; EID="$(tail -n 1 "$EV" | cut -f 7)"
check I1 '[ "$RC$OUT" = 2SCAM ] && grep -q "${T}scam${T}email${T}alerts@bank-secure.example${T}Your account is locked${T}test${T}" "$EV" && grep -q "^From: alerts@bank-secure.example" <<< "$(G why "$EID")" && grep -q "It asks for gift cards" <<< "$(G why "$EID")"'
calls_wait "^notify-send .*Scam warning"
check I2 'grep -q "^notify-send --app-name=Always-On Guard --icon=security-high --urgency=critical Scam warning The email from alerts@bank-secure.example about \"Your account is locked\" looks like a scam. Don.t click its links or open its files. --action=why=Show why --wait$" "$WORK/calls.log"'
mkmail "Pal <pal@example.com>" "Lunch" "CAREWORD AI-SCAM" > "$M/2.eml"; mkmail "Pal <pal@example.com>" "Dinner" "CAREWORD only" > "$M/3.eml"
O2="$(G check-mail "$M/2.eml")"; O3="$(G check-mail "$M/3.eml")"; R3=$?
check I3 '[ "$O2" = SCAM ] && [ "$O3$R3" = FINE0 ] && grep -c "^forgeos-scamshield check" "$WORK/calls.log" | grep -qx 5 && [ "$(grep -c "^forgeos-scamshield check --no-ai" "$WORK/calls.log")" = 3 ]'
virus "$WORK/v.bin"; mkmail "Friend <f@example.com>" "Photos" "see attached" "photos.jpg" "$WORK/v.bin" > "$M/4.eml"
OUT="$(G check-mail "$M/4.eml")"; EID="$(tail -n 1 "$EV" | cut -f 7)"
check I4 '[ "$OUT" = SCAM ] && grep -q "The attachment photos.jpg has a virus: ForgeOS.Test.Eicar.UNOFFICIAL. Don.t open it." <<< "$(G why "$EID")" && [ -z "$(ls "$WORK/state/forgeos/guard" | grep "^\.mail-")" ]'
if start_clamd; then  # the always-ready checker gets the attachment streamed in (never saved to disk)
  : > "$WORK/calls.log"; G check-mail "$M/4.eml" >/dev/null; EID="$(tail -n 1 "$EV" | cut -f 7)"; stop_clamd
  check I4b 'grep -q "has a virus: ForgeOS.Test.Eicar.UNOFFICIAL" <<< "$(G why "$EID")" && grep -q "^clamdscan .*--stream --no-summary -$" "$WORK/calls.log" && ! grep -q "^clamscan" "$WORK/calls.log"'
else
  echo "SKIP I4b (clamd + clamdscan are not installed)"
fi
( cd "$WORK" && echo MZ > setup.exe && python3 -c "import zipfile; z=zipfile.ZipFile('z.zip','w'); z.write('setup.exe'); z.close()" )
mkmail "Shop <s@example.com>" "Invoice" "your invoice" "invoice.zip" "$WORK/z.zip" > "$M/5.eml"
echo "<form>password</form>" > "$WORK/login.html"; mkmail "IT <it@example.com>" "Login" "log in" "login.html" "$WORK/login.html" > "$M/6.eml"
O5="$(G check-mail "$M/5.eml")"; E5="$(tail -n 1 "$EV" | cut -f 7)"; O6="$(G check-mail "$M/6.eml")"; E6="$(tail -n 1 "$EV" | cut -f 7)"
check I5 '[ "$O5$O6" = CAREFULCAREFUL ] && grep -q "invoice.zip is a zip file with a program inside (setup.exe)" <<< "$(G why "$E5")" && grep -q "login.html is a web page - fake login pages come this way" <<< "$(G why "$E6")"'
python3 -B - "$M/7.eml" <<'PY'
import sys
from email.message import EmailMessage
m = EmailMessage(); m["From"] = "x@example.com"; m["Subject"] = "Hi"
m.set_content("plain part")
m.add_alternative('<p>Click <a href="http://evil-login.example/verify">here</a></p><script>alert(1)</script>', subtype="html")
open(sys.argv[1], "w").write(m.as_string())
PY
G check-mail "$M/7.eml" >/dev/null
check I6 'grep -q "http://evil-login.example/verify" "$WORK/last-checked.txt" && ! grep -q "alert(1)" "$WORK/last-checked.txt" && grep -qx "Subject: Hi" "$WORK/last-checked.txt"'

# Pop-ups held back within a minute are counted into the next one
: > "$WORK/calls.log"
PYTHONPATH="$FORGEOS_GUARD_LIB" python3 -B -c "
from guardlib import alerts
alerts.QUIET = 100
r = [alerts.email(2, 'a@x', 'one'), alerts.email(1, 'b@x', 'two'), alerts.email(2, 'c@x', 'three')]
alerts.QUIET = 0
r.append(alerts.email(1, 'd@x', 'four'))
assert r == [True, False, False, True], r"
calls_wait "^notify-send" 2
check I7 '[ "$(grep -c "^notify-send" "$WORK/calls.log")" = 2 ] && grep -q "^notify-send .*--urgency=normal Be careful with this email The email from d@x about \"four\" has warning signs. .* (+2 more warnings - see Always-On Guard)" "$WORK/calls.log"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

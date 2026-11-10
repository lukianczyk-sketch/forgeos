#!/usr/bin/env bash
# Tests for Show Me How (Job 22), cases A-C: the 24 guides (list, self-check, broken guides found), which guide
# fits a question, and finding words on a pretend screen (exact, nearly, our own panel skipped, smudges skipped).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-showme.sh <repo-root>
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
PY() { python3 -B -c "import sys; sys.path.insert(0, '$FORGEOS_SHOWME_LIB'); $1"; }

# A1-A2: 24 guides, the most used first; every one passes the self-check
OUT="$(SM list)"; CODE=$?
check A1 '[ "$CODE" = 0 ] && [ "$(grep -c "^GUIDE${T}" <<< "$OUT")" = 24 ] && [ "$(head -n 1 <<< "$OUT")" = "GUIDE${T}print${T}Print something" ] && [ "$(sed -n 2p <<< "$OUT" | cut -f 2)" = wifi ]'
OUT="$(SM check all)"; CODE=$?
check A2 '[ "$CODE" = 0 ] && [ "$(grep -c "^OK " <<< "$OUT")" = 24 ] && ! grep -q "^BAD" <<< "$OUT"'
# A3: a broken guide is found (bad step, unknown settings page, unknown place, no words line, too long)
mkdir -p "$WORK/share/guides"
printf '# Broken\nopen: settings kcm_nothing\nstep: place moon | Look up.\nstep: jump | %s\n' "$(printf 'x%.0s' {1..95})" > "$WORK/share/guides/broken.txt"
printf '# No bar\nwords: x\nstep: word Hello\n' > "$WORK/share/guides/nobar.txt"
OUT="$(FORGEOS_SHOWME_SHARE="$WORK/share" SM check all)"; CODE=$?
check A3 '[ "$CODE" = 1 ] && grep -q "^BAD broken: unknown settings page: kcm_nothing; unknown place: moon; unknown step kind: jump; say it shorter" <<< "$OUT" && grep -q "the words: line is missing" <<< "$OUT" && grep -q "^BAD nobar: a step needs" <<< "$OUT"'
# A4-A5: an unknown guide; the steps in writing
SM guide nothing >/dev/null 2>&1; CODE=$?
SM guide ../../etc/passwd >/dev/null 2>&1; CODE2=$?
OUT="$(SM written print)"
check A4 '[ "$CODE" = 1 ] && [ "$CODE2" = 1 ] && [ ! -e "$WORK/calls.log" ]'
check A5 '[ "$OUT" = "Print something
1. Open what you want to print, then press Ctrl and P together.
2. Pick your printer and how many copies, then click Print." ]'

# B1: which guide fits the question
ok=1
while IFS="|" read -r q want; do
  got="$(SM find "$q" | cut -f 2)"
  [ "$got" = "$want" ] || { echo "  \"$q\": got \"$got\", want \"$want\""; ok=0; }
done <<'EOF'
how do I print|print
how do i add a printer|add-printer
show me how to connect to the internet|wifi
the letters are too small, make them bigger|bigger-text
how do I turn up the volume|sound
set up my email account|email
take a picture of the screen|screenshot
connect my bluetooth headphones|bluetooth
change my login password|user-password
how do I get rid of an app|uninstall-app
restart into windows|windows-forgeos
make a zoom call with the grandkids|video-call
EOF
check B1 '[ "$ok" = 1 ]'
# B2-B3: nothing fits; wrong use
SM find what is the meaning of life >/dev/null; CODE=$?
SM >/dev/null 2>&1; CODE2=$?
SM check >/dev/null 2>&1; CODE3=$?
check B2 '[ "$CODE" = 1 ]'
check B3 '[ "$CODE2" = 3 ] && [ "$CODE3" = 3 ]'

# C1: exact words -> parts of the screen (0 to 1); the box covers both words
screen 0 "Add Printer@960,540" "Cancel@100,1000"
touch "$WORK/x"; OUT="$(PY "from showlib import screen; s = screen.read('$WORK/x'); print(s[0], s[1], [round(n, 4) for n in screen.find(s, 'Add Printer')])")"
check C1 '[ "$OUT" = "1920 1080 [0.5, 0.5, 0.051, 0.0148]" ]'
# C2: OCR mistakes still count ("Add Prlnter", look-alike letters "Caneel", "Fi1e"); other short words must be exact
screen 0 "Add Prlnter...@200,300" "Fail@50,50" "OK@60,60" "Caneel@70,70" "Fi1e@80,80"
OUT="$(PY "from showlib import screen; s = screen.read('$WORK/x'); print(bool(screen.find(s, 'Add Printer')), screen.find(s, 'Fat'), bool(screen.find(s, 'ok')), bool(screen.find(s, 'Cancel')), bool(screen.find(s, 'File')))")"
check C2 '[ "$OUT" = "True None True True True" ]'
# C3: our own label/panel is skipped; smudges (low sureness) are skipped; exact beats nearly; whole line beats part
screen 0 "Click Add Printer.@900,100" "Add Printer@300,700" "Print@10,10,5" "Prints@500,500" "Print@800,800" "Print this page@20,900"
OUT="$(PY "from showlib import screen; s = screen.read('$WORK/x'); a = screen.find(s, 'Add Printer', [[0.4, 0.05, 0.3, 0.1]]); b = screen.find(s, 'Print'); print(round(a[0], 3), round(b[0], 3), round(b[1], 3))")"
check C3 '[ "$OUT" = "0.156 0.417 0.741" ]'
# C4: the words the AI may choose from: one per line, no repeats, no lines without letters
screen 0 "Wi-Fi@10,10" "wi-fi@20,20" "****@30,30" "Connect@40,40"
OUT="$(PY "from showlib import screen; print('|'.join(screen.visible(screen.read('$WORK/x'))))")"
check C4 '[ "$OUT" = "Wi-Fi|Connect" ]'
# C5: no picture = nothing found (never a guess)
OUT="$(PY "from showlib import screen; print(screen.find(None, 'OK'), screen.read('$WORK/missing'))")"
check C5 '[ "$OUT" = "None None" ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Show Me How tests A-C passed."; else echo "$failures Show Me How test(s) failed."; exit 1; fi

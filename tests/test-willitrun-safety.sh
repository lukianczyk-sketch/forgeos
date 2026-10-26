#!/usr/bin/env bash
# Tests for Will It Run? (Job 10), case Q: the safety check before any answer (virus check, fake double
# endings, the website the file came from, cracked programs).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-willitrun-safety.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/willitrun-fakes.sh
. "$ROOT/tests/willitrun-fakes.sh"
DL="$HOME/Downloads"
run() { : > "$WORK/calls.log"; OUT="$(bash "$WR" check --no-ai "$@" 2>&1)"; RC=$?; }
echo com.usebottles.bottles >> "$WORK/installed"
mkpe "$DL/setup.exe" 8664 2 20b 0 22

# Q1: the virus check finds something: No, and no way to run it is offered
FAKE_VIRUS="Win.Test.EICAR_HDB-1" run "$DL/setup.exe"
check Q1 '[ "$RC" -eq 2 ] && grep -q "virus check found something bad" <<< "$OUT" && grep -q "Found: Win.Test.EICAR_HDB-1." <<< "$OUT" && ! grep -q "^WAY:" <<< "$OUT"'

# Q2: a clean file: the answer first, then the virus check note, then the verdict
run "$DL/setup.exe"
check Q2 '[ "$RC" -eq 0 ] && [ "$(head -n 1 <<< "$OUT")" = "Yes, it should run in Bottles." ] && [ "$(tail -n 3 <<< "$OUT" | head -n 1)" = "Virus check: nothing bad found." ] && grep -q "^clamscan .*--infected .*$DL/setup.exe" "$WORK/calls.log"'
FAKE_SCAN_RC=2 run "$DL/setup.exe"
check Q3 '[ "$RC" -eq 0 ] && grep -q "Virus check: could not finish" <<< "$OUT"'

# Q4: programs dressed up as documents, pictures or songs are always a No (even with a known name)
cp "$DL/setup.exe" "$DL/Invoice March.PDF.exe"
run "$DL/Invoice March.PDF.exe"
check Q4 '[ "$RC" -eq 2 ] && grep -q "pretending to be something else" <<< "$OUT" && ! grep -q "^WAY:" <<< "$OUT"'
cp "$DL/setup.exe" "$DL/Spotify song.mp3      .scr"
run "$DL/Spotify song.mp3      .scr"
check Q5 '[ "$RC" -eq 2 ] && grep -q "pretending" <<< "$OUT" && ! grep -q "own Linux version" <<< "$OUT"'
cp "$DL/setup.exe" "$DL/Bank statement      .exe"
run "$DL/Bank statement      .exe"
check Q5b '[ "$RC" -eq 2 ] && grep -q "pretending" <<< "$OUT"'

# Q6: the website the file came from: a known scam website is a No, others are shown
FAKE_ORIGIN="https://cdn.evil-downloads.com:8080/get/setup.exe" run "$DL/setup.exe"
check Q6 '[ "$RC" -eq 2 ] && grep -q "known scam or virus website (cdn.evil-downloads.com)" <<< "$OUT"'
FAKE_ORIGIN="https://www.GIMP.org/downloads/" run "$DL/setup.exe"
check Q7 '[ "$RC" -eq 0 ] && grep -q "Downloaded from: gimp.org." <<< "$OUT"'

# Q8: cracked programs get a warning; a name typed in is never scanned
cp "$DL/setup.exe" "$DL/Photoshop 2026 Crack + Keygen.exe"
run "$DL/Photoshop 2026 Crack + Keygen.exe"
check Q8 'grep -q "cracked or pirated" <<< "$OUT" && grep -q "Krita" <<< "$OUT"'
run "Spotify"
check Q9 '[ "$RC" -eq 0 ] && ! grep -q clamscan "$WORK/calls.log" && ! grep -q "Virus check" <<< "$OUT"'

echo
if [ "$failures" -eq 0 ]; then echo "ALL WILL IT RUN? TESTS PASSED (Q)"; else echo "$failures WILL IT RUN? TEST(S) FAILED (Q)"; fi
[ "$failures" -eq 0 ]

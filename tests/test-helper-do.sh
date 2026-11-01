#!/usr/bin/env bash
# Tests for Forge Helper (Job 13c), cases M-P: actions only with --yes and only from the fixed list,
# memory ("remember that..."), thumbs up / down.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-helper-do.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/helper-fakes.sh
. "$ROOT/tests/helper-fakes.sh"

# M: no --yes = nothing happens; only known actions with checked arguments run
OUT="$(F run panic 2>&1)"; RC=$?
check M1 '[ "$RC" -eq 3 ] && grep -q "need the user.s Yes" <<< "$OUT" && ! grep -q forgeos-panic "$WORK/calls.log" 2>/dev/null'
OUT="$(F run panic --yes)"; RC=$?
check M2 '[ "$RC" -eq 0 ] && grep -qx "forgeos-panic on" "$WORK/calls.log"'
OUT="$(F run rm-everything / --yes)"; RC=$?
check M3 '[ "$RC" -eq 2 ] && grep -q "does not know how" <<< "$OUT"'
OUT="$(F run pc_fix "format-disk" --yes)"; RC=$?
check M4 '[ "$RC" -eq 2 ] && ! grep -q "forgeos-askpc fix " "$WORK/calls.log"'
OUT="$(F run pc_fix "close-busy-app hog" --yes)"; RC=$?
check M5 '[ "$RC" -eq 0 ] && grep -qx "forgeos-askpc fix close-busy-app hog" "$WORK/calls.log"'
echo 1 > "$WORK/fix-rc"
F run pc_fix restart-internet --yes >/dev/null; RC=$?
check M6 '[ "$RC" -eq 1 ]'
# The fix list is read from Ask Your PC itself: a fix it does not have is refused.
sed -i 's/ open-backup"/"/' "$WORK/libexec/forgeos-askpc-fixes"
F run pc_fix open-backup --yes >/dev/null; RC=$?
check M7 '[ "$RC" -eq 2 ]'

# N: sizes, windows, files and downloads are checked
F run text_size huge --yes >/dev/null; A=$?
F run text_size bigger --yes >/dev/null; B=$?
F run family_on big --yes >/dev/null; C=$?
check N1 '[ "$A" -eq 2 ] && [ "$B" -eq 0 ] && [ "$C" -eq 0 ] && grep -qx "forgeos-family size bigger" "$WORK/calls.log" && grep -qx "forgeos-family on --size big" "$WORK/calls.log"'
F run open bash --yes >/dev/null; A=$?
F run open guard --yes >/dev/null; B=$?
sleep 0.3
check N2 '[ "$A" -eq 2 ] && [ "$B" -eq 0 ] && grep -qx "forgeos-guard-gui " "$WORK/calls.log"'
echo hi > "$H/Documents/a.txt"
F run open_file /etc/passwd --yes >/dev/null; A=$?
F run open_file "$H/../../etc/passwd" --yes >/dev/null; B=$?
F run open_file "$H/Documents/a.txt" --yes >/dev/null; C=$?
sleep 0.3
check N3 '[ "$A" -eq 2 ] && [ "$B" -eq 2 ] && [ "$C" -eq 0 ] && grep -qx "xdg-open $H/Documents/a.txt" "$WORK/calls.log"'
F run get_model evil:latest --yes >/dev/null; A=$?
OUT="$(F run get_model gemma4:e2b --yes)"; B=$?
check N4 '[ "$A" -eq 2 ] && [ "$B" -eq 0 ] && grep -qx "ollama pull gemma4:e2b" "$WORK/calls.log" && [ "$(cat "$WORK/cfg/forgeos/ai-quick-model")" = gemma4:e2b ]'
echo 1 > "$WORK/pull-rc"
OUT="$(F run get_model gemma4:31b --yes)"; A=$?
check N5 '[ "$A" -eq 1 ] && grep -q "did not work" <<< "$OUT"'
F run family_call --yes >/dev/null; A=$?
sleep 0.3
check N6 '[ "$A" -eq 0 ] && grep -qx "forgeos-family-call " "$WORK/calls.log"'

# O: memory - private file, no secrets, no duplicates, forget everything
OUT="$(F ask --no-ai "remember that my daughter is Brianna")"
MEM="$WORK/cfg/forgeos/helper/memory.json"
check O1 'grep -q "OK, I.ll remember that: my daughter is Brianna" <<< "$OUT" && [ "$(stat -c %a "$MEM")" = 600 ] && [ "$(stat -c %a "${MEM%/*}")" = 700 ]'
OUT="$(F ask --no-ai "remember that my daughter is Brianna")"
check O2 'grep -q "already remember" <<< "$OUT"'
OUT="$(F remember "my bank password is hunter2")"
OUT2="$(F remember "card 4111 1111 1111 1111")"
check O3 'grep -q "don.t keep passwords" <<< "$OUT" && grep -q "don.t keep passwords" <<< "$OUT2" && ! grep -q "hunter2\|4111" "$MEM"'
OUT="$(F ask --no-ai "what do you remember about me")"
check O4 'grep -q "^- my daughter is Brianna$" <<< "$OUT"'
OUT="$(F ask --no-ai "forget everything")"
check O5 'grep -q "^ACTION.forget_all..Forget everything$" <<< "$OUT" && [ -s "$MEM" ]'
F forget >/dev/null 2>&1; A=$?
F forget --yes >/dev/null; B=$?
check O6 '[ "$A" -eq 3 ] && [ "$B" -eq 0 ] && [ ! -e "$MEM" ] && grep -q "anything yet" <<< "$(F memory)"'

# P: thumbs up / down; a thumbs-down question becomes one of the user's own tests
F feedback up help_answer "how do I print" >/dev/null
F feedback down find "where is the paper tray" >/dev/null
FB="$WORK/data/forgeos/helper"
check P1 '[ "$(wc -l < "$FB/feedback.jsonl")" -eq 2 ] && [ "$(wc -l < "$FB/my-tests.jsonl")" -eq 1 ] && grep -q "\"not_tool\": \"find\"" "$FB/my-tests.jsonl"'
OUT="$(F selftest --no-ai --quick)"
check P2 'grep -q "^SCORE" <<< "$OUT" && grep -q "^FAIL.where is the paper tray.want not find.got find" <<< "$OUT"'
F feedback sideways find "x" >/dev/null 2>&1; A=$?
check P3 '[ "$A" -eq 3 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Forge Helper tests M-P passed."; else echo "$failures Forge Helper test(s) failed."; fi
exit "$((failures > 0))"

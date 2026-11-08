#!/usr/bin/env bash
# Tests for Digital Will (Job 18), case I: the gentle reminders (once a day at most) - started but no envelope
# after a week (then every 2 weeks), the envelope is 6 months old (then once a month), the password safe
# changed after the envelope was made (once per change); "Open Digital Will" on the note opens the window.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-digitalwill-remind.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/digitalwill-fakes.sh
. "$ROOT/tests/digitalwill-fakes.sh"
T0=1800000000; D=86400
at() { FORGEOS_WILL_NOW=$((T0 + $1)) DW "${@:2}"; }   # at SECONDS-AFTER-T0 COMMAND...
notes() { grep -c "^notify-send" <<< "$(calls)"; }

# I1: nothing set up -> nothing; I2: started, no envelope -> after a week, then every 2 weeks
fresh
check I1 '[ "$(at 0 tick)" = "Nothing to remind." ] && [ "$(notes)" = 0 ]'
FORGEOS_WILL_NOW=$T0 answers > /dev/null
R1="$(at $((3 * D)) tick)"; R2="$(at $((8 * D)) tick)"; R3="$(at $((9 * D)) tick)"; R4="$(at $((23 * D)) tick)"
check I2 '[ "$R1" = "Nothing to remind." ] && [ "$R2" = "Reminded: unfinished" ] && [ "$R3" = "Nothing to remind." ] && [ "$R4" = "Reminded: unfinished" ] && [ "$(notes)" = 2 ] && grep -q "^notify-send --app-name=Digital Will .*--action=go=Open Digital Will --action=later=Not now Digital Will You started your Digital Will but have not made your Emergency Envelope yet." <<< "$(calls)" && ! grep -q "^gui" <<< "$(calls)"'

# I3: the envelope is 6 months old -> a note (Open Digital Will opens the window), then once a month
fresh
touch -d "@$((T0 - D))" "$H/Documents/Passwords.kdbx"
FORGEOS_WILL_NOW=$T0 answers > /dev/null
secrets "" "" "" | at 0 make --holder Brianna > /dev/null
R1="$(at $((100 * D)) tick)"; touch "$WORK/note-go"; R2="$(at $((183 * D)) tick)"; R3="$(at $((184 * D)) tick)"; R4="$(at $((214 * D)) tick)"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(grep -c "^gui" <<< "$(calls)")" = 2 ] && break; sleep 0.2; done  # the window starts on its own
check I3 '[ "$R1" = "Nothing to remind." ] && [ "$R2" = "Reminded: old" ] && [ "$R3" = "Nothing to remind." ] && [ "$R4" = "Reminded: old" ] && grep -q "Your Digital Will is 6 months old. Make a new Emergency Envelope" <<< "$(calls)" && grep -q "Your Digital Will is 7 months old." <<< "$(calls)" && [ "$(grep -c "^gui" <<< "$(calls)")" = 2 ]'
check I4 'at $((200 * D)) report | grep -q "It is more than 6 months old: please make a new envelope." && { at $((200 * D)) report > /dev/null; [ $? = 1 ]; } && at $((10 * D)) report > /dev/null'

# I5: the password safe changed after the envelope was made -> one note for that change
fresh
touch -d "@$((T0 - D))" "$H/Documents/Passwords.kdbx"
FORGEOS_WILL_NOW=$T0 answers > /dev/null
secrets "" "" "" | at 0 make --holder Brianna > /dev/null
R1="$(at $((2 * D)) tick)"
touch -d "@$((T0 + 5 * D))" "$H/Documents/Passwords.kdbx"
R2="$(at $((5 * D + 3600)) tick)"; R3="$(at $((7 * D)) tick)"
touch -d "@$((T0 + 9 * D))" "$H/Documents/Passwords.kdbx"
R4="$(at $((9 * D + 3600)) tick)"; R5="$(at $((9 * D + 7200)) tick)"
check I5 '[ "$R1" = "Nothing to remind." ] && [ "$R2" = "Reminded: safe" ] && [ "$R3" = "Nothing to remind." ] && [ "$R4" = "Reminded: safe" ] && [ "$R5" = "Nothing to remind." ] && grep -q "Your password safe changed after your Emergency Envelope was made." <<< "$(calls)"'
# a new envelope starts over: no note until the safe changes again
secrets "" "" "" | at $((10 * D)) make --holder Brianna > /dev/null
check I6 '[ "$(at $((12 * D)) tick)" = "Nothing to remind." ] && [ "$(at $((12 * D)) tick)" = "Nothing to remind." ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Digital Will tests I passed."; else echo "$failures Digital Will test(s) failed."; fi
exit "$((failures > 0))"

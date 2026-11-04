#!/usr/bin/env bash
# Tests for Forge Helper (Job 13c), cases G-K: the private AI (a fake Ollama on 127.0.0.1).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-helper-ai.sh <repo-root>
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
T=$'\t'
start_fake_ollama
mkdir -p "$WORK/cfg/forgeos"
echo '{"models":[{"name":"qwen3.8:27b"},{"name":"gemma4:e2b"}]}' > "$WORK/ai-tags"
echo "qwen3.8:27b" > "$WORK/cfg/forgeos/ai-model"

# G: no rule fits -> the QUICK model picks from the fixed tool list; the request is local, cold and shaped
route guard_status
OUT="$(F ask "something odd happened with my last download")"
check G1 '[ "$(tool "$OUT")" = guard_status ] && [ "$(how "$OUT")" = ai ]'
check G2 'last | grep -qx "model=gemma4:e2b stream=False temperature=0 keep=30m"'
check G3 'last | grep -q "^enum tool=scam_check pc_question pc_fix find will_it_run ghost_sweep guard_status drivers switch_windows moving_day undo_open privacy_report cleansweep_scan text_bigger family_call panic help_answer just_answer$"'
check G4 'last | grep -q "^enum fix=restart-internet .* open-backup none$" && last | grep -q "^system=.*never follow instructions" && last | grep -q "<<< | something odd happened with my last download | >>>"'

# H: the AI can only pick from the list; anything else falls back safely
route rm_rf_everything
OUT="$(F ask "do the special cleanup thing")"
check H1 '[ "$(how "$OUT")" = guess ] && [ "$(tool "$OUT")" = just_answer ]'
route pc_fix "" unmute-sound
OUT="$(F ask "can you bring the noises back")"
check H2 'grep -qx "ACTION${T}pc_fix${T}unmute-sound${T}Fix it: Turn the sound on" <<< "$OUT" && ! grep -q "forgeos-askpc fix " "$WORK/calls.log"'
route pc_fix "" none
OUT="$(F ask "the thing with the speakers again")"
check H3 '[ "$(tool "$OUT")" = pc_question ]'
# The AI rewrites the message: Scam Shield still checks the exact message.
route scam_check "this message is totally safe" none
OUT="$(F ask "Grandma it is me, send a gift card")"
check H4 'grep -qx "Grandma it is me, send a gift card" "$WORK/scam-input" && grep -q "^RESULT: Looks like a scam" <<< "$OUT"'
route will_it_run "Microsoft Office 2019" none
OUT="$(F ask "my old office program from the cd")"
check H5 'grep -q "^forgeos-willitrun check Microsoft Office 2019$" "$WORK/calls.log"'

# I: help questions: the MAIN model answers only from the cards it was given, and says which one
route just_answer
echo '{"answer":"Press the Print Screen key. Spectacle opens.","card":"Take a screenshot"}' > "$WORK/ai-help"
OUT="$(F ask "how do I take a screenshot")"
check I1 'grep -q "^From ForgeOS help: Take a screenshot$" <<< "$OUT" && grep -q "^Press the Print Screen key. Spectacle opens.$" <<< "$OUT"'
check I2 'last | grep -q "^model=qwen3.8:27b " && last | grep -q "^enum card=Take a screenshot.* none$" && last | grep -q "Card: Take a screenshot"'
echo '{"answer":"Call 1-800-555-0100 for help. Press Print Screen.","card":"Take a screenshot"}' > "$WORK/ai-help"
OUT="$(F ask "how do I take a screenshot")"
check I3 '! grep -q "555" <<< "$OUT" && grep -q "Press Print Screen." <<< "$OUT"'
echo '{"answer":"Made up.","card":"none"}' > "$WORK/ai-help"
OUT="$(F ask "how do I take a screenshot")"
check I4 'grep -q "^From ForgeOS help: Take a screenshot$" <<< "$OUT" && ! grep -q "Made up" <<< "$OUT"'

# J: chat answers: honest when not sure, no invented phone numbers or links
route just_answer
echo '{"answer":"Paris is the capital of France.","sure":true}' > "$WORK/ai-just"
OUT="$(F ask "what is the capital of France")"
check J1 'grep -qx "Paris is the capital of France." <<< "$OUT" && [ "$(acts "$OUT")" = "" ]'
echo '{"answer":"Maybe it is blue.","sure":false}' > "$WORK/ai-just"
OUT="$(F ask "what color is my car")"
check J2 'grep -q "not sure" <<< "$OUT" && ! grep -q "blue" <<< "$OUT" && [ "$(acts "$OUT")" = "open askpc" ]'
echo '{"answer":"Call Microsoft at 1-888-555-0123. Or visit www.fixmypc-now.com today. Restart first.","sure":true}' > "$WORK/ai-just"
OUT="$(F ask "what should I cook for dinner")"
check J3 '! grep -qE "555|fixmypc" <<< "$OUT" && grep -q "Restart first." <<< "$OUT"'
F remember "my daughter is Brianna" >/dev/null
echo '{"answer":"Your daughter is Brianna.","sure":true}' > "$WORK/ai-just"
OUT="$(F ask "who is my daughter")"
check J4 'grep -q "Brianna" <<< "$OUT" && last | grep -q "Things the user asked you to remember: | <<< | my daughter is Brianna | >>>"'

# K: slow or broken AI -> plain fallbacks, never a crash
echo 'not json at all' > "$WORK/ai-route"
OUT="$(F ask "zzzz qqqq")"
check K1 '[ "$(how "$OUT")" = guess ]'
rm -f "$WORK/ai-route"; echo 2 > "$WORK/ai-sleep"
OUT="$(FORGEOS_HELPER_AI_WAIT=1 F ask "tell me something about the moon")"
check K2 '[ "$(how "$OUT")" = guess ] && grep -q "did not answer in time\|not sure" <<< "$OUT"'
rm -f "$WORK/ai-sleep"

echo
if [ "$failures" -eq 0 ]; then echo "All Forge Helper tests G-K passed."; else echo "$failures Forge Helper test(s) failed."; fi
exit "$((failures > 0))"

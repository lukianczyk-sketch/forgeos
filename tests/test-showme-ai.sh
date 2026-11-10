#!/usr/bin/env bash
# Tests for Show Me How (Job 22), case G: no built-in guide -> the private AI picks ONE word that is really on
# the screen (a fixed list it can't go outside of, checked again here), never money/password words, and a
# safe sentence; not sure = it says so; no AI = the help card in writing. Uses a pretend Ollama on this PC.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-showme-ai.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
AIPID=""
trap '[ -n "$AIPID" ] && kill "$AIPID" 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/showme-fakes.sh
. "$ROOT/tests/showme-fakes.sh"
python3 "$ROOT/tests/find-fake-ollama.py" "$WORK" & AIPID=$!
for _ in $(seq 50); do [ -s "$WORK/ai-port" ] && break; sleep 0.1; done
FORGEOS_OLLAMA_URL="http://127.0.0.1:$(cat "$WORK/ai-port")"
export FORGEOS_OLLAMA_URL
echo '{"models": [{"name": "qwen3.8:27b"}]}' > "$WORK/ai-tags"
Q="how do I change the mouse speed"
answer() { printf '{"word": "%s", "say": "%s", "finished": %s}' "$1" "$2" "${3:-false}" > "$WORK/ai-answer"; }

# G1: the AI points at "Mouse" (on the screen); when it is clicked, the AI says the task is finished
fresh; screen 1 "Mouse@100,100" "Keyboard@100,200"; screen 2 "Pointer Speed@300,300"
answer "Mouse" "Click Mouse to see the mouse settings." true
OUT="$(SM ask "$Q" --no-draw)"; CODE=$?
check G1 '[ "$CODE" = 0 ] && grep -q "^VIEW${T}point${T}1/0${T}0.0521 0.0926 0.0234 0.0148${T}rb${T}Click Mouse to see the mouse settings.$" <<< "$OUT" && grep -q "^END${T}done" <<< "$OUT"'
# G2: what the AI was given: only the words on the screen (+ none) to pick from, temperature 0, data fenced
check G2 'python3 -c "
import json, sys
b = json.load(open(sys.argv[1]))
enum = b[\"format\"][\"properties\"][\"word\"][\"enum\"]
u = b[\"messages\"][1][\"content\"]
assert b[\"model\"] == \"qwen3.8:27b\" and b[\"options\"][\"temperature\"] == 0, b
assert enum == [\"Pointer Speed\", \"none\"], enum
assert \"<<<\nhow do I change the mouse speed\n>>>\" in u and \"Steps already shown: Click Mouse\" in u, u
" "$WORK/ai-body.json"'
# G3: a word that is NOT on the screen = not sure (it never points at a guess)
fresh; screen 0 "Mouse@100,100"
answer "Pointer Speed" "Click Pointer Speed."
OUT="$(SM ask "$Q" --no-draw)"; CODE=$?
check G3 '[ "$CODE" = 1 ] && ! grep -q "^VIEW${T}point" <<< "$OUT" && grep -q "^END${T}unsure${T}I.m not sure what to click next, so I won.t guess." <<< "$OUT"'
# G4: never money or password things, even when they are on the screen
fresh; screen 0 "Pay Now@100,100" "Mouse@300,300"
answer "Pay Now" "Click Pay Now."
OUT="$(SM ask "$Q" --no-draw)"
answer "none" "I am not sure."
OUT2="$(SM ask "$Q" --no-draw)"
check G4 '! grep -q "^VIEW${T}point" <<< "$OUT" && grep -q "^END${T}unsure" <<< "$OUT" && grep -q "^END${T}unsure" <<< "$OUT2"'
# G5: a risky sentence from the AI is replaced by a plain "Click X."
fresh; screen 0 "Mouse@100,100"
answer "Mouse" "Click Mouse and then type your bank password here."
OUT="$(FORGEOS_SHOWME_LOOKS=1 SM ask "$Q" --no-draw)"
check G5 'grep -q "^VIEW${T}point${T}1/0${T}.*${T}Click Mouse.$" <<< "$OUT"'
# G6: no private AI: no guess - the help card in writing (exit 1)
echo '{"models": []}' > "$WORK/ai-tags"
fresh; screen 0 "Mouse@100,100"
OUT="$(SM ask "$Q" --no-draw)"; CODE=$?
check G6 '[ "$CODE" = 1 ] && grep -q "^I don.t have a guide for that yet, and the private AI is not set up." <<< "$OUT" && ! grep -q "^VIEW" <<< "$OUT" && [ ! -e "$WORK/pictures" ]'
# G7: a question with a built-in guide never asks the AI
echo '{"models": [{"name": "qwen3.8:27b"}]}' > "$WORK/ai-tags"; rm -f "$WORK/ai-body.json"
fresh; screen 0 "Scan@100,100"
OUT="$(FORGEOS_SHOWME_LOOKS=1 SM ask "how do I scan a paper" --no-draw)"
check G7 'grep -q "^VIEW${T}point${T}1/2" <<< "$OUT" && [ ! -e "$WORK/ai-body.json" ]'
# G8: a scam, a stranger or an emergency: Show Me How refuses (Forge Helper's tools handle it), reads nothing;
#     download / install / allow / remote-control words are never pointed at by the AI
fresh; screen 0 "Install@100,100" "Allow@300,300"
OUT="$(SM ask "help me install anydesk the microsoft man said to" --no-draw)"; CODE=$?
OUT2="$(SM ask "this website says my computer has a virus and to call this number" --no-draw)"; CODE2=$?
answer "Install" "Click Install."
OUT3="$(SM ask "$Q" --no-draw)"
check G8 '[ "$CODE$CODE2" = 11 ] && grep -q "^This sounds like a scam, a stranger in your PC or an emergency, so Show Me How won.t walk you through it." <<< "$OUT" && grep -q "^This sounds like a scam" <<< "$OUT2" && ! grep -q "^VIEW${T}point" <<< "$OUT3" && grep -q "^END${T}unsure" <<< "$OUT3"'

echo
if [ "$failures" -eq 0 ]; then echo "All Show Me How tests G passed."; else echo "$failures Show Me How test(s) failed."; exit 1; fi

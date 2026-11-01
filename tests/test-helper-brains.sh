#!/usr/bin/env bash
# Tests for Forge Helper (Job 13c), case L: which AI brains it uses, the warm-up, and the weekly
# "models" check (switches only to a model that scores HIGHER; only SUGGESTS downloads).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-helper-brains.sh <repo-root>
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
cp "$ROOT/tests/helper-ai-map.json" "$WORK/ai-map"

# L1-L4: brains, warm-up; the model picked by "models" wins over AI Setup's pick
OUT="$(F brains)"
check L1 'grep -qx "MAIN${T}qwen3.8:27b" <<< "$OUT" && grep -qx "QUICK${T}gemma4:e2b" <<< "$OUT" && ! grep -q QUICKGET <<< "$OUT"'
echo '{"models":[{"name":"qwen3.8:27b"}]}' > "$WORK/ai-tags"
OUT="$(F brains)"
check L2 'grep -qx "QUICK${T}qwen3.8:27b" <<< "$OUT" && grep -qx "QUICKGET${T}gemma4:e2b${T}~5GB" <<< "$OUT"'
F warm; RC=$?
check L3 '[ "$RC" -eq 0 ] && last | grep -qx "model=qwen3.8:27b stream=None temperature=None keep=30m"'
echo '{"models":[{"name":"qwen3.8:27b"},{"name":"gpt-oss:20b"}]}' > "$WORK/ai-tags"
echo "gpt-oss:20b" > "$WORK/cfg/forgeos/helper-model"
check L4 'grep -qx "MAIN${T}gpt-oss:20b" <<< "$(F brains)"'

# L5-L7 models: a model that answers badly is never kept; switch only to a HIGHER score; never downloads
echo '{"models":[{"name":"gemma4:e4b"},{"name":"gemma4:12b"}]}' > "$WORK/ai-tags"
echo gemma4:12b > "$WORK/cfg/forgeos/ai-model"; echo gemma4:12b > "$WORK/ai-bad"
OUT="$(FAKE_VRAM=8192 F models)"
check L5 'grep -qx "SWITCHED${T}gemma4:12b${T}gemma4:e4b" <<< "$OUT" && [ "$(cat "$WORK/cfg/forgeos/helper-model")" = gemma4:e4b ] && ! grep -q SUGGEST <<< "$OUT"'
: > "$WORK/ai-bad"
OUT="$(FAKE_VRAM=8192 F models)"
check L6 'grep -qx "KEPT${T}gemma4:e4b" <<< "$OUT"'
OUT="$(FAKE_VRAM=24576 F models)"
check L7 'grep -qx "SUGGEST${T}gemma4:31b${T}~19GB" <<< "$OUT" && grep -qx "SUGGEST${T}gemma4:31b${T}~19GB" <<< "$(F brains)" && ! grep -q "ollama" "$WORK/calls.log"'

echo
if [ "$failures" -eq 0 ]; then echo "All Forge Helper tests L1-L7 passed."; else echo "$failures Forge Helper test(s) failed."; fi
exit "$((failures > 0))"

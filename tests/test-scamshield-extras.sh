#!/usr/bin/env bash
# Tests for Scam Shield (Job 8), cases L-T: private AI, clipboard, list download, window, build files.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-scamshield-extras.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
U="$ROOT/files/system/usr"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
mkdir -p "$WORK/bin" "$WORK/lists" "$WORK/cfg/forgeos" "$WORK/web"

# Fake curl: Ollama answers from FAKE_TAGS / FAKE_AI; downloads come from $WORK/web.
cat > "$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$WORK/curl.log"
o=""; last=""
while [ $# -gt 0 ]; do
  case "$1" in -o) o="$2"; shift ;; *) last="$1" ;; esac
  shift
done
case "$last" in
  */api/tags) [ -n "${FAKE_TAGS:-}" ] || exit 7; printf '%s' "$FAKE_TAGS" ;;
  */api/chat) cat > "$WORK/body.json"; [ -n "${FAKE_AI:-}" ] || exit 28
    jq -n --arg c "$FAKE_AI" '{message: {role: "assistant", content: $c}}' ;;
  https://*) f="$WORK/web/${last#https://}"; [ -f "$f" ] || exit 22; cp "$f" "$o" ;;
  *) exit 7 ;;
esac
EOF
printf '#!/bin/sh\ncat "$WORK/clip" 2>/dev/null\n' > "$WORK/bin/wl-paste"
printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/dbus-send"
printf '#!/bin/sh\necho "$*" >> "$WORK/kdialog.log"\n[ "$1 $3" = "--title --progressbar" ] && echo "org.x /p"\nexit 0\n' > "$WORK/bin/kdialog"
chmod +x "$WORK/bin/"*
export WORK PATH="$WORK/bin:$PATH" FORGEOS_SCAM_LIB="$U/libexec/forgeos-scamshield-lib"
export FORGEOS_SCAM_DIR="$WORK/lists" FORGEOS_SCAM_DATA="$U/share/forgeos" XDG_CONFIG_HOME="$WORK/cfg"
export FAKE_TAGS='{"models":[{"name":"gemma4:e2b"},{"name":"qwen3.8:27b"}]}'
SS="$U/bin/forgeos-scamshield"
echo "qwen3.8:27b" > "$WORK/cfg/forgeos/ai-model"

# L: the AI raises a clean-looking message to a scam; the request is local, cold and shaped
OUT="$(echo "Hello dear customer" | FAKE_AI='{"verdict":"scam","reasons":["It pretends to be your bank."],"advice":"Delete it."}' bash "$SS" check)"; RC=$?
check L1 '[ "$RC" -eq 2 ] && grep -q "pretends to be your bank" <<< "$OUT" && grep -q "Delete it." <<< "$OUT"'
check L2 'jq -e ".model == \"qwen3.8:27b\" and .stream == false and .options.temperature == 0 and .format.properties.verdict.enum == [\"scam\",\"suspicious\",\"safe\"]" "$WORK/body.json" >/dev/null && grep -q "http://127.0.0.1:11434/api/chat" "$WORK/curl.log"'

# M: the AI can never lower what the rules found
OUT="$(echo "Your computer is infected! Call Microsoft" | FAKE_AI='{"verdict":"safe","reasons":[],"advice":"Fine."}' bash "$SS" check)"; RC=$?
check M '[ "$RC" -eq 1 ] && grep -q "still says to be careful" <<< "$OUT"'

# N: a broken AI answer, no AI at all, --no-ai, and a missing saved model (first one is used)
OUT="$(echo hi | FAKE_AI='not json' bash "$SS" check)"; RC=$?
check N1 '[ "$RC" -eq 0 ] && grep -q "did not answer in time" <<< "$OUT"'
OUT="$(echo hi | FAKE_TAGS="" bash "$SS" check)"
check N2 'grep -q "AI is not set up" <<< "$OUT"'
: > "$WORK/curl.log"
echo hi | bash "$SS" check --no-ai >/dev/null
check N3 '[ ! -s "$WORK/curl.log" ]'
rm -f "$WORK/cfg/forgeos/ai-model"
echo hi | FAKE_AI='{"verdict":"suspicious","reasons":["x"],"advice":"y"}' bash "$SS" check >/dev/null; RC=$?
check N4 '[ "$RC" -eq 1 ] && [ "$(jq -r .model "$WORK/body.json")" = "gemma4:e2b" ]'

# O: check what was copied
echo "Buy gift cards now and send me the code" > "$WORK/clip"
bash "$SS" check-clipboard --no-ai >/dev/null; RC=$?
: > "$WORK/clip"
ERR="$(bash "$SS" check-clipboard --no-ai 2>&1)"; RC2=$?
check O '[ "$RC" -eq 2 ] && [ "$RC2" -eq 3 ] && grep -q "Nothing is copied" <<< "$ERR"'

# P: wrong use and unreadable files
bash "$SS" bogus 2>/dev/null; R1=$?
bash "$SS" check /nonexistent 2>/dev/null; R2=$?
check P '[ "$R1" -eq 3 ] && [ "$R2" -eq 3 ]'

# Q: list download: first mirror down, second works; bad lines are dropped; tiny lists keep the old one
mkdir -p "$WORK/web/curbengh.github.io/malware-filter"
{ echo "# Title: test"; for i in $(seq 1 150); do echo "0.0.0.0 scam$i.example.top"; done; echo "0.0.0.0 bad name"; echo "127.0.0.1 x.com"; } \
  > "$WORK/web/curbengh.github.io/malware-filter/phishing-filter-hosts.txt"
echo "0.0.0.0 only.one.com" > "$WORK/web/curbengh.github.io/malware-filter/urlhaus-filter-hosts.txt"
echo "old.example.com" > "$WORK/lists/urlhaus.list"
: > "$WORK/curl.log"
OUT="$(bash "$U/libexec/forgeos-scamshield-update")"; RC=$?
check Q1 '[ "$RC" -eq 0 ] && [ "$(wc -l < "$WORK/lists/phishing.list")" -eq 150 ] && grep -qx "scam7.example.top" "$WORK/lists/phishing.list" && ! grep -q "x.com" "$WORK/lists/phishing.list"'
check Q2 'grep -qx "old.example.com" "$WORK/lists/urlhaus.list" && [ -z "$(find "$WORK/lists" -name ".download*")" ] && ! grep -q "pages.dev/phishing" "$WORK/curl.log"'
rm -rf "$WORK/web/curbengh.github.io"
bash "$U/libexec/forgeos-scamshield-update" 2>/dev/null; RC=$?
check Q3 '[ "$RC" -eq 1 ] && [ "$(wc -l < "$WORK/lists/phishing.list")" -eq 150 ]'

# R: the window: a right-clicked file is checked at once; a scam is shown as an error box
printf '#!/bin/sh\necho "$*" > "$WORK/engine.args"\necho "RESULT: Looks like a scam"\nexit 2\n' > "$WORK/bin/fake-engine"
chmod +x "$WORK/bin/fake-engine"
FORGEOS_SCAM_ENGINE="$WORK/bin/fake-engine" bash "$U/bin/forgeos-scamshield-gui" --file "$WORK/mail.eml"
check R '[ "$(cat "$WORK/engine.args")" = "check $WORK/mail.eml" ] && grep -q -- "--error RESULT: Looks like a scam" "$WORK/kdialog.log"'

# S: menu entry, right-click entry, daily list timer
D="$U/share"
s=0
grep -qx "Exec=/usr/bin/forgeos-scamshield-gui" "$D/applications/forgeos-scamshield.desktop" || s=1
grep -qx "Exec=/usr/bin/forgeos-scamshield-gui --file %f" "$D/kio/servicemenus/forgeos-scamshield.desktop" || s=1
grep -qx "ExecStart=/usr/libexec/forgeos-scamshield-update" "$U/lib/systemd/system/forgeos-scamshield-update.service" || s=1
grep -qx "Persistent=true" "$U/lib/systemd/system/forgeos-scamshield-update.timer" || s=1
if command -v desktop-file-validate >/dev/null 2>&1; then desktop-file-validate "$D/applications/forgeos-scamshield.desktop" || s=1; fi
check S '[ "$s" -eq 0 ]'

# T: the build makes the scripts runnable, turns on the timer, and adds wl-clipboard
SET="$ROOT/files/scripts/forgeos-setup.sh"
t=0
for f in /usr/bin/forgeos-scamshield /usr/bin/forgeos-scamshield-gui /usr/libexec/forgeos-scamshield-update; do
  grep "^chmod 0755" "$SET" | grep -q " $f\( \|$\)" || t=1
done
grep -q "^systemctl enable forgeos-scamshield-update.timer" "$SET" || t=1
grep -q "^ *- wl-clipboard" "$ROOT/recipes/common-modules.yml" || t=1
check T '[ "$t" -eq 0 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Scam Shield extra tests passed."; else echo "$failures Scam Shield extra test(s) failed."; exit 1; fi

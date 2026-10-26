#!/usr/bin/env bash
# Tests for the Scam Shield rule check (Job 8), cases A-K. No AI, no internet.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-scamshield.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
U="$ROOT/files/system/usr"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

mkdir -p "$WORK/bin" "$WORK/lists"
printf '%s\n' "evil-login.example" "bad.weebly.com" > "$WORK/lists/phishing.list"
printf '#!/bin/sh\necho "$*" >> "%s/curl.log"\nexit 7\n' "$WORK" > "$WORK/bin/curl"
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH" FORGEOS_SCAM_LIB="$U/libexec/forgeos-scamshield-lib"
export FORGEOS_SCAM_DIR="$WORK/lists" FORGEOS_SCAM_DATA="$U/share/forgeos" XDG_CONFIG_HOME="$WORK/cfg"

# run <message>: check it with the rules only; answer in $OUT, exit code in $RC.
run() {
  OUT="$(printf '%s\n' "$1" | bash "$U/bin/forgeos-scamshield" check --no-ai 2>&1)"
  RC=$?
}

# A: every script is valid bash
m=0
for f in "$U/bin/forgeos-scamshield" "$U/bin/forgeos-scamshield-gui" "$U/libexec/forgeos-scamshield-lib" "$U/libexec/forgeos-scamshield-update"; do
  bash -n "$f" || m=1
done
check A '[ "$m" -eq 0 ]'

# B: a classic family-emergency gift card scam
run "Grandma, it's me. I'm in jail, please don't tell mom. Buy Google Play gift cards and read me the numbers."
check B '[ "$RC" -eq 2 ] && grep -q "RESULT: Looks like a scam" <<< "$OUT" && grep -q "gift cards" <<< "$OUT" && grep -q "keep it secret" <<< "$OUT"'

# C: a normal message and a real Amazon link are fine
run "Hi Robert, lunch at noon tomorrow? Your order: https://www.amazon.com/gp/your-orders"
check C '[ "$RC" -eq 0 ] && grep -q "RESULT: No scam signs found" <<< "$OUT" && grep -q "Links checked: 1" <<< "$OUT" && ! grep -q "^Why:" <<< "$OUT"'

# D: a fake PayPal address (with a 1 for the l) and a fake USPS delivery text
run "Sign in: https://secure.paypa1-account.com/login"
check D1 '[ "$RC" -eq 1 ] && grep -q "uses the name \"paypal\"" <<< "$OUT"'
run "USPS: Your package is on hold due to an incomplete address. Update now: http://usps-redeliver.top/track"
check D2 '[ "$RC" -eq 2 ] && grep -q "package is stuck" <<< "$OUT" && grep -q "ends in .top" <<< "$OUT" && grep -q "not secure" <<< "$OUT"'

# E: the downloaded scam list: exact names and their sub-sites, but not neighbours
run "see https://login.bad.weebly.com/x and www.evil-login.example."
check E1 '[ "$RC" -eq 2 ] && grep -q "login.bad.weebly.com is on a list" <<< "$OUT"'
run "see https://good.weebly.com"
check E2 '[ "$RC" -eq 0 ]'
OUT="$(printf 'see https://bad.weebly.com\n' | FORGEOS_SCAM_DIR="$WORK/none" bash "$U/bin/forgeos-scamshield" check --no-ai)"
check E3 'grep -q "lists last updated: not downloaded yet" <<< "$OUT" && ! grep -q "on a list" <<< "$OUT"'

# F: hidden address after @, a bare number, short links, look-alike letters, very long names
run "Check http://paypal.com@203.0.113.9/login"
check F1 '[ "$RC" -eq 2 ] && grep -q "after an @ sign. It really goes to 203.0.113.9" <<< "$OUT" && grep -q "bare number" <<< "$OUT"'
run "Visit https://xn--pypal-4ve.com or bit.ly/3abc or a.b.c.d.example.com"
check F2 '[ "$RC" -eq 2 ] && grep -q "look-alike letters" <<< "$OUT" && grep -q "short link (bit.ly)" <<< "$OUT" && grep -q "very long" <<< "$OUT"'

# G: links inside an HTML email are found; file names are not links
run "<a href=\"https://bad.weebly.com/a\">Track</a> policy.pdf"
check G '[ "$RC" -eq 2 ] && grep -q "Links checked: 1" <<< "$OUT"'

# H: real .gov sites and names that only contain a brand are not flagged
run "Visit irs.gov, irs.treasury.gov, pineapple.com, apple.com and support.microsoft.com"
check H1 '[ "$RC" -eq 0 ]'
run "Pay at https://www.irs.gov.payment-center.com"
check H2 'grep -q "uses the name \"irs\"" <<< "$OUT"'

# I: the sender's email address is checked too
run "From: PayPal Service <service@paypal-billing.com>"
check I1 'grep -q "paypal-billing.com uses the name \"paypal\"" <<< "$OUT"'
run "From: PayPal <service@paypal.com> Your receipt"
check I2 '[ "$RC" -eq 0 ] && grep -q "Links checked: 0" <<< "$OUT"'

# J: fake tech support, remote control apps; every kind of warning counts once
run "Your computer is infected! Call Microsoft now and install AnyDesk. Install AnyDesk now. Urgent urgent. win.top cash.top"
check J '[ "$RC" -eq 2 ] && [ "$(grep -c "control your computer" <<< "$OUT")" -eq 1 ] && [ "$(grep -c "rush or scare" <<< "$OUT")" -eq 1 ] && [ "$(grep -c "ends in .top" <<< "$OUT")" -eq 1 ]'

# K: the rule files: 4 parts per rule, whole-number points, every pattern works, no rule twice
k=0
while IFS='~' read -r id pts pat why; do
  case "$id" in ''|'#'*) continue ;; esac
  [[ "${pts// /}" =~ ^[0-9]+$ ]] || k=1
  [ -n "$why" ] || k=1
  pat="${pat# }"; pat="${pat% }"
  echo x | grep -qiE -- "$pat"; [ $? -le 1 ] || k=1
done < "$U/share/forgeos/scamshield-words.txt"
dups="$(sed -n 's/^\([a-z]*\) ~.*/\1/p' "$U/share/forgeos/scamshield-words.txt" | sort | uniq -d)"
check K '[ "$k" -eq 0 ] && [ -z "$dups" ] && [ ! -e "$WORK/curl.log" ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Scam Shield rule tests passed."; else echo "$failures Scam Shield rule test(s) failed."; exit 1; fi

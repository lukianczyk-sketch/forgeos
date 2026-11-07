#!/usr/bin/env bash
# Tests for Fake Tech Support Guard (Job 17), cases G-H: anyone can see the screen -> money websites locked
# (/etc/hosts block), a red note, passwords locked; open 10 s after; "on purpose"; root helper; the list.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-techguard-money.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/techguard-fakes.sh
. "$ROOT/tests/techguard-fakes.sh"
B="# >>> ForgeOS Fake Tech Support Guard: money websites locked while someone can see this screen >>>"
E="# <<< ForgeOS Fake Tech Support Guard <<<"
GB="# >>> ForgeOS Always-On Guard: scam and virus websites blocked (made by forgeos-guard-hosts, do not edit) >>>"
LIST="$ROOT/files/system/usr/share/forgeos/techguard/money-sites.txt"
N="$(grep -cvE '^(#|$)' "$LIST")"
later() { FORGEOS_TG_NOW="$(( $(date +%s) + $1 ))" TG watch --once; }

# G: a video call shares the screen -> money websites locked (every sign-in name), Website Guard's block and
# the old lines kept, one red note; stops -> open again only after 10 quiet seconds, note closed
fresh
printf '%s\n0.0.0.0 evil.example\n# <<< ForgeOS Always-On Guard <<<\n' "$GB" >> "$WORK/hosts"; cp "$WORK/hosts" "$WORK/hosts.before"
share us.zoom.Zoom "Zoom Meeting" 0
tick >/dev/null
check G1 'grep -qx "$B" "$WORK/hosts" && grep -qx "0.0.0.0 chase.com" "$WORK/hosts" && grep -qx ":: secure.bankofamerica.com" "$WORK/hosts" && grep -qx "0.0.0.0 onlinebanking.paypal.com" "$WORK/hosts" && [ "$(grep -c "^0.0.0.0 " "$WORK/hosts")" -eq "$((N * 16 + 1))" ]'
check G2 'head -n 4 "$WORK/hosts" | cmp -s - <(head -n 4 "$WORK/hosts.before") && grep -qx "0.0.0.0 evil.example" "$WORK/hosts" && grep -q "^notify-send .*--print-id --urgency=critical Someone can see this screen Zoom Meeting can see your screen" <<< "$(calls)" && [ "$(st "s[\"note\"]")" = 7 ]'
: > "$WORK/calls.log"; tick >/dev/null
TG status > "$WORK/s"; RC=$?
check G3 '! grep -q notify-send <<< "$(calls)" && [ "$RC" -eq 1 ] && grep -qx "MONEY${T}locked" "$WORK/s" && grep -qx "SHARING${T}us.zoom.Zoom" "$WORK/s"'
share none; tick >/dev/null
check G4 'grep -qx "$B" "$WORK/hosts"'
later 11 >/dev/null
check G5 'cmp -s "$WORK/hosts" "$WORK/hosts.before" && grep -q "^gdbus call .*CloseNotification 7$" <<< "$(calls)" && [ "$(st "s[\"money\"]")" = open ]'
later 20 >/dev/null
check G6 'cmp -s "$WORK/hosts" "$WORK/hosts.before" && [ "$(grep -c CloseNotification <<< "$(calls)")" = 1 ]'

# H: I'm sharing on purpose -> PC password, open until the sharing stops; next sharing locks again
fresh
share com.obsproject.Studio OBS 0; tick >/dev/null
touch "$WORK/pkexec-no"; OUT="$(TG share-ok)"; RC=$?; rm -f "$WORK/pkexec-no"
check H1 '[ "$RC" -eq 1 ] && grep -q "stay locked" <<< "$OUT" && grep -qx "$B" "$WORK/hosts"'
OUT="$(TG share-ok)"; RC=$?
check H2 '[ "$RC" -eq 0 ] && grep -q "open again until the screen sharing stops" <<< "$OUT" && cmp -s "$WORK/hosts" "$WORK/hosts.start"'
tick >/dev/null
check H3 'cmp -s "$WORK/hosts" "$WORK/hosts.start" && grep -qx "MONEY${T}open" <<< "$(TG status)"'
share none; later 11 >/dev/null; share com.obsproject.Studio OBS 0; later 12 >/dev/null
check H4 'grep -qx "$B" "$WORK/hosts"'
# H5: the root helper takes only lock / unlock; root-trust only add PID / share
bash "$FORGEOS_TG_MONEY" >/dev/null 2>&1; A=$?; bash "$FORGEOS_TG_MONEY" lock now >/dev/null 2>&1; B2=$?
bash "$FORGEOS_TG_TRUST" add 12x >/dev/null 2>&1; C=$?; bash "$FORGEOS_TG_TRUST" share x >/dev/null 2>&1; D=$?
FORGEOS_TG_ROOT=1 bash "$FORGEOS_TG_MONEY" unlock >/dev/null; U=$?
check H5 '[ "$A" -eq 3 ] && [ "$B2" -eq 3 ] && [ "$C" -eq 3 ] && [ "$D" -eq 3 ] && [ "$U" -eq 0 ] && cmp -s "$WORK/hosts" "$WORK/hosts.start"'
# H6: the list - real website names only, no doubles, the big banks, payments, gift cards and crypto
DOM='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'
check H6 '[ "$N" -ge 60 ] && [ -z "$(grep -vE "^(#|$)" "$LIST" | grep -vE "$DOM")" ] && [ -z "$(grep -vE "^(#|$)" "$LIST" | sort | uniq -d)" ] && for d in chase.com bankofamerica.com wellsfargo.com paypal.com zellepay.com westernunion.com giftcards.com coinbase.com; do grep -qx "$d" "$LIST" || exit 1; done'

# H7: the lock is refused -> tried once per sharing (never a password window every 2 s); the note only once
fresh; touch "$WORK/pkexec-no"; fake notify-send 'exit 1'
share us.zoom.Zoom Zoom 0; tick >/dev/null; tick >/dev/null; share none; later 11 >/dev/null
rm -f "$WORK/pkexec-no"; fake notify-send 'echo 7'
check H7 '[ "$(grep -c "^pkexec" <<< "$(calls)")" = 1 ] && [ "$(grep -c "^notify-send" <<< "$(calls)")" = 1 ] && [ "$(st "s[\"money\"]")" = open ] && cmp -s "$WORK/hosts" "$WORK/hosts.start"'
# H8: opening again was refused -> stays locked (shown); "open the money websites" (PC password) opens them,
# and the next sharing locks them again
fresh; share us.zoom.Zoom Zoom 0; tick >/dev/null; share none
touch "$WORK/pkexec-no"; later 11 >/dev/null; rm -f "$WORK/pkexec-no"
A="$(st "s[\"money\"]")"; S="$(TG status)"; TG share-ok >/dev/null; C="$(cat "$WORK/hosts")"
share us.zoom.Zoom Zoom 0; later 30 >/dev/null
check H8 '[ "$A" = stuck ] && grep -qx "MONEY${T}locked" <<< "$S" && ! grep -qx "$B" <<< "$C" && grep -qx "$B" "$WORK/hosts"'
# H9: Easy Passwords (KeePassXC) is locked when the sharing starts (only when it is open)
fresh; prog 80 keepassxc "$APP/app-flatpak-org.keepassxc.KeePassXC-1.scope"; share us.zoom.Zoom Zoom 0; tick >/dev/null
check H9 'grep -qx "flatpak run --command=keepassxc org.keepassxc.KeePassXC --lock" <<< "$(calls)"'
echo
if [ "$failures" -eq 0 ]; then echo "All Fake Tech Support Guard tests G-H passed."; else echo "$failures Fake Tech Support Guard test(s) failed."; fi
exit "$((failures > 0))"

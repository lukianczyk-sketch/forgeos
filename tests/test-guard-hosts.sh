#!/usr/bin/env bash
# Tests for Always-On Guard (Job 13b), cases M-N: Website Guard (forgeos-guard-hosts) on a test hosts file:
# block added from Scam Shield's lists, your own lines never touched, same lists = no change, unblock / block
# again, remove = the file exactly as before, no lists yet, bad names, not allowed to write.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-guard-hosts.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK"; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
HELPER="$ROOT/files/system/usr/libexec/forgeos-guard-hosts"
H() { bash "$HELPER" "$@"; }
export FORGEOS_HOSTS="$WORK/hosts" FORGEOS_SCAM_DIR="$WORK/scam" FORGEOS_GUARD_ALLOW="$WORK/etc/guard-allow.list" FORGEOS_GUARD_STATE="$WORK/state"
BEGIN="# >>> ForgeOS Always-On Guard: scam and virus websites blocked (made by forgeos-guard-hosts, do not edit) >>>"
END="# <<< ForgeOS Always-On Guard <<<"
mkdir -p "$WORK/scam" "$WORK/etc"
printf '127.0.0.1   localhost localhost.localdomain\n::1         localhost\n# my NAS\n10.0.0.5 nas.home\n' > "$WORK/hosts"; cp "$WORK/hosts" "$WORK/orig"
printf '# ForgeOS: never block these\n' > "$WORK/etc/guard-allow.list"

# M: no lists yet -> nothing changes; lists -> block (cleaned, both IPv4 + IPv6), status file, same again = no change
OUT="$(H apply)"; RC=$?
check M1 '[ "$RC" -eq 0 ] && grep -q "^No scam lists yet" <<< "$OUT" && cmp -s "$WORK/hosts" "$WORK/orig" && [ ! -e "$WORK/state/status" ]'
printf 'paypa1-login.example\nWWW.Fake-Bank.TEST\nlocalhost\nmy.localdomain\nprinter.local\n-bad-.example\nbad_name.example\nnodot\nsupport.ok-shop.example\n' > "$WORK/scam/phishing.list"
printf 'fake-bank.test\nmalware.example.org\n' > "$WORK/scam/urlhaus.list"
OUT="$(H apply)"; RC=$?
BLOCK="$(sed -n "/^# >>> ForgeOS/,/^# <<< ForgeOS/p" "$WORK/hosts")"
check M2 '[ "$RC" -eq 0 ] && [ "$OUT" = "Website Guard is ON: 5 scam and virus websites blocked." ] && [ "$(head -n 4 "$WORK/hosts")" = "$(cat "$WORK/orig")" ] && [ "$(sed -n 5p "$WORK/hosts")" = "$BEGIN" ] && [ "$(tail -n 1 "$WORK/hosts")" = "$END" ]'
check M3 'grep -qx "0.0.0.0 www.fake-bank.test" <<< "$BLOCK" && grep -qx ":: www.fake-bank.test" <<< "$BLOCK" && grep -qx "0.0.0.0 fake-bank.test" <<< "$BLOCK" && [ "$(grep -c "^0.0.0.0 " <<< "$BLOCK")" = 5 ] && [ "$(grep -c "^:: " <<< "$BLOCK")" = 5 ] && ! grep -q "localhost\|localdomain\|printer.local\|-bad-\|bad_name\|nodot" <<< "$BLOCK"'
check M4 'grep -qx "state=on" "$WORK/state/status" && grep -qx "blocked=5" "$WORK/state/status" && grep -q "^updated=20" "$WORK/state/status" && [ "$(stat -c %a "$WORK/state/status")" = 644 ] && cmp -s "$WORK/state/hosts.before" "$WORK/orig"'
cp "$WORK/hosts" "$WORK/h1"; INO="$(stat -c %i "$WORK/hosts")"
OUT="$(H apply)"
check M5 'grep -q "(no change).$" <<< "$OUT" && cmp -s "$WORK/hosts" "$WORK/h1" && [ "$(stat -c %i "$WORK/hosts")" = "$INO" ]'
# You add your own line after our block, the lists change -> your line kept, block rebuilt, same file (inode)
echo "192.168.1.9 tv.home" >> "$WORK/hosts"; echo "new-scam.example" >> "$WORK/scam/urlhaus.list"
H apply >/dev/null
check M6 'grep -qx "192.168.1.9 tv.home" "$WORK/hosts" && [ "$(grep -c "^# >>> ForgeOS" "$WORK/hosts")" = 1 ] && grep -qx "0.0.0.0 new-scam.example" "$WORK/hosts" && [ "$(stat -c %i "$WORK/hosts")" = "$INO" ] && grep -qx "blocked=6" "$WORK/state/status"'

# N: unblock (typed as a link, with www.) -> it and everything under it; block again; bad names; remove; no permission
OUT="$(H allow "https://www.Fake-Bank.test/login?x=1")"; RC=$?
check N1 '[ "$RC" -eq 0 ] && [ "$OUT" = "Unblocked: fake-bank.test" ] && ! grep -q "fake-bank" "$WORK/hosts" && grep -qx "fake-bank.test" "$WORK/etc/guard-allow.list" && grep -qx "blocked=4" "$WORK/state/status"'
H allow fake-bank.test >/dev/null
check N2 '[ "$(grep -c "^fake-bank.test$" "$WORK/etc/guard-allow.list")" = 1 ] && [ "$(H unallow fake-bank.test)" = "Blocked again (if it is on the scam lists): fake-bank.test" ] && grep -qx ":: www.fake-bank.test" "$WORK/hosts" && grep -qx "# ForgeOS: never block these" "$WORK/etc/guard-allow.list"'
H allow "not a site" >/dev/null 2>&1; R1=$?; H allow "com" >/dev/null 2>&1; R2=$?; H allow >/dev/null 2>&1; R3=$?; H wipe >/dev/null 2>&1; R4=$?; H apply extra >/dev/null 2>&1; R5=$?
check N3 '[ "$R1$R2$R3$R4$R5" = 33333 ]'
echo "192.168.1.9 tv.home" >> "$WORK/orig"
OUT="$(H remove)"; RC=$?
check N4 '[ "$RC" -eq 0 ] && cmp -s "$WORK/hosts" "$WORK/orig" && grep -qx "state=off" "$WORK/state/status" && [ "$(H status | head -n 1)" = "state=off" ] && [ "$(H remove)" = "Website Guard is OFF: no websites are blocked by ForgeOS." ] && cmp -s "$WORK/hosts" "$WORK/orig"'
chmod a-w "$WORK/hosts"
OUT="$(H apply 2>&1)"; RC=$?
check N5 '{ [ "$(id -u)" = 0 ] || { [ "$RC" -eq 1 ] && grep -q "needs to run as the administrator" <<< "$OUT" && cmp -s "$WORK/hosts" "$WORK/orig"; }; }'
chmod u+w "$WORK/hosts"
# A huge list is cut at the most allowed (FORGEOS_GUARD_MOST)
seq 1 50 | sed 's/^/scam/; s/$/.example/' > "$WORK/scam/phishing.list"
FORGEOS_GUARD_MOST=20 H apply >/dev/null
check N6 '[ "$(grep -c "^0.0.0.0 " "$WORK/hosts")" = 20 ] && grep -qx "blocked=20" "$WORK/state/status"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

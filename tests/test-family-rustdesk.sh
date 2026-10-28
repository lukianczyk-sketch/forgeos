#!/usr/bin/env bash
# Tests for Family Mode (Job 13), cases H-K: RustDesk locked down in RustDesk2.toml [options] -
# other settings kept, old values back on "off", closed first while running, a broken file never
# written, odd quoting, and the reader for older Python matching tomllib.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-family-rustdesk.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/family-fakes.sh
. "$ROOT/tests/family-fakes.sh"
TOML="$WORK/rd/RustDesk2.toml"
# opt FILE KEY: one option from the [options] table (real TOML reader when Python has one).
opt() { python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); from familylib import rustdesk as r
print(r.options(open(sys.argv[2]).read()).get(sys.argv[3], "<none>"))' "$FORGEOS_FAMILY_LIB" "$1" "$2"; }
top() { python3 -B -c 'import sys
try:
    import tomllib
except ImportError:
    print("skip"); sys.exit()
d = tomllib.load(open(sys.argv[1], "rb")); print(d["rendezvous_server"], d["nat_type"], d["socks"]["proxy"])' "$1"; }

cat > "$TOML" <<'EOF'
rendezvous_server = 'rs-ny.rustdesk.com:21116'
nat_type = 1
serial = 0

[options]
approve-mode = 'password-click'
local-ip-addr = '192.168.1.20'
"enable-file-transfer" = "Y"
custom-note = "it's mine"

[socks]
proxy = 'none'
EOF
cp "$TOML" "$WORK/toml.before"
F helper set --name Brianna --rustdesk-id 987654321 >/dev/null

# H: on - safe options in, everything else kept; off - the old values back
F on >/dev/null
check H1 '[ "$(opt "$TOML" approve-mode)" = click ] && [ "$(opt "$TOML" verification-method)" = use-temporary-password ] && [ "$(opt "$TOML" id-whitelist)" = 987654321 ] && [ "$(opt "$TOML" enable-file-transfer)" = N ] && [ "$(opt "$TOML" auto-disconnect-timeout)" = 30 ]'
check H2 '[ "$(opt "$TOML" local-ip-addr)" = 192.168.1.20 ] && [ "$(opt "$TOML" custom-note)" = "it'"'"'s mine" ] && { T2="$(top "$TOML")"; [ "$T2" = skip ] || [ "$T2" = "rs-ny.rustdesk.com:21116 1 none" ]; } && [ "$(grep -c "enable-file-transfer" "$TOML")" -eq 1 ]'
F helper set --name Brianna --rustdesk-id 111222333 >/dev/null
check H3 '[ "$(opt "$TOML" id-whitelist)" = 111222333 ] && grep -q "^RUSTDESK${T}locked$" <<< "$(F status)"'
F off >/dev/null
check H4 '[ "$(opt "$TOML" approve-mode)" = password-click ] && [ "$(opt "$TOML" enable-file-transfer)" = Y ] && [ "$(opt "$TOML" id-whitelist)" = "<none>" ] && [ "$(opt "$TOML" verification-method)" = "<none>" ] && [ "$(opt "$TOML" custom-note)" = "it'"'"'s mine" ] && grep -q "^RUSTDESK${T}open$" <<< "$(F status)"'
# Every other line comes back as it was (a key we set back may come back written the plain way).
check H5 'diff <(grep -v "enable-file-transfer" "$WORK/toml.before" | sort) <(grep -v "enable-file-transfer" "$TOML" | sort) >/dev/null'

# I: RustDesk running - closed before the file is written; won't close - file left alone, said so
echo com.rustdesk.RustDesk > "$WORK/running"; : > "$WORK/calls.log"
F on >/dev/null
check I1 '[ ! -s "$WORK/running" ] && grep -n "flatpak kill com.rustdesk.RustDesk" "$WORK/calls.log" >/dev/null && [ "$(opt "$TOML" approve-mode)" = click ]'
F off >/dev/null; cp "$TOML" "$WORK/toml.mid"
echo com.rustdesk.RustDesk > "$WORK/running"
OUT="$(FAKE_NO_KILL=1 F on)"; RC=$?
check I2 '[ "$RC" -eq 1 ] && grep -q "^Problem: RustDesk could not be locked down" <<< "$OUT" && cmp -s "$TOML" "$WORK/toml.mid"'
: > "$WORK/running"; F off >/dev/null

# J: a broken settings file is never written (RustDesk could not read it)
printf '[options\napprove-mode = click\n' > "$TOML"; cp "$TOML" "$WORK/toml.bad"
OUT="$(F on)"; RC=$?
check J '[ "$RC" -eq 1 ] && grep -q "RustDesk could not be locked down" <<< "$OUT" && cmp -s "$TOML" "$WORK/toml.bad" && grep -q "^RUSTDESK${T}open$" <<< "$(F status)"'
F off >/dev/null

# K: the simple reader (Python without tomllib) reads the same as tomllib; quoting both ways
printf '%s\n' "a = 1" "[options]" "approve-mode = 'click'" "'whitelist' = \"10.0.0.1,10.0.0.2\"" 'note = "say \"hi\""' "[x]" "y = 'z'" > "$WORK/k.toml"
K1="$(python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); from familylib import rustdesk as r
t = open(sys.argv[2]).read(); simple = r.tomllib is None
r.tomllib = None; a = r.options(t); print(a)
print(r.options("[options]\nbroken line") is None and r.options("[options\na = 1") is None)
print(r.quote("it'"'"'s") == "\"it'"'"'s\"", r.quote("plain") == "'"'"'plain'"'"'")' "$FORGEOS_FAMILY_LIB" "$WORK/k.toml")"
check K '[ "$K1" = "{'"'"'approve-mode'"'"': '"'"'click'"'"', '"'"'whitelist'"'"': '"'"'10.0.0.1,10.0.0.2'"'"', '"'"'note'"'"': '"'"'say \"hi\"'"'"'}
True
True True" ]'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1

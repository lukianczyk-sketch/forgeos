#!/usr/bin/env bash
# Tests for Always-On Guard (Job 13b), case Q: the build files - run bits, services, the virus checker's
# settings (a real clamd accepts them), menu entry, the new package, Family Mode's guard list, the CI step,
# Python that parses, small LF-only files (Cline limit).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-guard-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'stop_clamd; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/guard-fakes.sh
. "$ROOT/tests/guard-fakes.sh"
SYS="$ROOT/files/system"; U="$SYS/usr/lib/systemd/user"; S="$SYS/usr/lib/systemd/system"; LIB="$FORGEOS_GUARD_LIB/guardlib"
SETUP="$ROOT/files/scripts/forgeos-setup.sh"; A="$SYS/usr/share/applications"; M="$ROOT/recipes/common-modules.yml"
CONF="$SYS/etc/clamd.d/forgeos.conf"

check Q1 'grep -q "^chmod 0755 .* /usr/libexec/forgeos-family-call /usr/bin/forgeos-guard /usr/bin/forgeos-guard-gui /usr/libexec/forgeos-guard-hosts\( \|$\)" "$SETUP" && grep -qx "systemctl enable forgeos-clamd.service forgeos-guard-hosts.service forgeos-guard-hosts.path" "$SETUP" && grep -qx "systemctl --global enable forgeos-guard.service" "$SETUP"'
check Q2 'grep -qx "ExecStart=/usr/bin/forgeos-guard watch" "$U/forgeos-guard.service" && grep -qx "WantedBy=graphical-session.target" "$U/forgeos-guard.service" && grep -qx "Restart=on-failure" "$U/forgeos-guard.service"'
check Q3 'grep -qx "ExecStart=/usr/bin/clamd --config-file=/etc/clamd.d/forgeos.conf" "$S/forgeos-clamd.service" && grep -qx "ConditionMemory=>=5500M" "$S/forgeos-clamd.service" && grep -qx "DynamicUser=yes" "$S/forgeos-clamd.service" && grep -qx "RuntimeDirectory=clamd.forgeos" "$S/forgeos-clamd.service" && grep -qx "LocalSocket /run/clamd.forgeos/clamd.sock" "$CONF" && grep -qx "Foreground yes" "$CONF" && grep -qx "WantedBy=multi-user.target" "$S/forgeos-clamd.service"'
check Q4 'grep -qx "ExecStart=/usr/libexec/forgeos-guard-hosts apply" "$S/forgeos-guard-hosts.service" && grep -qx "ReadWritePaths=/etc/hosts" "$S/forgeos-guard-hosts.service" && grep -qx "StateDirectory=forgeos-guard" "$S/forgeos-guard-hosts.service" && grep -qx "Unit=forgeos-guard-hosts.service" "$S/forgeos-guard-hosts.path" && (for l in phishing urlhaus; do grep -qx "PathChanged=/var/lib/forgeos-scamshield/$l.list" "$S/forgeos-guard-hosts.path" || exit 1; done) && grep -qx "PathChanged=/etc/forgeos/guard-allow.list" "$S/forgeos-guard-hosts.path" && [ -f "$SYS/etc/forgeos/guard-allow.list" ]'
# the real clamd accepts our settings (only the socket and list folder moved into the test folder)
if [ -x "$CLAMD" ]; then
  sed -e "s|^LocalSocket .*|LocalSocket $WORK/cl/run/clamd.sock|" -e "s|^DatabaseDirectory .*|DatabaseDirectory $WORK/cl/db|" \
    -e "s|^Foreground yes|Foreground no|" -e "s|^LogSyslog yes|LogFile $WORK/cl/clamd.log|" "$CONF" > "$WORK/cl/clamd.conf"
  echo "PidFile $WORK/cl/run/clamd.pid" >> "$WORK/cl/clamd.conf"
  if start_clamd; then virus "$WORK/v.txt"; OUT="$(G scan "$WORK/v.txt")"; fi
  check Q5 'grep -q "^VIRUS${T}$WORK/v.txt${T}ForgeOS.Test.Eicar.UNOFFICIAL" <<< "${OUT:-}" && grep -q "^clamdscan" "$WORK/calls.log"'
else
  echo "SKIP Q5 (clamd is not installed: apt-get install clamav-daemon clamdscan)"
fi
check Q6 'grep -qx "Exec=/usr/bin/forgeos-guard-gui" "$A/forgeos-guard.desktop" && grep -qx "Name=Always-On Guard" "$A/forgeos-guard.desktop" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A/forgeos-guard.desktop"; }'
check Q7 'grep -q "^        - clamd  *# Always-On Guard" "$M" && (for p in clamav clamav-freshclam libnotify python3; do grep -q "^        - $p\( \|$\)" "$M" || exit 1; done) && grep -q "^          - org.mozilla.thunderbird " "$M"'
check Q8 'grep -q "(\"forgeos-guard.service\", \"Always-On Guard" "$ROOT/files/system/usr/lib/forgeos-family/familylib/guards.py" && grep -q "(\"forgeos-guard-hosts.path\", \"Website Guard" "$ROOT/files/system/usr/lib/forgeos-family/familylib/guards.py"'
check Q9 'python3 -c "import ast,sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]" "$ENGINE" "$LIB"/*.py && [ "$(head -n 1 "$ENGINE")" = "#!/usr/bin/python3" ] && [ ! -e "$LIB/__pycache__" ] && grep -q "sys.dont_write_bytecode = True" "$ENGINE"'
check Q10 '(for f in "$ENGINE" "$GUI" "$HOSTS_HELPER" "$LIB"/*.py "$CONF" "$A"/forgeos-guard.desktop "$U"/forgeos-guard.service "$S"/forgeos-clamd.service "$S"/forgeos-guard-hosts.* "$ROOT"/tests/*guard*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  too big, CRLF, tab or no last newline: $f"; exit 1; }; done)'
check Q11 '(for t in test-guard test-guard-more test-guard-watch test-guard-mail test-guard-inbox test-guard-hosts test-guard-gui test-guard-files; do grep -q "bash tests/$t.sh ." "$ROOT/.github/workflows/tests.yml" || exit 1; done) && grep -q "clamav-daemon clamdscan" "$ROOT/.github/workflows/tests.yml"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

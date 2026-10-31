# shellcheck shell=bash
# Fake tools + a REAL ClamAV for the Always-On Guard tests (Job 13b). Sourced by tests/test-guard*.sh.
# Fakes log their name and arguments to $WORK/calls.log. ClamAV is real: a test-only signature for the
# harmless EICAR test text (no internet virus list needed). start_clamd starts a real clamd in $WORK.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home/Downloads" "$WORK/home/Desktop" "$WORK/cl/db" "$WORK/cl/run"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
REAL_CLAMSCAN="$(command -v clamscan || echo clamscan)"; REAL_CLAMDSCAN="$(command -v clamdscan || echo clamdscan)"
export WORK HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/cfg" XDG_STATE_HOME="$WORK/state" XDG_DATA_HOME="$WORK/data" PATH="$WORK/bin:$PATH"
export FORGEOS_GUARD_LIB="$ROOT/files/system/usr/lib/forgeos-guard" FORGEOS_GUARD_CLAMD_CONF="$WORK/cl/clamd.conf"
export FORGEOS_GUARD_CLAMSCAN_DB="$WORK/cl/db" FORGEOS_GUARD_HOSTS_STATUS="$WORK/hosts-status" FORGEOS_GUARD_TB="$WORK/tb"
export FORGEOS_GUARD_SCAMSHIELD="$WORK/bin/forgeos-scamshield" FORGEOS_GUARD_SETTLE=1 FORGEOS_GUARD_QUIET=60
ENGINE="$ROOT/files/system/usr/bin/forgeos-guard"
GUI="$ROOT/files/system/usr/bin/forgeos-guard-gui"
HOSTS_HELPER="$ROOT/files/system/usr/libexec/forgeos-guard-hosts"
G() { python3 -B "$ENGINE" "$@"; }
T=$'\t'  # a tab, for checking the tab-separated lines
QD="$WORK/data/forgeos/guard/quarantine"
EV="$WORK/state/forgeos/guard/events.log"
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$ENGINE" > "$WORK/bin/fg-engine"
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$GUI" > "$WORK/bin/fg-gui"
chmod +x "$WORK/bin/fg-engine" "$WORK/bin/fg-gui"
export FORGEOS_GUARD_ENGINE="$WORK/bin/fg-engine" FORGEOS_GUARD_GUI="$WORK/bin/fg-gui"

# The EICAR test text: every virus checker treats it as a virus on purpose. It is harmless.
EICAR='X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
printf 'ForgeOS.Test.Eicar:0:*:%s\n' "$(printf '%s' "$EICAR" | od -An -tx1 | tr -d ' \n')" > "$WORK/cl/db/test.ndb"
virus() { printf '%s' "$EICAR" > "$1"; }
cat > "$WORK/cl/clamd.conf" <<EOF
LocalSocket $WORK/cl/run/clamd.sock
LocalSocketMode 666
DatabaseDirectory $WORK/cl/db
Foreground no
PidFile $WORK/cl/run/clamd.pid
TemporaryDirectory $WORK/cl/run
ConcurrentDatabaseReload no
StreamMaxLength 400M
MaxFileSize 400M
MaxScanSize 1000M
EOF
CLAMD="$(command -v clamd || echo /usr/sbin/clamd)"
start_clamd() { # 0 = a real clamd is answering on the test socket
  [ -x "$CLAMD" ] && command -v clamdscan >/dev/null 2>&1 || return 1
  "$CLAMD" --config-file="$WORK/cl/clamd.conf" >/dev/null 2>&1 || return 1
  local i
  for i in $(seq 1 60); do [ -S "$WORK/cl/run/clamd.sock" ] && return 0; sleep 0.5; done
  return 1
}
stop_clamd() { [ -s "$WORK/cl/run/clamd.pid" ] && kill "$(cat "$WORK/cl/run/clamd.pid")" 2>/dev/null; rm -f "$WORK/cl/run/clamd.sock"; sleep 0.5; }

# Pop-ups and warning windows start in the background: wait (up to 5 s) until calls.log has N lines matching $1.
calls_wait() { local i; for i in $(seq 1 20); do [ "$(grep -c -- "$1" "$WORK/calls.log" 2>/dev/null)" -ge "${2:-1}" ] && return 0; sleep 0.25; done; return 1; }
# Desktop tools. notify-send: with --wait it answers $WORK/click (e.g. "why") if that file exists.
fake notify-send 'for a in "$@"; do [ "$a" = --wait ] && [ -f "$WORK/click" ] && cat "$WORK/click"; done; exit 0'
fake kdialog 'exit 0'
# The real ClamAV programs, logged (so the tests can see which one did the check).
fake clamscan "exec \"$REAL_CLAMSCAN\" \"\$@\""
fake clamdscan "exec \"$REAL_CLAMDSCAN\" \"\$@\""
fake xdg-user-dir 'case "$1" in DOWNLOAD) echo "$HOME/Downloads" ;; DESKTOP) echo "$HOME/Desktop" ;; *) echo "$HOME" ;; esac'
fake systemctl 'case "$*" in *is-active*) [ -f "$WORK/active" ] && { echo active; exit 0; }; echo inactive; exit 3 ;; esac; exit 0'
fake pkexec 'exec "$@"'
# Scam Shield: SCAMWORD = scam (2); CAREWORD = be careful (1) by the rules, then the AI says scam if AI-SCAM is in it.
fake forgeos-scamshield 'f="${*: -1}"; ai=1; [ "$2" = --no-ai ] && ai=0
cp "$f" "$WORK/last-checked.txt"
if grep -q SCAMWORD "$f"; then echo "Looks like a SCAM."; echo "- It asks for gift cards."; exit 2; fi
if grep -q CAREWORD "$f"; then
  [ "$ai" = 0 ] && { echo "Be careful."; exit 1; }
  grep -q AI-SCAM "$f" && { echo "Looks like a SCAM (the private AI agrees)."; exit 2; }
  echo "No scam signs found."; exit 0
fi
echo "No scam signs found."; exit 0'

# One email as raw bytes: mkmail FROM SUBJECT BODY [ATTACHMENT-NAME ATTACHMENT-FILE]
mkmail() {
  python3 -B - "$@" <<'PY'
import sys
from email.message import EmailMessage
m = EmailMessage()
m["From"], m["To"], m["Subject"] = sys.argv[1], "me@example.com", sys.argv[2]
m["Message-ID"] = "<%s@test>" % abs(hash(sys.argv[2] + sys.argv[3]))
m.set_content(sys.argv[3])
if len(sys.argv) > 5:
    m.add_attachment(open(sys.argv[5], "rb").read(), maintype="application", subtype="octet-stream", filename=sys.argv[4])
sys.stdout.write(m.as_string())
PY
}
# Add an email to an mbox file the way Thunderbird does ("From - date" line first).
to_mbox() { { printf 'From - Wed Oct 28 10:00:00 2026\n'; mkmail "$@"; printf '\n'; } >> "$MBOX"; }

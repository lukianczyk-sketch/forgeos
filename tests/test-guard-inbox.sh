#!/usr/bin/env bash
# Tests for Always-On Guard (Job 13b), cases J-L: Email Guard watching Thunderbird's real mail files -
# only NEW mail, Junk skipped, pop-ups held back, guard off, a folder made later, a tidied (compacted)
# mailbox, a Maildir account; Thunderbird's files are never changed.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-guard-inbox.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'kill "$WPID" 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/guard-fakes.sh
. "$ROOT/tests/guard-fakes.sh"
WPID=""
command -v clamscan >/dev/null 2>&1 || { echo "FAIL clamscan is needed (apt-get install clamav)"; exit 1; }
wait_for() { local i; for i in $(seq 1 $((${3:-30} * 4))); do grep -q -- "$2" "$1" 2>/dev/null && return 0; sleep 0.25; done; return 1; }

# J: watching Thunderbird (Flatpak-style profile): old mail is not checked again, new mail is; Junk skipped;
# a second warning within a minute is held back and counted into the next one
P="$WORK/tb/abc123.default-release"; IMAP="$P/ImapMail/imap.example.com"; mkdir -p "$IMAP/INBOX.sbd" "$P/Mail/Local Folders"
MBOX="$IMAP/INBOX"; to_mbox "Old <old@example.com>" "Old scam" "SCAMWORD old"
JUNK="$IMAP/Junk"; : > "$JUNK"; : > "$IMAP/INBOX.msf"; : > "$WORK/calls.log"
echo "Thunderbird notes, not an email" > "$IMAP/notes"
G watch --for 40 > "$WORK/watch.out" 2>&1 & WPID=$!; sleep 2
to_mbox "Crook <crook@example.net>" "Prize waiting" "SCAMWORD claim now"
MBOX="$JUNK" to_mbox "Junk <j@example.net>" "Junk scam" "SCAMWORD junk"
wait_for "$EV" "Prize waiting"
check J1 'grep -q "${T}scam${T}email${T}crook@example.net${T}Prize waiting${T}imap.example.com${T}" "$EV" && ! grep -q "Old scam\|Junk scam" "$EV" && ! grep -q "Junk scam" "$WORK/last-checked.txt"'
to_mbox "Crook2 <c2@example.net>" "Second prize" "SCAMWORD again"; wait_for "$EV" "Second prize"
to_mbox "Crook3 <c3@example.net>" "Third prize" "SCAMWORD again"; wait_for "$EV" "Third prize"
calls_wait "^notify-send .*Scam warning"; sleep 1
check J2 '[ "$(grep -c "^notify-send" "$WORK/calls.log")" = 1 ] && grep -q "Scam warning" "$WORK/calls.log" && [ "$(grep -c "${T}scam${T}email${T}" "$EV")" = 3 ]'
# K: Email Guard OFF - new mail is passed over (and not checked later); a sub-folder made later is watched
G off email >/dev/null; to_mbox "Off <off@example.net>" "While off" "SCAMWORD off"; sleep 4
G on email >/dev/null; mkdir -p "$IMAP/Family.sbd"; sleep 1; MBOX="$IMAP/Family.sbd/Aunt"; : > "$MBOX"; sleep 2
to_mbox "Aunt <aunt@example.org>" "Family gift card" "SCAMWORD aunt"; wait_for "$EV" "Family gift card"
check K1 '! grep -q "While off" "$EV" && grep -q "${T}aunt@example.org${T}Family gift card${T}Family.sbd${T}" "$EV"'
# a mailbox that shows up already full (a new account copying old mail) is not checked; nor is a file that is not mail
MBOX="$WORK/old-box"; to_mbox "Old2 <o2@example.net>" "Old copied scam" "SCAMWORD old copy"; mv "$MBOX" "$IMAP/Archive"
echo "SCAMWORD in a note" >> "$IMAP/notes"; sleep 4
check K2 '! grep -q "Old copied scam\|in a note" "$EV" && ! grep -q "in a note" "$WORK/last-checked.txt"'
# L: Thunderbird tidies (compacts) INBOX: same old mail rewritten into a new, smaller file + one new email
MBOX="$IMAP/INBOX"; python3 -B - "$MBOX" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
parts = data.split(b"\nFrom - ")
open(sys.argv[1] + ".tmp", "wb").write(b"\nFrom - ".join(parts[:1] + parts[2:]))
PY
mv "$MBOX.tmp" "$MBOX"; to_mbox "New <new@example.net>" "After tidy" "SCAMWORD new"
wait_for "$EV" "After tidy"
check L1 '[ "$(grep -c "Second prize\|Third prize\|Prize waiting" "$EV")" = 3 ] && grep -q "${T}new@example.net${T}After tidy${T}" "$EV"'
# Maildir account (one file per email)
mkdir -p "$P/Mail/maildir.example/Inbox/cur" "$P/Mail/maildir.example/Inbox/new"; sleep 1.5
mkmail "MD <md@example.org>" "Maildir scam" "SCAMWORD maildir" > "$P/Mail/maildir.example/Inbox/new/123.eml"
wait_for "$EV" "Maildir scam"
check L2 'grep -q "${T}md@example.org${T}Maildir scam${T}" "$EV" && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert len(d[\"seen\"])>=5" "$WORK/state/forgeos/guard/mail.json"'
wait "$WPID" 2>/dev/null; WPID=""
check L3 '[ "$(find "$WORK/tb" -type f | grep -vc "/INBOX$\|/INBOX.msf$\|/Junk$\|/Aunt$\|/123.eml$\|/notes$\|/Archive$")" = 0 ] && grep -q "watching [0-9]* folders" "$WORK/watch.out"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi

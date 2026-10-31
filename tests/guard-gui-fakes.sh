# shellcheck shell=bash
# The Always-On Guard window tests' fake kdialog and a test Website Guard (Job 13b). Sourced by
# tests/test-guard-gui.sh after tests/guard-fakes.sh.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
# kdialog: menus answer from $WORK/menu (none left = Cancel), Yes/No from $WORK/yes (none left = yes),
# typed answers from $WORK/input, the picked file from $WORK/file. What it shows is logged to $WORK/shown.
next() { l="$(head -n 1 "$WORK/$1" 2>/dev/null)"; sed -i 1d "$WORK/$1" 2>/dev/null; }
fake kdialog "$(declare -f next)"'
for a in "$@"; do case "$a" in
  --menu) printf "%s\n" "$@" >> "$WORK/shown"; l=""; next menu; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --yesno|--warningyesno) printf "%s\n" "$@" >> "$WORK/shown"; l=""; next yes; exit "${l:-0}" ;;
  --inputbox) printf "%s\n" "$@" >> "$WORK/shown"; l=""; next input; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --getopenfilename) l=""; next file; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --textbox) for b in "$@"; do [ -f "$b" ] && cat "$b" >> "$WORK/shown"; done; exit 0 ;;
  --msgbox|--sorry) printf "%s\n" "$@" >> "$WORK/shown"; exit 0 ;;
esac; done; exit 0'
W() { : > "$WORK/shown"; printf '%s\n' "$@" > "$WORK/menu"; bash "$GUI"; }
S() { cat "$WORK/shown"; }
D="$HOME/Downloads"
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$HOSTS_HELPER" > "$WORK/bin/fg-hosts"; chmod +x "$WORK/bin/fg-hosts"
export FORGEOS_GUARD_HOSTS_HELPER="$WORK/bin/fg-hosts"  # git keeps no exec bits
export FORGEOS_HOSTS="$WORK/hosts" FORGEOS_SCAM_DIR="$WORK/scam" FORGEOS_GUARD_ALLOW="$WORK/allow" FORGEOS_GUARD_STATE="$WORK/hstate"
mkdir -p "$WORK/scam"; echo "127.0.0.1 localhost" > "$WORK/hosts"; printf 'fake-bank.test\nevil.example\n' > "$WORK/scam/phishing.list"
bash "$FORGEOS_GUARD_HOSTS_HELPER" apply >/dev/null; cp "$WORK/hstate/status" "$WORK/hosts-status"


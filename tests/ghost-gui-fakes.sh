# shellcheck shell=bash
# Fake window tools for the GhostFinder window tests (Job 12). Sourced after tests/ghost-fakes.sh.
# shellcheck disable=SC2016  # the fake scripts are written out single-quoted on purpose
fake pw-play 'exit 0'
fake systemd-inhibit 'exit 0'
fake systemctl '[ "$2" = is-enabled ] && { cat "$WORK/watch-state" 2>/dev/null || echo disabled; exit 0; }
[ "$2" = enable ] && echo enabled > "$WORK/watch-state"; [ "$2" = disable ] && echo disabled > "$WORK/watch-state"; exit 0'
# dbus-send: wasCancelled answers from $WORK/cancel (one line per question; "yes" = Cancel was pressed).
fake dbus-send 'case "$*" in *wasCancelled*) l="$(head -n 1 "$WORK/cancel" 2>/dev/null)"; sed -i 1d "$WORK/cancel" 2>/dev/null
  [ "$l" = yes ] && echo "   boolean true" || echo "   boolean false" ;; esac; exit 0'
# kdialog: menus answer from $WORK/menu (one per line; none left = Cancel), Yes/No from $WORK/yes
# (one per line; none left = yes). What it shows is logged to $WORK/shown.
fake kdialog 'for a in "$@"; do case "$a" in
  --menu) printf "%s\n" "$@" >> "$WORK/shown"; l="$(head -n 1 "$WORK/menu" 2>/dev/null)"; sed -i 1d "$WORK/menu" 2>/dev/null; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --yesno) printf "%s\n" "$@" >> "$WORK/shown"; l="$(head -n 1 "$WORK/yes" 2>/dev/null)"; sed -i 1d "$WORK/yes" 2>/dev/null; exit "${l:-0}" ;;
  --textbox) for b in "$@"; do [ -f "$b" ] && cat "$b" >> "$WORK/shown"; done; exit 0 ;;
  --msgbox|--error|--sorry) printf "%s\n" "$@" >> "$WORK/shown"; exit 0 ;;
  --progressbar) echo "org.fake /bar"; exit 0 ;;
esac; done; exit 0'

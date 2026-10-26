# shellcheck shell=bash
# Fake tools and fake program files for the Will It Run? tests (Job 10). Sourced by tests/test-willitrun*.sh.
# Every fake writes its name and arguments to $WORK/calls.log. Answers come from FAKE_* settings.
# shellcheck disable=SC2016  # the fake scripts are written out single-quoted on purpose
mkdir -p "$WORK/bin" "$WORK/home/Downloads" "$WORK/cfg/forgeos" "$WORK/wir" "$WORK/scam" "$WORK/games/Rust" "$WORK/games/Shooter/EasyAntiCheat"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }

# Installed Flatpak apps are listed in $WORK/installed (one app ID per line).
fake flatpak '[ "$1" = info ] && { grep -qx "$2" "$WORK/installed" 2>/dev/null; exit $?; }; exit 0'
fake setsid 'exit 0'
fake konsole 'exit 0'
fake steam 'exit 0'
fake sleep 'exit 0'
fake waydroid 'case "$1" in
  status) printf "Session:\t%s\n" "${FAKE_WAYDROID:-STOPPED}" ;;
  app) [ -n "${FAKE_WAYDROID_ERR:-}" ] && echo "[12:00:00] WayDroid session is stopped" ;;
esac; exit 0'
fake dbus-send 'exit 0'
# Fake virus check: FAKE_VIRUS = name of the virus found, FAKE_SCAN_RC = exit code when nothing is found.
fake clamscan 'last=""; for a in "$@"; do last="$a"; done
[ -n "${FAKE_VIRUS:-}" ] && { echo "$last: $FAKE_VIRUS FOUND"; exit 1; }; exit "${FAKE_SCAN_RC:-0}"'
# Fake download website: FAKE_ORIGIN = the web address the browser saved on the file.
fake getfattr '[ -n "${FAKE_ORIGIN:-}" ] || exit 1; printf "%s" "$FAKE_ORIGIN"'

# Fake curl: Ollama answers from FAKE_TAGS / FAKE_AI and keeps the request in $WORK/body.json;
# the anti-cheat list download copies $WORK/games.json.
fake curl 'last=""; for a in "$@"; do last="$a"; done
case "$last" in
  */api/tags) [ -n "${FAKE_TAGS:-}" ] || exit 7; printf "%s" "$FAKE_TAGS" ;;
  */api/chat) cat > "$WORK/body.json"; [ -n "${FAKE_AI:-}" ] || exit 28
    jq -n --arg c "$FAKE_AI" "{message: {role: \"assistant\", content: \$c}}" ;;
  *games.json) [ -f "$WORK/games.json" ] || exit 22
    o=""; p=""; for a in "$@"; do [ "$p" = -o ] && o="$a"; p="$a"; done; cp "$WORK/games.json" "$o" ;;
  *) exit 7 ;;
esac'

# Fake kdialog: menus pop answers from $WORK/menu (one per line; none left = Cancel), the name box
# answers FAKE_NAME, the file picker FAKE_FILE, Yes/No answers FAKE_YES (0 = yes). Messages go to $WORK/shown.
fake kdialog 'for a in "$@"; do case "$a" in
  --menu) l="$(head -n 1 "$WORK/menu" 2>/dev/null)"; sed -i 1d "$WORK/menu" 2>/dev/null; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --inputbox) echo "${FAKE_NAME:-}"; exit 0 ;;
  --getopenfilename) [ -n "${FAKE_FILE:-}" ] || exit 1; echo "$FAKE_FILE"; exit 0 ;;
  --yesno) echo "$*" >> "$WORK/shown"; exit "${FAKE_YES:-0}" ;;
  --progressbar) echo "org.fake /bar"; exit 0 ;;
  --msgbox|--sorry|--error) echo "$*" >> "$WORK/shown"; exit 0 ;;
esac; done; exit 0'

# mkpe <file> <machine hex> <subsystem> <magic 10b/20b> <.NET 0/1> <flags hex> [text inside]: a tiny fake Windows program.
mkpe() {
  perl -e 'my ($f, $m, $s, $mg, $net, $ch, $x) = @ARGV; my $b = pack("x512");
    substr($b, 0, 2) = "MZ"; substr($b, 60, 4) = pack("V", 64); substr($b, 64, 4) = "PE" . pack("x2");
    substr($b, 68, 2) = pack("v", hex $m); substr($b, 86, 2) = pack("v", hex $ch);
    substr($b, 88, 2) = pack("v", hex $mg); substr($b, 156, 2) = pack("v", $s);
    my $dd = 88 + ($mg eq "20b" ? 112 : 96); substr($b, $dd + 112, 4) = pack("V", $net ? 8192 : 0);
    open(my $o, ">", $f) or die; print $o $b . (defined $x ? $x : ""); close $o;' "$@"
}

printf 'Halo: The Master Chief Collection|Supported|Easy Anti-Cheat\nFortnite|Denied|Easy Anti-Cheat\nRust|Denied|Easy Anti-Cheat, VAC\nPUBG: Battlegrounds|Broken|BattlEye\nElden Ring|Running|Easy Anti-Cheat\n' > "$WORK/wir/anticheat.list"
: > "$WORK/installed"
printf 'evil-downloads.com\nfree-games.example\n' > "$WORK/scam/phishing.list"

export WORK HOME="$WORK/home" PATH="$WORK/bin:$PATH" XDG_CONFIG_HOME="$WORK/cfg"
export FORGEOS_WIR_LIBDIR="$ROOT/files/system/usr/libexec" FORGEOS_WIR_LISTS="$ROOT/files/system/usr/share/forgeos/willitrun"
export FORGEOS_WIR_DIR="$WORK/wir" FORGEOS_WIR_WAYDROID_CFG="$WORK/waydroid.cfg" FORGEOS_WIR_WAIT=4
export FORGEOS_SCAM_DIR="$WORK/scam"
WR="$ROOT/files/system/usr/bin/forgeos-willitrun"
# git keeps the scripts without the "run" bit, so the window calls the engine through bash.
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$WR" > "$WORK/engine"
chmod +x "$WORK/engine"
export FORGEOS_WIR_ENGINE="$WORK/engine"

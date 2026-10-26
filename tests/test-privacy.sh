#!/usr/bin/env bash
# Tests for the Privacy Report (Job 7) with fake pw-dump, pactl, flatpak, kdialog + a fake /proc.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-privacy.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
U="$ROOT/files/system/usr"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# --- PipeWire graph: Zoom records the mic, Firefox uses the camera, OBS shares the screen.
# Not counted: a speaker-sound recorder, a volume meter, a paused stream, the taskbar thumbnails.
cat > "$WORK/pw.json" <<'EOF'
[
 {"id":40,"type":"PipeWire:Interface:Client","info":{"props":{"application.name":"ZOOM VoiceEngine","pipewire.access.portal.app_id":"us.zoom.Zoom"}}},
 {"id":41,"type":"PipeWire:Interface:Client","info":{"props":{"application.name":"Firefox","pipewire.access.portal.app_id":"org.mozilla.firefox"}}},
 {"id":42,"type":"PipeWire:Interface:Client","info":{"props":{"application.name":"OBS Studio","application.process.binary":"obs"}}},
 {"id":43,"type":"PipeWire:Interface:Client","info":{"props":{"application.name":"Plasma","application.process.binary":"plasmashell"}}},
 {"id":10,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Audio/Source","node.name":"alsa_input.mic"}}},
 {"id":11,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Audio/Sink","node.name":"alsa_output.spk"}}},
 {"id":12,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Video/Source","device.api":"v4l2","node.name":"v4l2_input.cam"}}},
 {"id":13,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Stream/Output/Video","media.name":"kwin-screencast-1","node.name":"kwin_wayland"}}},
 {"id":20,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Stream/Input/Audio","client.id":40,"application.name":"ZOOM VoiceEngine","pipewire.access.portal.app_id":"us.zoom.Zoom"}}},
 {"id":21,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Stream/Input/Audio","client.id":42,"application.name":"OBS Studio","application.process.binary":"obs"}}},
 {"id":22,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Stream/Input/Audio","client.id":41,"stream.monitor":true,"application.name":"Firefox"}}},
 {"id":23,"type":"PipeWire:Interface:Node","info":{"state":"suspended","props":{"media.class":"Stream/Input/Audio","client.id":41,"application.name":"Firefox"}}},
 {"id":24,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Stream/Input/Video","client.id":41,"application.name":"Firefox"}}},
 {"id":25,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Stream/Input/Video","client.id":42,"application.name":"OBS Studio","application.process.binary":"obs"}}},
 {"id":26,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Stream/Input/Video","client.id":43,"application.process.binary":"plasmashell"}}},
 {"id":30,"type":"PipeWire:Interface:Link","info":{"output-node-id":10,"input-node-id":20,"state":"active"}},
 {"id":31,"type":"PipeWire:Interface:Link","info":{"output-node-id":10,"input-node-id":20,"state":"active"}},
 {"id":32,"type":"PipeWire:Interface:Link","info":{"output-node-id":11,"input-node-id":21,"state":"active"}},
 {"id":33,"type":"PipeWire:Interface:Link","info":{"output-node-id":10,"input-node-id":22,"state":"active"}},
 {"id":34,"type":"PipeWire:Interface:Link","info":{"output-node-id":10,"input-node-id":23,"state":"paused"}},
 {"id":35,"type":"PipeWire:Interface:Link","info":{"output-node-id":12,"input-node-id":24,"state":"active"}},
 {"id":36,"type":"PipeWire:Interface:Link","info":{"output-node-id":13,"input-node-id":25,"state":"active"}},
 {"id":37,"type":"PipeWire:Interface:Link","info":{"output-node-id":13,"input-node-id":26,"state":"active"}}
]
EOF
# The same graph after Zoom stopped recording.
jq 'map(select(.id != 30 and .id != 31))' "$WORK/pw.json" > "$WORK/pw2.json"

# --- fake /proc: Skype (a Flatpak) opened the camera directly; PipeWire's own handle is ignored ---
PR="$WORK/proc"
mkdir -p "$PR/4242/fd" "$PR/77/fd" "$PR/99/fd"
ln -s /dev/video0 "$PR/4242/fd/3"; echo skypeforlinux > "$PR/4242/comm"
echo "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-com.skype.Client-12345.scope" > "$PR/4242/cgroup"
ln -s /dev/video0 "$PR/77/fd/5"; echo pipewire > "$PR/77/comm"; echo "0::/" > "$PR/77/cgroup"
ln -s /dev/null "$PR/99/fd/1"; echo bash > "$PR/99/comm"
mkdir -p "$PR/4343"; printf '%s\n' '0::/user.slice/app.slice/app-flatpak-io.github.cam\x2dtool-777.scope' > "$PR/4343/cgroup"

# --- menu names of Flatpak apps ---
APPS="$WORK/apps"; mkdir -p "$APPS"
for a in "us.zoom.Zoom:Zoom" "org.mozilla.firefox:Firefox" "com.skype.Client:Skype"; do
  printf '[Desktop Entry]\nName=%s\n' "${a#*:}" > "$APPS/${a%%:*}.desktop"
done

# --- fake tools ---
B="$WORK/bin"; mkdir -p "$B"
LOG="$WORK/log"; : > "$LOG"
mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$B/$1"; chmod +x "$B/$1"; }
mk pw-dump 'cat "${FAKE_PW:-$WORK/pw.json}"'
mk notify-send 'echo "notify $*" >> "$LOG"'
mk pactl 'case "$*" in
"-f json list source-outputs") cat "$WORK/so.json" 2>/dev/null || echo "[]" ;;
set-source-output-mute*) echo "pactl mute $2 $3" >> "$LOG" ;;
subscribe) echo "pactl subscribe" >> "$LOG"; exec sleep 30 ;;
esac'
# flatpak apps: perm_<id> holds "flatpak info --show-permissions" output
mk flatpak 'case "$1" in
info) if [ "$2" = --show-permissions ]; then cat "$WORK/perm_$3" 2>/dev/null; else [ -f "$WORK/perm_$2" ]; fi ;;
list) printf "us.zoom.Zoom\tzoom\norg.mozilla.firefox\tFirefox\ncom.skype.Client\tSkype\nus.zoom.Zoom\tzoom\n" ;;
permissions) [ "$2" = devices ] && printf "devices\tcamera\torg.mozilla.firefox\tyes\t0x00\ndevices\tcamera\tus.zoom.Zoom\tno\t0x00\n"
  [ "$2" = location ] && printf "location\tlocation\tcom.skype.Client\tEXACT,1700000000\t\n" ;;
*) echo "flatpak $*" >> "$LOG" ;;
esac'
printf '[Context]\nshared=network;\nsockets=x11;pulseaudio;\ndevices=dri;all;\nfilesystems=home:ro;xdg-download;\n' > "$WORK/perm_us.zoom.Zoom"
printf '[Context]\nsockets=wayland;pulseaudio;\ndevices=dri;\nfilesystems=xdg-download;\n' > "$WORK/perm_org.mozilla.firefox"
printf '[Context]\nsockets=x11;\ndevices=dri;\nfilesystems=host;\n' > "$WORK/perm_com.skype.Client"

export PATH="$B:$PATH" LOG WORK
export FORGEOS_PRIVACY_LIB="$U/libexec/forgeos-privacy-lib" FORGEOS_PRIVACY_PROC="$PR" FORGEOS_PRIVACY_APPS="$APPS"
export FORGEOS_PRIVACY_STATE="$WORK/state" FORGEOS_PRIVACY_CONF="$WORK/conf" FORGEOS_PRIVACY_RUN="$WORK/run"
P="$U/bin/forgeos-privacy"; BL="$U/bin/forgeos-privacy-block"; G="$U/bin/forgeos-privacy-gui"
UL="$WORK/state/usage.log"; BF="$WORK/conf/blocked"
T=1790000000

# A: now -> camera (PipeWire + direct), mic, screen; nothing else
want="$(printf 'camera\tcom.skype.Client\tSkype\ncamera\torg.mozilla.firefox\tFirefox\nmic\tus.zoom.Zoom\tZoom\nscreen\tobs\tOBS Studio')"
check "A now lists exactly who uses camera/mic/screen" '[ "$(bash "$P" now)" = "$want" ]'
check "A2 Flatpak id with a dash is read back from its scope name" '[ "$(. "$FORGEOS_PRIVACY_LIB"; key_for_pid 4343 camtool)" = io.github.cam-tool ]'

# B: watch --once writes starts once (+ camera/screen notices), then a stop when Zoom quits
FORGEOS_PRIVACY_NOW=$T bash "$P" watch --once
FORGEOS_PRIVACY_NOW=$((T + 60)) bash "$P" watch --once
starts1="$(grep -c "	start	" "$UL")"
FAKE_PW="$WORK/pw2.json" FORGEOS_PRIVACY_NOW=$((T + 600)) bash "$P" watch --once
check "B1 four starts, no repeats" '[ "$starts1" -eq 4 ] && [ "$(grep -c "	start	" "$UL")" -eq 4 ]'
check "B2 Zoom mic stop at +600" 'grep -qxF "$((T + 600))	stop	mic	us.zoom.Zoom	Zoom" "$UL" && [ "$(grep -c "	stop	" "$UL")" -eq 1 ]'
check "B3 camera + screen notices" 'grep -q "notify.*Skype turned on your camera" "$LOG" && grep -q "notify.*Firefox turned on your camera" "$LOG" && grep -q "notify.*OBS Studio can see your screen" "$LOG" && [ "$(grep -c "^notify" "$LOG")" -eq 3 ]'

# C: report from a known log
mkdir -p "$WORK/run"
printf 'camera\torg.mozilla.firefox\tFirefox\n' > "$WORK/run/now"
{
  printf '%s\tstart\tcamera\tcom.skype.Client\tSkype\n%s\tstop\tcamera\tcom.skype.Client\tSkype\n' $((T - 9 * 86400)) $((T - 9 * 86400 + 60))
  printf '%s\tstart\tmic\tus.zoom.Zoom\tZoom\n%s\tstop\tmic\tus.zoom.Zoom\tZoom\n' $((T - 7 * 86400 - 600)) $((T - 7 * 86400 + 1200))
  printf '%s\tstart\tmic\tus.zoom.Zoom\tZoom\n%s\tstop\tmic\tus.zoom.Zoom\tZoom\n' $((T - 3600)) $((T - 3600 + 1500))
  printf '%s\tstart\tcamera\torg.mozilla.firefox\tFirefox\n' $((T - 4000))
  printf '%s\tstart\tcamera\tcom.skype.Client\tSkype\n' $((T - 100))
} > "$UL"
rep="$(FORGEOS_PRIVACY_NOW=$T bash "$P" report)"
check "C1 Firefox camera live: 1 time, about 1 hour 6 minutes, RIGHT NOW" 'grep -q "Firefox - 1 time, about 1 hour 6 minutes in all.*USING IT RIGHT NOW" <<< "$rep"'
check "C2 Zoom mic: 2 times (one began before the week), 45 minutes" 'grep -q "Zoom - 2 times, about 45 minutes in all" <<< "$rep"'
check "C3 Skype: old use dropped, crashed open use = 1 time, not live" 'grep -q "Skype - 1 time, less than a minute in all. Last time: [^.]*\.$" <<< "$rep"'
check "C4 nobody saw the screen" 'grep -q "No app saw your screen." <<< "$rep"'
check "C5 bad days -> 2" 'bash "$P" report x >/dev/null 2>&1; [ $? -eq 2 ]'
check "C6 allowed: camera, mic, files, location (names from the menu, no repeats)" 'grep -qx "  Camera: Firefox, Zoom" <<< "$rep" && grep -qx "  Microphone (any app with sound can also record): Firefox, Zoom" <<< "$rep" && grep -qx "  All your files: Skype, Zoom" <<< "$rep" && grep -qx "  Your location: Skype" <<< "$rep"'
check "C7 nothing blocked yet" 'grep -q "Nothing blocked." <<< "$rep"'
# D: mic guard mutes only a blocked app's live recordings, and says so once
mkdir -p "$WORK/conf"; printf 'mic\tus.zoom.Zoom\n' > "$BF"
cat > "$WORK/so.json" <<'EOF'
[{"index":51,"mute":false,"properties":{"application.name":"ZOOM","pipewire.access.portal.app_id":"us.zoom.Zoom"}},
 {"index":52,"mute":false,"properties":{"application.name":"Firefox","pipewire.access.portal.app_id":"org.mozilla.firefox"}},
 {"index":53,"mute":true,"properties":{"application.process.binary":"zoom"}},
 {"index":54,"mute":false,"properties":{"application.process.binary":"arecord"}}]
EOF
: > "$LOG"; rm -f "$WORK/run/muted"
bash "$P" watch --once; bash "$P" watch --once
check "D1 only stream 51 muted" '[ "$(grep "^pactl mute" "$LOG" | sort -u)" = "pactl mute 51 1" ]'
check "D2 one notice for it" '[ "$(grep -c "Blocked Zoom from using your microphone" "$LOG")" -eq 1 ]'

# E-H: camera block / unblock
: > "$BF"; : > "$LOG"
out="$(bash "$BL" block us.zoom.Zoom camera)"; rc=$?
check "E1 Zoom (devices=all) camera block" '[ $rc -eq 0 ] && grep -qx "flatpak override --user --nodevice=all us.zoom.Zoom" "$LOG" && grep -qx "flatpak permission-set devices camera us.zoom.Zoom no" "$LOG" && grep -qxF "camera	us.zoom.Zoom	all" "$BF"'
check "E2 says close + reopen" 'grep -q "Zoom is blocked from your camera" <<< "$out" && grep -q "Close Zoom and open it again" <<< "$out"'
: > "$LOG"
check "F already blocked -> no change" 'bash "$BL" block us.zoom.Zoom camera | grep -q "already blocked" && [ ! -s "$LOG" ]'
bash "$BL" unblock us.zoom.Zoom camera >/dev/null
check "G unblock gives exactly that back" 'grep -qx "flatpak override --user --device=all us.zoom.Zoom" "$LOG" && grep -qx "flatpak permission-remove devices camera us.zoom.Zoom" "$LOG" && [ ! -s "$BF" ]'
: > "$LOG"; bash "$BL" block org.mozilla.firefox camera --close >/dev/null
check "H Firefox (no devices=all): portal only, no override, closed" '! grep -q override "$LOG" && grep -qxF "camera	org.mozilla.firefox" "$BF" && grep -qx "flatpak kill org.mozilla.firefox" "$LOG"'

# I-J: files
: > "$LOG"; bash "$BL" block us.zoom.Zoom files >/dev/null
check "I1 home:ro removed, saved" 'grep -qx "flatpak override --user --nofilesystem=home us.zoom.Zoom" "$LOG" && grep -qxF "files	us.zoom.Zoom	home:ro" "$BF" && ! grep -q "xdg-download" "$LOG"'
: > "$LOG"; bash "$BL" unblock us.zoom.Zoom files >/dev/null
check "I2 unblock puts home:ro back" 'grep -qx "flatpak override --user --filesystem=home:ro us.zoom.Zoom" "$LOG" && ! grep -q "^files" "$BF"'
: > "$LOG"
check "J Firefox has no home access -> nothing to do" 'bash "$BL" block org.mozilla.firefox files | grep -q "already cannot see all your files" && [ ! -s "$LOG" ] && ! grep -q "^files" "$BF"'

# K: refusals
bash "$BL" block zoom camera >/dev/null 2>&1; k1=$?
bash "$BL" block 'a;b' mic >/dev/null 2>&1; k2=$?
bash "$BL" block us.zoom.Zoom wifi >/dev/null 2>&1; k3=$?
bash "$BL" >/dev/null 2>&1; k4=$?
check "K not sandboxed camera = 3; bad name, kind, usage = 2" '[ "$k1$k2$k3$k4" = 3222 ]'

# L: mic block works for a plain program too; unblock unmutes only that program
: > "$LOG"
check "L1 block zoom mic (its stream is already muted: no extra mute)" 'bash "$BL" block zoom mic | grep -q "zoom is blocked from your microphone" && grep -qxF "mic	zoom" "$BF" && ! grep -q "^pactl mute" "$LOG"'
bash "$BL" unblock zoom mic >/dev/null
check "L2 unblock unmutes 53 only" '[ "$(grep "^pactl mute" "$LOG")" = "pactl mute 53 0" ] && ! grep -q "^mic	zoom" "$BF"'
check "L3 list shows what is left" '[ "$(bash "$BL" list)" = "camera	org.mozilla.firefox" ]'
# M: the window (fake kdialog answers from a list: "<exit code>|<what it prints>")
mk kdialog 'echo "kdialog $*" >> "$LOG"
[ "$1 $2 $3" = "--title ForgeOS Privacy Report --textbox" ] && cp "$4" "$WORK/shown"
a="$(head -n 1 "$WORK/kd")"; sed -i 1d "$WORK/kd"
[ -n "$a" ] || exit 1
printf "%s" "${a#*|}"; [ -n "${a#*|}" ] && echo
exit "${a%%|*}"'
mk fp-report "exec bash \"$P\" \"\$@\""; mk fp-block "exec bash \"$BL\" \"\$@\""
export FORGEOS_PRIVACY_ENGINE="$B/fp-report" FORGEOS_PRIVACY_BLOCKER="$B/fp-block"
: > "$BF"; : > "$LOG"
printf '0|block\n0|us.zoom.Zoom\n0|camera\n0|\n0|\n0|\n0|report\n0|\n0|unblock\n0|camera us.zoom.Zoom\n0|\n1|\n' > "$WORK/kd"
FORGEOS_PRIVACY_NOW=$T bash "$G"; rc=$?
check "M1 window: block Zoom camera, closed, then menu Cancel exits 0" '[ $rc -eq 0 ] && grep -qx "flatpak kill us.zoom.Zoom" "$LOG" && grep -qx "flatpak override --user --nodevice=all us.zoom.Zoom" "$LOG"'
check "M2 warned about camera + controllers first" 'grep -q "warningyesno Zoom will not be able to use your camera.*Game controllers" <<< "$(tr "\n" " " < "$LOG")"'
check "M3 report shown in a text box" 'grep -q "ForgeOS Privacy Report - the last 7 days" "$WORK/shown" && grep -q "Zoom: blocked from your camera." "$WORK/shown"'
check "M4 undo the block from the window" 'grep -qx "flatpak override --user --device=all us.zoom.Zoom" "$LOG" && [ ! -s "$BF" ]'
check "M5 app list = seen apps + Flatpak apps, once each" '[ "$(grep -c "menu Which app do you want to block? .*us.zoom.Zoom Zoom" "$LOG")" -eq 1 ] && ! grep "menu Which app" "$LOG" | grep -q "us.zoom.Zoom.*us.zoom.Zoom"'

# N: background service: closes leftovers on start, keeps 90 days, closes all on stop, ends pactl
mkdir -p "$WORK/run"
printf 'mic\tobs\tOBS Studio\n' > "$WORK/run/now"
printf '%s\tstart\tmic\told\tOld\n%s\tstart\tmic\tobs\tOBS Studio\n' $((T - 91 * 86400)) $((T - 50)) > "$UL"
: > "$LOG"
FORGEOS_PRIVACY_NOW=$T bash "$P" watch & wp=$!
for _ in $(seq 1 50); do [ "$(grep -c "	start	" "$UL")" -ge 5 ] && break; sleep 0.1; done
kill -TERM "$wp"; wait "$wp" 2>/dev/null
sleep 0.3
check "N1 91-day-old note removed" '! grep -q "	old	" "$UL"'
check "N2 leftover OBS use closed at start" '[ "$(sed -n 2p "$UL")" = "$T	stop	mic	obs	OBS Studio" ]'
check "N3 on stop every open use is closed" '[ "$(grep -c "	stop	" "$UL")" -eq 5 ] && [ ! -s "$WORK/run/now" ]'
check "N4 pactl subscribe started and ended with it" 'grep -q "pactl subscribe" "$LOG" && ! pgrep -f "sleep 30" >/dev/null'

# O: build files
SET="$ROOT/files/scripts/forgeos-setup.sh"
check "O1 setup makes all 3 commands runnable" 'grep -q "/usr/bin/forgeos-privacy " "$SET" && grep -q "/usr/bin/forgeos-privacy-block" "$SET" && grep -q "/usr/bin/forgeos-privacy-gui" "$SET"'
check "O2 setup turns the note-taker on for everyone" 'grep -qx "systemctl --global enable forgeos-privacy-watch.service" "$SET"'
check "O3 recipe adds pipewire-utils (pw-dump)" 'grep -q "^ *- pipewire-utils" "$ROOT/recipes/recipe.yml"'
SV="$U/lib/systemd/user/forgeos-privacy-watch.service"
check "O4 user service runs forgeos-privacy watch in the desktop session" 'grep -qx "ExecStart=/usr/bin/forgeos-privacy watch" "$SV" && grep -qx "WantedBy=graphical-session.target" "$SV"'
D="$U/share/applications/forgeos-privacy.desktop"
check "O5 menu entry opens the window" 'grep -qx "Exec=/usr/bin/forgeos-privacy-gui" "$D" && grep -qx "Name=Privacy Report" "$D"'
if command -v desktop-file-validate >/dev/null 2>&1; then
  check "O6 menu entry is valid" 'desktop-file-validate "$D"'
fi
check "O7 no Windows line endings" '! grep -l $'"'"'\r'"'"' "$U/libexec/forgeos-privacy-lib" "$P" "$BL" "$G" "$SV" "$D" "$ROOT/tests/test-privacy.sh" >/dev/null'

echo
if [ "$failures" -eq 0 ]; then echo "ALL PRIVACY REPORT TESTS PASSED"; exit 0; fi
echo "$failures PRIVACY REPORT TEST(S) FAILED"; exit 1

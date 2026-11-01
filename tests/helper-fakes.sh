# shellcheck shell=bash
# Fake tools for the Forge Helper tests (Job 13c). Sourced by tests/test-helper*.sh.
# Every fake writes its name and arguments to $WORK/calls.log. Answers come from files in $WORK.
# shellcheck disable=SC2016  # the fake scripts are written out single-quoted on purpose
mkdir -p "$WORK/bin" "$WORK/home/Documents" "$WORK/cfg" "$WORK/data" "$WORK/state" "$WORK/libexec"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }

# Scam Shield: "prize" or "gift card" = scam (2), "careful" = be careful (1), else fine (0).
fake forgeos-scamshield 'm="$(cat)"; echo "$m" > "$WORK/scam-input"
case "$m" in
  *prize*|*[Gg]ift\ card*) printf "RESULT: Looks like a scam\nWhat to do: Do not click any link.\nVERDICT\tscam\n"; exit 2 ;;
  *careful*) echo "RESULT: Be careful"; exit 1 ;;
  *) echo "RESULT: No scam signs found"; exit 0 ;;
esac'
fake forgeos-askpc 'case "$1" in
  ask) echo "The sound is turned off."; echo; echo "Suggested fix: Turn the sound on (unmute) and set the volume to half."; echo "FIX: unmute-sound" ;;
  fixes) printf "restart-internet\tTurn the internet connection off and on again\t\nunmute-sound\tTurn the sound on\t\nclose-busy-app\tClose the program using the most computer power: hog\thog\n" ;;
  fix) echo "Done: $2"; exit "$(cat "$WORK/fix-rc" 2>/dev/null || echo 0)" ;;
  health) cat "$WORK/health" 2>/dev/null; exit "$(cat "$WORK/health-rc" 2>/dev/null || echo 0)" ;;
esac'
fake forgeos-find 'if [ -s "$WORK/find-out" ]; then cat "$WORK/find-out"; exit 0; fi; echo "Nothing found."; exit "$(cat "$WORK/find-rc" 2>/dev/null || echo 1)"'
fake forgeos-willitrun 'printf "%s does not run on ForgeOS. Try GIMP, it is free.\nVERDICT: swap\nWAY: flatpak org.gimp.GIMP\n" "$2"; exit 0'
fake forgeos-ghost 'printf "GhostFinder - see who'"'"'s watching.\nAll clear: no cameras or trackers found.\nVERDICT\tgreen\n"'
fake forgeos-guard 'case "$1" in
  status) printf "SERVICE\trunning\nGUARD\tdownloads\ton\tfast\nGUARD\twebsites\ton\t120000\ttoday\nGUARD\temail\toff\tno-thunderbird\nVIRUSLIST\t2026-10-31\nLOCKED\t1\nWARNINGS\t2\n" ;;
  events) cat "$WORK/guard-events" 2>/dev/null ;;
esac'
fake forgeos-undo 'exit "$(cat "$WORK/undo-rc" 2>/dev/null || echo 0)"'
fake forgeos-privacy 'printf "ForgeOS Privacy Report - the last 7 days\nCamera: Brave used it for 5 minutes.\n"'
fake forgeos-family 'case "$1" in
  status) printf "STATUS\t%s\nSIZE\tbig\nHELPER\t%s\n" "$(cat "$WORK/family-on" 2>/dev/null || echo off)" "$(cat "$WORK/family-helper" 2>/dev/null || echo -)" ;;
  size|on) echo "Text size is now done." ;;
esac'
fake forgeos-panic 'echo "Panic Button is ON."'
fake forgeos-ai-setup 'echo "VRAM: ${FAKE_VRAM:-8192} MB"; echo "Model: gemma4:e4b (~10 GB)"'
fake ollama 'exit "$(cat "$WORK/pull-rc" 2>/dev/null || echo 0)"'
fake xdg-open 'exit 0'
for w in cleansweep undo privacy scamshield find willitrun ghost guard family askpc; do fake "forgeos-$w-gui" 'exit 0'; done
fake notify-send 'cat "$WORK/notify-answer" 2>/dev/null; exit 0'
fake busctl 'cat "$WORK/busctl-out" 2>/dev/null || echo "b false"'
fake gamemoded 'echo "gamemode is inactive"'
fake pgrep '[ -e "$WORK/gamescope" ]'
fake systemctl 'for a in "$@"; do grep -qx -- "$a" "$WORK/failed-units" 2>/dev/null && exit 0; done; exit 1'
fake ps 'cat "$WORK/ps-out" 2>/dev/null'
printf '#!/usr/bin/env bash\necho "forgeos-family-call $*" >> "$WORK/calls.log"\n' > "$WORK/libexec/forgeos-family-call"
chmod +x "$WORK/libexec/forgeos-family-call"
cp "$ROOT/files/system/usr/libexec/forgeos-askpc-fixes" "$WORK/libexec/"


H="$WORK/home"
export WORK HOME="$H" PATH="$WORK/bin:$PATH" XDG_CONFIG_HOME="$WORK/cfg" XDG_DATA_HOME="$WORK/data" XDG_STATE_HOME="$WORK/state"
export FORGEOS_HELPER_LIB="$ROOT/files/system/usr/lib/forgeos-helper" FORGEOS_HELPER_SHARE="$ROOT/files/system/usr/share/forgeos/helper"
export FORGEOS_HELPER_LIBEXEC="$WORK/libexec" FORGEOS_OLLAMA_URL="http://127.0.0.1:9" PYTHONDONTWRITEBYTECODE=1
HELPER="$ROOT/files/system/usr/bin/forgeos-helper"
# git keeps the scripts without the "run" bit, so the window calls the engine through a wrapper.
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$HELPER" > "$WORK/engine"
chmod +x "$WORK/engine"
export FORGEOS_HELPER_ENGINE="$WORK/engine"

# F: run Forge Helper. tool <output>: the TOOL line's tool. acts <output>: the ACTION lines.
F() { python3 -B "$HELPER" "$@"; }
tool() { awk -F '\t' '$1 == "TOOL" {print $2; exit}' <<< "$1"; }
how() { awk -F '\t' '$1 == "TOOL" {print $3; exit}' <<< "$1"; }
acts() { awk -F '\t' '$1 == "ACTION" {print $2 " " $3}' <<< "$1"; }
calls() { cat "$WORK/calls.log" 2>/dev/null; }

# start_fake_ollama: start tests/helper-fake-ollama.py and point Forge Helper at it.
start_fake_ollama() {
  python3 -B "$ROOT/tests/helper-fake-ollama.py" "$WORK" &
  OLLAMA_PID=$!
  for _ in $(seq 50); do [ -s "$WORK/ai-port" ] && break; sleep 0.1; done
  FORGEOS_OLLAMA_URL="http://127.0.0.1:$(cat "$WORK/ai-port")"
  export FORGEOS_OLLAMA_URL
  trap 'kill "$OLLAMA_PID" 2>/dev/null; rm -rf "$WORK"' EXIT
}
# route TOOL [TEXT] [FIX]: what the fake router AI answers next.
route() { printf '{"tool":"%s","text":"%s","fix":"%s"}' "$1" "${2:-}" "${3:-none}" > "$WORK/ai-route"; }
# last N: one fact per line about the Nth-last request sent to the AI (1 = the last one).
last() { python3 -B "$ROOT/tests/helper-last.py" "$WORK/ai-bodies.jsonl" "${1:-1}"; }

# shellcheck shell=bash
# Fake PC for the PC Report Card tests (Job 21). Sourced by tests/test-reportcard*.sh.
# Every ForgeOS tool the card asks is a fake that prints $WORK/say/<tool> (and exits with $WORK/code/<tool>);
# rpm-ostree, systemctl, upower and notify-send are fakes too. Fakes log to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home/Documents" "$WORK/say" "$WORK/code"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
export WORK HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" XDG_DATA_HOME="$WORK/data" XDG_CONFIG_HOME="$WORK/config"
export PATH="$WORK/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 FORGEOS_CARD_LIB="$ROOT/files/system/usr/lib/forgeos-reportcard"
export FORGEOS_SLOW_LIB="$ROOT/files/system/usr/lib/forgeos-slow"
ENGINE="$ROOT/files/system/usr/bin/forgeos-reportcard"
GUI="$ROOT/files/system/usr/bin/forgeos-reportcard-gui"
RC() { python3 -B "$ENGINE" "$@"; }
T=$'\t'
NOW="$(date +%s)"
DAY=86400
for t in forgeos-guard forgeos-tripwire forgeos-techguard forgeos-autopilot forgeos-drivehealth forgeos-undo \
         forgeos-digitalwill forgeos-locate rpm-ostree upower; do
  fake "$t" "cat \"\$WORK/say/$t\" 2>/dev/null; exit \"\$(cat \"\$WORK/code/$t\" 2>/dev/null || echo 0)\""
done
fake systemctl 'cat "$WORK/say/systemctl" 2>/dev/null; exit "$(cat "$WORK/code/systemctl" 2>/dev/null || echo 0)"'
fake notify-send 'cat "$WORK/say/notify-send" 2>/dev/null; exit 0'
fake busctl 'echo "b ${GAME:-false}"'
fake gamemoded 'exit 1'
fake pgrep 'exit 1'
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$ENGINE" > "$WORK/bin/forgeos-reportcard"
chmod +x "$WORK/bin/forgeos-reportcard"
say() { printf '%b' "$2" > "$WORK/say/$1"; }
day() { date -d "@$((NOW - $1 * DAY))" +%Y-%m-%d; }
# the slow history: N samples over the last hours, the first S of them slow (memory nearly full)
slow_history() {
  mkdir -p "$WORK/state/forgeos/slow"
  python3 -c "
import json, sys
n, s, now = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
for i in range(n):
    print(json.dumps({'t': now - 300 * (i + 1), 'cpu': 0, 'mem': 20 if i < s else 0, 'io': 0, 'free': 50,
                      'top': ['', 0], 'big': ['Brave', 3 * 1024 ** 3], 'temp': 50}))" "$1" "$2" "$NOW" > "$WORK/state/forgeos/slow/history.jsonl"
}
sweep() {
  mkdir -p "$WORK/data/forgeos/ghost"
  printf '{"time": %d, "level": "%s", "items": [{"level": "%s", "what": "%s"}]}\n' "$((NOW - $2 * DAY))" "$1" "$1" "${3:-a camera}" \
    > "$WORK/data/forgeos/ghost/last-sweep.json"
}
# healthy_pc: every subject gets an A (a desktop PC, no battery)
healthy_pc() {
  say forgeos-guard "SERVICE${T}running\nGUARD${T}downloads${T}on${T}fast\nGUARD${T}websites${T}on${T}90000${T}$(day 1) 03:00\nGUARD${T}email${T}on${T}thunderbird\nVIRUSLIST${T}$(day 1)\nLOCKED${T}0\nWARNINGS${T}0\n"
  say forgeos-tripwire "SERVICE${T}on\nBAIT${T}12\nSNAPSHOT${T}none\nINTERNET${T}normal\n"
  say forgeos-techguard "SERVICE${T}on\nFAMILY${T}off\nMONEY${T}open\nINTERNET${T}on\n"
  say forgeos-autopilot "DRIVERS${T}current${T}\nUPDATES${T}ok\nFIRMWARE${T}0${T}-${T}checked\nDEVICES${T}0\nIMAGE${T}ok\n"
  say rpm-ostree "{\"deployments\": [{\"booted\": true, \"timestamp\": $((NOW - 3 * DAY))}]}\n"
  say forgeos-drivehealth "CHECKED${T}$((NOW - DAY))${T}good\nDRIVE${T}nvme0${T}good${T}Samsung 990${T}ssd${T}1 TB\nBACKUP${T}set${T}2\n"
  say forgeos-undo "Undo Button: ON — 40 snapshots, from $(day 20) 10:00 to $(day 0) 09:00\n"
  say systemctl "active\n"
  say forgeos-digitalwill "PEOPLE${T}1${T}Brianna\nENVELOPE${T}$(day 30)${T}30${T}Robert\nUNLOCK${T}off\n"
  say forgeos-locate "SETUP${T}yes\nMADE${T}-\n"
  say upower ""
  slow_history 100 0
  sweep green 10
  export FORGEOS_CARD_SPACE="500000000000 1000000000000"
}
grade_of() { awk -F "$T" -v k="$1" '$1 == "SUBJECT" && $2 == k {print $3}' <<< "$OUT"; }
why_of() { awk -F "$T" -v k="$1" '$1 == "SUBJECT" && $2 == k {print $8}' <<< "$OUT"; }
overall() { awk -F "$T" '$1 == "OVERALL" {print $2}' <<< "$OUT"; }

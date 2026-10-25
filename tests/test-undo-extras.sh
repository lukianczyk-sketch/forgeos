#!/usr/bin/env bash
# tests/test-undo-extras.sh — Job 5 Step 5: cases L-T for forgeos-undo-gui,
# forgeos-undo-setup and Clean Sweep's wipe_snapshots_plan. All tools are fakes.
set -uo pipefail

ROOT="${1:-.}"
B="$ROOT/files/system/usr"
failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
export PATH="$WORK/bin:$PATH" FAKE_LOG="$WORK/fake.log"

# Fake kdialog: logs every call; --menu answers pop from $WORK/menu, one per line.
cat > "$WORK/bin/kdialog" <<'EOF'
#!/usr/bin/env bash
echo "kdialog $*" >> "$FAKE_LOG"
for a in "$@"; do
  if [ "$a" = "--menu" ]; then
    l="$(head -n 1 "$FAKE_MENU" 2>/dev/null)"; sed -i 1d "$FAKE_MENU" 2>/dev/null
    [ -n "$l" ] || exit 1
    echo "$l"; exit 0
  fi
done
exit 0
EOF
# Fake engine: answers from FAKE_VERS / FAKE_RESTORE_RC.
cat > "$WORK/bin/fake-engine" <<'EOF'
#!/usr/bin/env bash
echo "engine $*" >> "$FAKE_LOG"
case "$1" in
  versions) [ -n "${FAKE_VERS:-}" ] || exit 1; printf '%b' "$FAKE_VERS" ;;
  restore) [ "${FAKE_RESTORE_RC:-0}" -eq 0 ] && echo "/h/doc (from X).txt"; exit "${FAKE_RESTORE_RC:-0}" ;;
  snapshot-now) echo "Snapshot taken." ;;
esac
EOF
chmod +x "$WORK/bin/"*
export FORGEOS_UNDO_ENGINE="$WORK/bin/fake-engine" FAKE_MENU="$WORK/menu"
GUI="$B/bin/forgeos-undo-gui"

gui() { : > "$FAKE_LOG"; printf '%s' "$1" > "$FAKE_MENU"; shift; bash "$GUI" "$@" >/dev/null 2>&1; RC=$?; }

# L: right-click a file -> pick version 3 -> restore 3 -> "Got it back"
FAKE_VERS='3\t2026-10-03 12:00\tAutomatic snapshot\tfile\n' gui $'3\n' /h/doc.txt
if [ "$RC" -eq 0 ] && grep -qxF "engine restore 3 /h/doc.txt" "$FAKE_LOG" && grep -q "msgbox Got it back" "$FAKE_LOG"; then
  pass "L gui restore"; else fail "L gui restore"; fi

# M: no versions -> "No older versions", no restore
gui "" /h/doc.txt
if grep -q "No older versions" "$FAKE_LOG" && ! grep -q "engine restore" "$FAKE_LOG"; then
  pass "M gui no versions"; else fail "M gui no versions"; fi

# N: virus (exit 4) -> error box that says virus
FAKE_VERS='3\td\tx\tfile\n' FAKE_RESTORE_RC=4 gui $'3\n' /h/doc.txt
if grep -q "error A virus was found" "$FAKE_LOG"; then pass "N gui virus"; else fail "N gui virus"; fi

# O: main menu -> "snap" -> snapshot-now, then Cancel ends the loop
gui $'snap\n'
if [ "$RC" -eq 0 ] && grep -q "engine snapshot-now" "$FAKE_LOG" && grep -q "Snapshot taken" "$FAKE_LOG"; then
  pass "O gui snapshot now"; else fail "O gui snapshot now"; fi

# --- forgeos-undo-setup with fake findmnt / btrfs / snapper ---
cat > "$WORK/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
echo "${FAKE_FS:-btrfs}"
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/btrfs"
cat > "$WORK/bin/snapper" <<'EOF'
#!/usr/bin/env bash
echo "snapper $*" >> "$FAKE_LOG"
case " $* " in
  *" get-config "*) [ -n "${FAKE_HAS_CFG:-}" ]; exit $? ;;
  *" list-configs "*) [ -n "${FAKE_NODBUS:-}" ] && [ "$1" != "--no-dbus" ] && exit 1
     printf 'config,subvolume\n%b' "${FAKE_CFGS:-root,/var/home\n}" ;;
  *" list "*) printf 'number\n0\n1\n3\n4\n' ;;
  *" delete "*) exit "${FAKE_DEL_RC:-0}" ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/"*
export FORGEOS_UNDO_HOME="$WORK/vh" FORGEOS_UNDO_MARKER="$WORK/m/done"
setup() { : > "$FAKE_LOG"; rm -rf "$WORK/m"; bash "$B/libexec/forgeos-undo-setup" >/dev/null 2>&1; RC=$?; }

# P: fresh btrfs -> create-config + safe limits, marker "enabled"
setup
if [ "$RC" -eq 0 ] && grep -q "create-config $WORK/vh" "$FAKE_LOG" \
   && grep -q "set-config ALLOW_GROUPS=wheel SYNC_ACL=yes .*TIMELINE_LIMIT_HOURLY=1-12 .*FREE_LIMIT=0.2" "$FAKE_LOG" \
   && grep -q "^enabled" "$WORK/m/done"; then pass "P setup turns it on"; else fail "P setup"; fi

# Q: not btrfs -> skipped; existing config -> left alone (no create-config)
FAKE_FS=ext4 setup; q1="$(cat "$WORK/m/done")"
FAKE_HAS_CFG=1 setup; q2="$(cat "$WORK/m/done")"
if [ "$q1" = "skipped: not btrfs" ] && [ "$q2" = "skipped: config already existed" ] && ! grep -q create-config "$FAKE_LOG"; then
  pass "Q setup skips"; else fail "Q setup skips ($q1 / $q2)"; fi

# R: marker already there -> nothing runs
mkdir -p "$WORK/m"; echo old > "$WORK/m/done"; : > "$FAKE_LOG"
bash "$B/libexec/forgeos-undo-setup" >/dev/null 2>&1
if [ "$?" -eq 0 ] && [ ! -s "$FAKE_LOG" ]; then pass "R setup runs once"; else fail "R setup runs once"; fi

# --- wipe_snapshots_plan, cut out of forgeos-cleansweep ---
sed -n '/^wipe_snapshots_plan() {/,/^}/p' "$B/bin/forgeos-cleansweep" > "$WORK/wsp"
grep -q '^}' "$WORK/wsp" || fail "wipe_snapshots_plan not found"
wipe() {
  : > "$FAKE_LOG"
  ( export LOG_FILE="$WORK/wlog"; WIPE_ERRORS=0; WIPE_SNAPS=0
    log() { echo "$*"; }
    # shellcheck source=/dev/null
    . "$WORK/wsp"; wipe_snapshots_plan "$@" >"$WORK/out"
    echo "$WIPE_SNAPS $WIPE_ERRORS" > "$WORK/cnt" )
}

# S: plan counts 3 (0 is "now"), no delete; apply deletes 1 3 4; finds the
#    /var/home config when not first; D-Bus down -> --no-dbus
FAKE_CFGS='root,/\nhome,/var/home\n' wipe plan; s1="$(cat "$WORK/cnt")"; s1d="$(grep -c delete "$FAKE_LOG")"
FAKE_CFGS='root,/\nhome,/var/home\n' wipe apply; s2="$(cat "$WORK/cnt")"
s2ok=0; grep -qxF "snapper -c home delete --sync 1 3 4" "$FAKE_LOG" && s2ok=1
FAKE_NODBUS=1 wipe apply; s3ok=0; grep -qxF "snapper --no-dbus -c root delete --sync 1 3 4" "$FAKE_LOG" && s3ok=1
if [ "$s1" = "3 0" ] && [ "$s1d" -eq 0 ] && [ "$s2" = "3 0" ] && [ "$s2ok" -eq 1 ] && [ "$s3ok" -eq 1 ]; then
  pass "S wipe snapshots"; else fail "S wipe ($s1/$s1d/$s2/$s2ok/$s3ok)"; fi

# T: no /var/home config -> "off"; delete fails -> counted as a problem
FAKE_CFGS='root,/\n' wipe apply; t1="$(cat "$WORK/cnt")"; t1m=0; grep -q "Undo Button is off" "$WORK/out" && t1m=1
FAKE_DEL_RC=1 wipe apply; t2="$(cat "$WORK/cnt")"
if [ "$t1" = "0 0" ] && [ "$t1m" -eq 1 ] && [ "$t2" = "3 1" ]; then
  pass "T wipe off + delete error"; else fail "T ($t1/$t1m/$t2)"; fi

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1

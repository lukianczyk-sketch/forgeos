#!/usr/bin/env bash
# tests/test-undo.sh — Job 5 Step 5: cases A-K for files/system/usr/bin/forgeos-undo.
# Normal user, no root. FORGEOS_UNDO_HOME points at a fake home with a fake
# .snapshots tree; snapper / rpm-ostree / clamscan are fake shims in $WORK/bin.
set -uo pipefail

ROOT="${1:-.}"
ENGINE="$ROOT/files/system/usr/bin/forgeos-undo"
failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
[ -f "$ENGINE" ] || { echo "FAIL: engine not found: $ENGINE"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"
S="$H/.snapshots"
mkdir -p "$WORK/bin" "$H/bob"
export FORGEOS_UNDO_HOME="$H" TZ=XST+7 PATH="$WORK/bin:$PATH"

# snap <num> <UTC date> <cleanup> <description>
snap() {
  mkdir -p "$S/$1/snapshot/bob"
  printf '<snapshot>\n  <num>%s</num>\n  <date>%s</date>\n  <description>%s</description>\n  <cleanup>%s</cleanup>\n</snapshot>\n' \
    "$1" "$2" "$4" "$3" > "$S/$1/info.xml"
}
snap 1 "2026-10-01 10:00:00" number "Before update"
snap 2 "2026-10-02 11:00:00" timeline "timeline"
snap 3 "2026-10-03 12:00:00" timeline "timeline"
snap 4 "2026-10-04 13:00:00" timeline "timeline"
echo v1 > "$S/1/snapshot/bob/doc.txt"
echo v2 > "$S/2/snapshot/bob/doc.txt"
echo v2 > "$S/3/snapshot/bob/doc.txt"
echo v3 > "$S/4/snapshot/bob/doc.txt"
echo v3 > "$H/bob/doc.txt"
echo gone > "$S/2/snapshot/bob/lost.txt"
mkdir -p "$S/1/snapshot/bob/pics" && echo p > "$S/1/snapshot/bob/pics/a.jpg"
mkdir -p "$S/junk/snapshot"   # not a number: must be ignored

cat > "$WORK/bin/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "clamscan $*" >> "$FAKE_LOG"
exit "${FAKE_CLAM_RC:-0}"
EOF
cat > "$WORK/bin/snapper" <<'EOF'
#!/usr/bin/env bash
echo "snapper $*" >> "$FAKE_LOG"
EOF
cat > "$WORK/bin/rpm-ostree" <<'EOF'
#!/usr/bin/env bash
echo "rpm-ostree $*" >> "$FAKE_LOG"
[ "$1" = status ] && echo '{"deployments":[{"booted":true,"timestamp":1760000000,"version":"43.2"},{"booted":false,"timestamp":1759000000,"version":"43.1"}]}'
exit 0
EOF
chmod +x "$WORK/bin/"*
export FAKE_LOG="$WORK/fake.log"

run() { : > "$FAKE_LOG"; bash "$ENGINE" "$@" >"$WORK/out" 2>"$WORK/err"; RC=$?; }

# A: status -> ON, 4 snapshots, oldest..newest in local time (UTC-7)
run status
if [ "$RC" -eq 0 ] && grep -q "ON — 4 snapshots, from 2026-10-01 03:00 to 2026-10-04 06:00" "$WORK/out"; then
  pass "A status on"; else fail "A status on (rc=$RC $(cat "$WORK/out"))"; fi

# B: versions -> newest first; skips copies same as now / same as the newer one listed
run versions "$H/bob/doc.txt"
got="$(cut -f1 "$WORK/out" | tr '\n' ' ')"
if [ "$RC" -eq 0 ] && [ "$got" = "3 1 " ] && grep -q $'^3\t2026-10-03 05:00\tAutomatic snapshot\tfile$' "$WORK/out" \
   && grep -q $'^1\t2026-10-01 03:00\tBefore update\tfile$' "$WORK/out"; then
  pass "B versions list"; else fail "B versions list (rc=$RC got=$got)"; fi

# C: bad paths -> exit 2 (outside home, inside .snapshots); nothing found -> exit 1
run versions /etc/passwd; c1=$RC
run versions "$S/1/snapshot/bob/doc.txt"; c2=$RC
echo same > "$H/bob/new.txt"; run versions "$H/bob/new.txt"; c3=$RC
if [ "$c1" -eq 2 ] && [ "$c2" -eq 2 ] && [ "$c3" -eq 1 ]; then
  pass "C bad paths + no versions"; else fail "C (rcs=$c1/$c2/$c3)"; fi

# D: restore over an existing file -> new name, current file untouched; again -> "#2"
run restore 1 "$H/bob/doc.txt"; d1=$RC
n1="$H/bob/doc (from 2026-10-01 03.00).txt"
run restore 1 "$H/bob/doc.txt"; d2=$RC
n2="$H/bob/doc (from 2026-10-01 03.00 #2).txt"
if [ "$d1" -eq 0 ] && [ "$d2" -eq 0 ] && [ "$(cat "$n1")" = v1 ] && [ "$(cat "$n2")" = v1 ] \
   && [ "$(cat "$H/bob/doc.txt")" = v3 ] && grep -qxF "$n2" "$WORK/out"; then
  pass "D restore never overwrites"; else fail "D restore (rcs=$d1/$d2)"; fi

# E: deleted file -> back under its old name; folder -> whole folder back
run restore 2 "$H/bob/lost.txt"; e1=$RC
run restore 1 "$H/bob/pics"; e2=$RC
if [ "$e1" -eq 0 ] && [ "$(cat "$H/bob/lost.txt")" = gone ] && [ "$e2" -eq 0 ] && [ -f "$H/bob/pics/a.jpg" ]; then
  pass "E deleted file + folder"; else fail "E (rcs=$e1/$e2)"; fi

# F: virus in the old copy -> exit 4, the new copy is removed
rm -f "$H/bob/lost.txt"
FAKE_CLAM_RC=1 run restore 2 "$H/bob/lost.txt"
if [ "$RC" -eq 4 ] && [ ! -e "$H/bob/lost.txt" ] && grep -q virus "$WORK/err"; then
  pass "F virus -> removed"; else fail "F virus (rc=$RC)"; fi

# G: scan error -> copy kept, warning on stderr, exit 0
FAKE_CLAM_RC=2 run restore 2 "$H/bob/lost.txt"
if [ "$RC" -eq 0 ] && [ -f "$H/bob/lost.txt" ] && grep -q "could not be virus-checked" "$WORK/err"; then
  pass "G scan error keeps copy"; else fail "G scan error (rc=$RC)"; fi

# H: bad restore input -> exit 2 (number), exit 1 (no copy in that snapshot)
run restore x "$H/bob/doc.txt"; h1=$RC
run restore 3 "$H/bob/lost.txt"; h2=$RC
if [ "$h1" -eq 2 ] && [ "$h2" -eq 1 ]; then pass "H bad restore"; else fail "H (rcs=$h1/$h2)"; fi

# I: snapshot-now -> snapper -c root create -c number -d <text>
run snapshot-now "My text"
if [ "$RC" -eq 0 ] && grep -qxF "snapper -c root create -c number -d My text" "$FAKE_LOG"; then
  pass "I snapshot-now"; else fail "I snapshot-now (rc=$RC $(cat "$FAKE_LOG"))"; fi

# J: updates -> NOW/BACKUP lines; undo-update -> rpm-ostree rollback
run updates; j1=$RC; cp "$WORK/out" "$WORK/upd"
run undo-update; j2=$RC
if [ "$j1" -eq 0 ] && grep -q $'^NOW\t2025-10-09 01:53\t43.2$' "$WORK/upd" && grep -q $'^BACKUP\t.*\t43.1$' "$WORK/upd" \
   && [ "$j2" -eq 0 ] && grep -qxF "rpm-ostree rollback" "$FAKE_LOG"; then
  pass "J updates + undo-update"; else fail "J (rcs=$j1/$j2 $(cat "$WORK/upd"))"; fi

# K: off -> status exit 1; bad command -> exit 2
FORGEOS_UNDO_HOME="$WORK/nohome" run status; k1=$RC
run bogus; k2=$RC
if [ "$k1" -eq 1 ] && [ "$k2" -eq 2 ]; then pass "K off + bad command"; else fail "K (rcs=$k1/$k2)"; fi

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1

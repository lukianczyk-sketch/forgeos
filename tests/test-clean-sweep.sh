#!/usr/bin/env bash
# tests/test-clean-sweep.sh — Job 3 Step 8e: cases A-Q (scan, quarantine, reset plan, full-wipe safety, symlinked folder, password reminder, real ClamAV when REAL_CLAMAV=1) for files/system/usr/bin/forgeos-cleansweep.
# Runs as a normal user (no root). The engine copy is sed-rewritten so its log/quarantine/reset-backup
# dirs point inside a private mktemp work dir, and the external tools it calls are replaced with fake
# shims in $WORK/bin that honor FAKE_DIFF / FAKE_RKH_RC / FAKE_INFECTED.
# getent / systemctl / flatpak / passwd are faked too, so even a broken engine
# cannot erase homes or empty the real tmp folders.
set -uo pipefail

ROOT="${1:-.}"
ENGINE="$ROOT/files/system/usr/bin/forgeos-cleansweep"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
skip() { echo "SKIP: $1"; }
failures=0

if [ ! -f "$ENGINE" ]; then
    echo "FAIL: engine not found: $ENGINE"
    exit 1
fi

WORK="$(mktemp -d)"
trap 'chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

# --- Copy the engine and point its dir vars at private locations ---
# (log / quarantine / reset-backup, plus /etc, /usr/etc and the two tmp folders a
# real reset would change — so even a broken engine can't touch this machine)
sed \
    -e "s|^LOG_DIR=\"/var/log/forgeos/clean-sweep\"|LOG_DIR=\"$WORK/log\"|" \
    -e "s|^QUAR_DIR=\"/var/lib/forgeos/quarantine\"|QUAR_DIR=\"$WORK/quar\"|" \
    -e "s|^RESET_BK_DIR=\"/var/lib/forgeos/reset-backup\"|RESET_BK_DIR=\"$WORK/resetbk\"|" \
    -e "s|^ETC_DIR=\"/etc\"|ETC_DIR=\"$WORK/etc\"|" \
    -e "s|^USR_ETC_DIR=\"/usr/etc\"|USR_ETC_DIR=\"$WORK/usr-etc\"|" \
    -e "s|^TMP_DIR=\"/tmp\"|TMP_DIR=\"$WORK/tmp\"|" \
    -e "s|^VARTMP_DIR=\"/var/tmp\"|VARTMP_DIR=\"$WORK/var-tmp\"|" \
    "$ENGINE" > "$WORK/fcs"
mkdir -p "$WORK/etc" "$WORK/usr-etc" "$WORK/tmp" "$WORK/var-tmp"
for v in LOG_DIR QUAR_DIR RESET_BK_DIR ETC_DIR USR_ETC_DIR TMP_DIR VARTMP_DIR; do
    if ! grep -q "^$v=\"$WORK/" "$WORK/fcs"; then
        echo "FAIL: could not point $v at the test folder (engine line changed?)"
        exit 1
    fi
done

# --- Fake bin dir: shims for every external tool the engine calls ---
mkdir -p "$WORK/bin"

cat > "$WORK/bin/id" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-u" ]; then echo 0; else exec /usr/bin/id "$@"; fi
EOF

cat > "$WORK/bin/rpm-ostree" <<'EOF'
#!/usr/bin/env bash
echo '{"deployments":[{"booted":true,"container-image-reference":"ostree-image-signed:docker://ghcr.io/x/forgeos:latest"}]}'
EOF

cat > "$WORK/bin/ostree" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_DIFF:-M    hostname}"
EOF

cat > "$WORK/bin/rkhunter" <<'EOF'
#!/usr/bin/env bash
exit "${FAKE_RKH_RC:-0}"
EOF

cat > "$WORK/bin/chkrootkit" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$WORK/bin/clamscan" <<'EOF'
#!/usr/bin/env bash
move_dir=""
for a in "$@"; do
    case "$a" in --move=*) move_dir="${a#--move=}"; break ;; esac
done
if [ -n "${FAKE_INFECTED:-}" ]; then
    echo "$FAKE_INFECTED: Eicar-Test-Signature FOUND"
    if [ -n "$move_dir" ] && [ -f "$FAKE_INFECTED" ]; then
        mv "$FAKE_INFECTED" "$move_dir/" 2>/dev/null || true
        if [ -n "${FAKE_REALPATH:-}" ]; then
            echo "$FAKE_INFECTED (real path: '$FAKE_REALPATH'): moved to '$move_dir/$(basename "$FAKE_INFECTED")'"
        else
            echo "$FAKE_INFECTED: moved to '$move_dir/$(basename "$FAKE_INFECTED")'"
        fi
    fi
    exit 1
fi
exit 0
EOF

chmod +x "$WORK/bin/id" "$WORK/bin/rpm-ostree" "$WORK/bin/ostree" \
         "$WORK/bin/rkhunter" "$WORK/bin/chkrootkit" "$WORK/bin/clamscan"

PATH="$WORK/bin:$PATH"
export PATH
unset PKEXEC_UID 2>/dev/null || true

cat > "$WORK/bin/runuser" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done; shift; exec "$@"
EOF
chmod +x "$WORK/bin/runuser"

# Safety net: if a broken engine ever got past the full-wipe / reset refusals,
# it must not touch this machine. `getent passwd` lists only a fake user whose
# home is inside $WORK (not under /home, so it is never erased), and
# systemctl / flatpak / passwd do nothing.
mkdir -p "$WORK/home/tester"
cat > "$WORK/bin/getent" <<EOF
#!/usr/bin/env bash
if [ "\$#" -eq 1 ] && [ "\$1" = "passwd" ]; then
    echo "root:x:0:0:root:/root:/bin/bash"
    echo "tester:x:1000:1000::$WORK/home/tester:/bin/bash"
    exit 0
fi
exec /usr/bin/getent "\$@"
EOF
for t in systemctl flatpak passwd; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/$t"
done
chmod +x "$WORK/bin/getent" "$WORK/bin/systemctl" "$WORK/bin/flatpak" "$WORK/bin/passwd"

# --- run(): reset per-run dirs, execute the engine copy, capture RC and output ---
run() {
    chmod -R u+rwx "$WORK/log" 2>/dev/null; rm -rf "$WORK/log"
    chmod -R u+rwx "$WORK/quar" 2>/dev/null; rm -rf "$WORK/quar"
    bash "$WORK/fcs" "$@" >"$WORK/out" 2>&1
    RC=$?
}

# --- run_keep(): same as run() but keeps $WORK/log and $WORK/quar (quarantine survives between steps) ---
run_keep() {
    bash "$WORK/fcs" "$@" >"$WORK/out" 2>&1
    RC=$?
}

# --- A: clean scan -> exit 0, report first line says "All clear" ---
run scan
first=""
for report in "$WORK"/log/report-*.txt; do
    [ -f "$report" ] && first="$(head -n1 "$report")"
done
if [ "$RC" -eq 0 ] && printf '%s' "$first" | grep -q "All clear"; then
    pass "A clean scan: exit 0 and report says All clear"
else
    fail "A clean scan (rc=$RC first='$first')"
fi

# --- B: infected file -> exit 1, file quarantined, quarantine.log has exactly 1 line, mode 000 ---
echo eicar > "$WORK/bad.txt"
FAKE_INFECTED="$WORK/bad.txt" run scan
moved="$(find "$WORK/quar" -type f ! -name 'quarantine.log' | head -n1)"
qlines=0
[ -f "$WORK/quar/quarantine.log" ] && qlines="$(wc -l < "$WORK/quar/quarantine.log")"
mode=""
[ -n "$moved" ] && mode="$(stat -c %a "$moved")"
# quarantine.log field 2 = original path, field 4 = threat name
qorig=""; qthreat=""
[ -f "$WORK/quar/quarantine.log" ] && IFS=$'\t' read -r _ qorig _ qthreat _ < "$WORK/quar/quarantine.log"
if [ "$RC" -eq 1 ] && [ ! -e "$WORK/bad.txt" ] && [ "$qlines" = "1" ] && [ "$mode" = "0" ] \
   && [ "$qorig" = "$WORK/bad.txt" ] && [ "$qthreat" = "Eicar-Test-Signature" ]; then
    pass "B infected scan: exit 1, file quarantined (log=1 line with path + threat, mode 0)"
else
    fail "B infected scan (rc=$RC qlines=$qlines mode=${mode:-none} orig='$qorig' threat='$qthreat')"
fi

# --- C: dry-run -> exit 1 but the file is left in place ---
echo eicar > "$WORK/bad.txt"
FAKE_INFECTED="$WORK/bad.txt" run scan --dry-run
if [ "$RC" -eq 1 ] && [ -f "$WORK/bad.txt" ]; then
    pass "C dry-run: exit 1 and file still present"
else
    fail "C dry-run (rc=$RC)"
fi

# --- D: tampered startup file -> exit 2, output mentions TAMPERED ---
FAKE_DIFF="A    ld.so.preload" run scan
if [ "$RC" -eq 2 ] && grep -q "TAMPERED" "$WORK/out"; then
    pass "D tamper detection: exit 2 and TAMPERED in output"
else
    fail "D tamper detection (rc=$RC)"
fi

# --- E: rkhunter tool error -> exit 3 ---
FAKE_RKH_RC=2 run scan
if [ "$RC" -eq 3 ]; then
    pass "E tool error: exit 3 when rkhunter fails hard"
else
    fail "E tool error (rc=$RC)"
fi

# --- F: --help -> exit 0, usage on stdout ---
run --help
if [ "$RC" -eq 0 ] && grep -q "Usage:" "$WORK/out"; then
    pass "F help: exit 0 and Usage shown"
else
    fail "F help (rc=$RC)"
fi

# --- G: bad argument -> exit 3 ---
run bogus
if [ "$RC" -eq 3 ]; then
    pass "G bad arg: exit 3"
else
    fail "G bad arg (rc=$RC)"
fi

# --- H: quarantine list -> exit 0, ID = field 1 of line 2 (tab-separated), threat shown ---
echo eicar > "$WORK/bad.txt"
chmod 640 "$WORK/bad.txt"
FAKE_INFECTED="$WORK/bad.txt" run scan
run_keep quarantine list
ID="$(awk -F'\t' 'NR==2{print $1}' "$WORK/out")"
if [ "$RC" -eq 0 ] && [ -n "$ID" ] && grep -q "Eicar-Test-Signature" "$WORK/out"; then
    pass "H quarantine list: exit 0, ID present and Eicar threat shown"
else
    fail "H quarantine list (rc=$RC id='$ID')"
fi

# --- I: restore without --yes -> exit 3 (refuses) ---
[ -n "$ID" ] || ID="missing"   # keep later cases from touching $WORK/quar itself
chmod u+r "$WORK/quar/$ID"   # engine runs as root and can read a mode-000 file; this test is a normal user, so give it back read first
run_keep quarantine restore "$ID" </dev/null
if [ "$RC" -eq 3 ]; then
    pass "I restore without --yes: exit 3 (refuses)"
else
    fail "I restore without --yes (rc=$RC)"
fi

# --- J: restore --yes -> exit 0, file back with mode 640, quarantine entry gone ---
run_keep quarantine restore "$ID" --yes
if [ "$RC" -eq 0 ] && [ -f "$WORK/bad.txt" ] && [ "$(stat -c %a "$WORK/bad.txt")" = "640" ] \
   && [ ! -e "$WORK/quar/$ID" ]; then
    pass "J restore --yes: exit 0, file restored with mode 640 and quarantine entry gone"
else
    fail "J restore --yes (rc=$RC)"
fi

# --- K: delete --yes -> exit 0, entry gone, list says empty ---
echo eicar > "$WORK/bad.txt"
FAKE_INFECTED="$WORK/bad.txt" run scan
run_keep quarantine list
ID2="$(awk -F'\t' 'NR==2{print $1}' "$WORK/out")"
run_keep quarantine delete "$ID2" --yes
k_rc=$RC; k_gone=0
[ ! -e "$WORK/quar/$ID2" ] && k_gone=1
run_keep quarantine list
k_empty=""
grep -q "Quarantine is empty." "$WORK/out" && k_empty=yes
if [ "$k_rc" -eq 0 ] && [ "$k_gone" = 1 ] && [ -n "$k_empty" ]; then
    pass "K delete --yes: exit 0, entry gone and list says Quarantine is empty"
else
    fail "K delete --yes (rc=$k_rc)"
fi

# --- L: restore with a bad ID -> exit 3 and "Bad ID" in output ---
run quarantine restore ../x --yes
if [ "$RC" -eq 3 ] && grep -q "Bad ID" "$WORK/out"; then
    pass "L bad id: exit 3 and Bad ID shown"
else
    fail "L bad id (rc=$RC)"
fi

# --- M: reset-system --dry-run -> exit 0, KEEP hostname+passwd, REMOVE ld.so.preload, counts right ---
FAKE_DIFF=$'M    hostname\nA    ld.so.preload\nM    passwd' run reset-system --dry-run
if [ "$RC" -eq 0 ] && grep -q "KEEP     /etc/hostname" "$WORK/out" \
   && grep -q "KEEP     /etc/passwd" "$WORK/out" \
   && grep -q "REMOVE   /etc/ld.so.preload" "$WORK/out" \
   && grep -q "1 to remove" "$WORK/out" && grep -q "2 kept" "$WORK/out"; then
    pass "M reset plan: exit 0, KEEP hostname+passwd, REMOVE ld.so.preload, counts right"
else
    fail "M reset plan (rc=$RC)"
fi

# --- N: full-wipe safety -> refuses without WIPE, refuses without a terminal, --dry-run plans ---
run full-wipe --yes NOPE
n1=$RC; n1_ok=0
[ "$n1" -eq 3 ] && ! grep -q "Full Wipe started" "$WORK/out" && n1_ok=1   # refused BEFORE starting
run full-wipe </dev/null
n2=$RC; n2_ok=0
[ "$n2" -eq 3 ] && ! grep -q "Full Wipe started" "$WORK/out" && n2_ok=1   # refused BEFORE starting
run full-wipe --dry-run
n3=$RC; n3_ok=""
[ "$n3" -eq 0 ] && grep -q "Full Wipe plan" "$WORK/out" \
    && grep -q "SKIP     tester" "$WORK/out" && n3_ok=yes   # fake home is outside /home -> never erased
if [ "$n1_ok" = 1 ] && [ "$n2_ok" = 1 ] && [ -n "$n3_ok" ]; then
    pass "N full-wipe safety: refuses without WIPE, refuses without terminal, dry-run plans"
else
    fail "N full-wipe safety (rcs=$n1/$n2/$n3)"
fi

# --- P: file reached through a symlinked folder -> log records the REAL path + threat, restore puts it back there ---
mkdir -p "$WORK/realdir"
ln -s "$WORK/realdir" "$WORK/linkdir"
echo eicar > "$WORK/realdir/bad.txt"
FAKE_INFECTED="$WORK/linkdir/bad.txt" FAKE_REALPATH="$WORK/realdir/bad.txt" run scan
p_rc=$RC
p_orig="$(awk -F'\t' 'NR==1{print $2}' "$WORK/quar/quarantine.log" 2>/dev/null)"
p_threat="$(awk -F'\t' 'NR==1{print $4}' "$WORK/quar/quarantine.log" 2>/dev/null)"
run_keep quarantine list
PID="$(awk -F'\t' 'NR==2{print $1}' "$WORK/out")"
[ -n "$PID" ] || PID="missing"
chmod u+r "$WORK/quar/$PID" 2>/dev/null
run_keep quarantine restore "$PID" --yes
if [ "$p_rc" -eq 1 ] && [ "$p_orig" = "$WORK/realdir/bad.txt" ] && [ "$p_threat" = "Eicar-Test-Signature" ] \
   && [ "$RC" -eq 0 ] && [ -f "$WORK/realdir/bad.txt" ]; then
    pass "P symlinked folder: real path + threat logged, restore puts file back in the real folder"
else
    fail "P symlinked folder (scan rc=$p_rc orig='$p_orig' threat='$p_threat' restore rc=$RC)"
fi

# --- Q: password reminder -> reset plan says REMIND (no passwd -e anywhere), reminder file is right ---
run reset-system --dry-run
q1=$RC; q_ok=0
grep -q "REMIND   user tester will be asked to choose a new password" "$WORK/out" \
    && ! grep -qE '^[^#]*passwd -e' "$ENGINE" && q_ok=1
sed -n '/^add_password_reminder() {/,/^}/p' "$WORK/fcs" > "$WORK/apr.sh"
# shellcheck source=/dev/null
. "$WORK/apr.sh"
add_password_reminder tester "$WORK/home/tester"
q2=$?
QF="$WORK/home/tester/.config/autostart/forgeos-password-reminder.desktop"
REMINDER="$ROOT/files/system/usr/libexec/forgeos-password-reminder"
if [ "$q1" -eq 0 ] && [ "$q_ok" = 1 ] && [ "$q2" -eq 0 ] \
   && [ "$(head -n 1 "$QF" 2>/dev/null)" = "[Desktop Entry]" ] \
   && grep -qx "Exec=/usr/libexec/forgeos-password-reminder" "$QF" \
   && [ -f "$REMINDER" ] && bash -n "$REMINDER" \
   && grep -q "/usr/libexec/forgeos-password-reminder" "$ROOT/files/scripts/forgeos-setup.sh"; then
    pass "Q password reminder: plan says REMIND, no passwd -e, reminder file + script + chmod in place"
else
    fail "Q password reminder (plan rc=$q1 plan_ok=$q_ok add rc=$q2)"
fi

# --- O: REAL ClamAV (only when REAL_CLAMAV=1) -> exit 1, file quarantined, threat name from a custom test signature ---
# Harmless sample + our own md5 signature (no EICAR anywhere). Custom signatures get ".UNOFFICIAL" added.
if [ "${REAL_CLAMAV:-0}" = "1" ]; then
    REAL_CLAMSCAN="${REAL_CLAMSCAN:-/usr/bin/clamscan}"
    mkdir -p "$WORK/scan"
    echo "ForgeOS harmless test sample" > "$WORK/scan/sample.txt"
    printf '%s:%s:ForgeOS.Test.Signature\n' \
        "$(md5sum < "$WORK/scan/sample.txt" | cut -d' ' -f1)" \
        "$(stat -c %s "$WORK/scan/sample.txt")" > "$WORK/test.hdb"
    # Wrapper: keep only the engine's "-" options, use our signature file, scan only $WORK/scan
    cat > "$WORK/bin/clamscan" <<EOF
#!/usr/bin/env bash
opts=()
for a in "\$@"; do
    case "\$a" in -*) opts+=("\$a") ;; esac
done
exec "$REAL_CLAMSCAN" "\${opts[@]}" -d "$WORK/test.hdb" "$WORK/scan"
EOF
    chmod +x "$WORK/bin/clamscan"
    run scan --dry-run
    o_dry=$RC; o_dry_ok=0
    [ "$o_dry" -eq 1 ] && [ -f "$WORK/scan/sample.txt" ] && o_dry_ok=1
    run scan
    omoved="$(find "$WORK/quar" -type f ! -name 'quarantine.log' | head -n1)"
    omode=""; [ -n "$omoved" ] && omode="$(stat -c %a "$omoved")"
    oorig=""; othreat=""
    [ -f "$WORK/quar/quarantine.log" ] && IFS=$'\t' read -r _ oorig _ othreat _ < "$WORK/quar/quarantine.log"
    if [ "$o_dry_ok" = 1 ] && [ "$RC" -eq 1 ] && [ ! -e "$WORK/scan/sample.txt" ] && [ "$omode" = "0" ] \
       && [ "$oorig" = "$WORK/scan/sample.txt" ] && [ "$othreat" = "ForgeOS.Test.Signature.UNOFFICIAL" ]; then
        pass "O real ClamAV: dry-run leaves file, scan exits 1 and quarantines it with the real threat name"
    else
        fail "O real ClamAV (dry rc=$o_dry rc=$RC mode=${omode:-none} orig='$oorig' threat='$othreat')"
    fi
else
    skip "O real ClamAV (set REAL_CLAMAV=1 to run)"
fi

echo "failures: $failures"
if [ "$failures" -gt 0 ]; then exit 1; fi
exit 0

#!/usr/bin/env bash
# tests/test-clean-sweep.sh — Job 3 Step 8a: scan tests for files/system/usr/bin/forgeos-cleansweep.
# Runs as a normal user (no root). The engine copy is sed-rewritten so its log/quarantine/reset-backup
# dirs point inside a private mktemp work dir, and the external tools it calls are replaced with fake
# shims in $WORK/bin that honor FAKE_DIFF / FAKE_RKH_RC / FAKE_INFECTED.
set -uo pipefail

ROOT="${1:-.}"
ENGINE="$ROOT/files/system/usr/bin/forgeos-cleansweep"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
failures=0

if [ ! -f "$ENGINE" ]; then
    echo "FAIL: engine not found: $ENGINE"
    exit 1
fi

WORK="$(mktemp -d)"
trap 'chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

# --- Copy the engine and point its three dir vars at private locations ---
sed \
    -e "s|^LOG_DIR=\"/var/log/forgeos/clean-sweep\"|LOG_DIR=\"$WORK/log\"|" \
    -e "s|^QUAR_DIR=\"/var/lib/forgeos/quarantine\"|QUAR_DIR=\"$WORK/quar\"|" \
    -e "s|^RESET_BK_DIR=\"/var/lib/forgeos/reset-backup\"|RESET_BK_DIR=\"$WORK/resetbk\"|" \
    "$ENGINE" > "$WORK/fcs"

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
        echo "$FAKE_INFECTED: moved to '$move_dir/$(basename "$FAKE_INFECTED")'"
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

# --- run(): reset per-run dirs, execute the engine copy, capture RC and output ---
run() {
    chmod -R u+rwx "$WORK/log" 2>/dev/null; rm -rf "$WORK/log"
    chmod -R u+rwx "$WORK/quar" 2>/dev/null; rm -rf "$WORK/quar"
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

echo "failures: $failures"
if [ "$failures" -gt 0 ]; then exit 1; fi
exit 0

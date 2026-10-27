#!/usr/bin/env bash
# tests/test-cool-stuff.sh — automatic checks for Job 4 Step 2 ("Cool Stuff").
# Verifies the two ForgeOS menu-button .desktop files (Android Apps / Game
# Streaming): they exist, contain no carriage return bytes, and carry the
# exact required lines; validates them with desktop-file-validate when that
# tool is installed. Also checks that recipes/common-modules.yml has a `type: dnf`
# module whose install packages include the exact line `- kde-connect`.
# Uses only bash + grep/sed/awk — no Python, no yq (nothing to install).
set -euo pipefail

ROOT="${1:-.}"

ANDROID="$ROOT/files/system/usr/share/applications/forgeos-android-apps.desktop"
STREAMING="$ROOT/files/system/usr/share/applications/forgeos-game-streaming.desktop"
RECIPE="$ROOT/recipes/common-modules.yml"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
skip() { echo "SKIP: $1"; }

# Check 1 — both .desktop files exist.
if [[ -f "$ANDROID" && -f "$STREAMING" ]]; then
    pass "both menu button .desktop files exist (forgeos-android-apps.desktop, forgeos-game-streaming.desktop)"
else
    fail "missing menu button .desktop file(s): expected $ANDROID and $STREAMING"
fi

# Check 2 — neither .desktop file contains a carriage return (CR) byte.
cr_bad=""
for f in "$ANDROID" "$STREAMING"; do
    if [[ -f "$f" ]] && LC_ALL=C grep -q $'\r' -- "$f"; then
        cr_bad="${cr_bad:+$cr_bad, }$f"
    fi
done
if [[ -z "$cr_bad" ]]; then
    pass "no carriage return (CR) bytes in the .desktop files"
else
    fail "carriage return (CR) byte found in: $cr_bad"
fi

# Check 3 — each file starts with [Desktop Entry] and has its exact required lines.
check_required_lines() {
    local f name_line exec_line problems first line
    f="$1"
    name_line="$2"
    exec_line="$3"
    problems=""
    if [[ ! -f "$f" ]]; then
        fail "cannot check $f (file missing)"
        return 0
    fi
    first="$(head -n 1 -- "$f")"
    if [[ "$first" != "[Desktop Entry]" ]]; then
        problems="line 1 is not exactly [Desktop Entry] (got: ${first:-<empty>})"
    fi
    for line in "Type=Application" "Terminal=false" "$name_line" "$exec_line"; do
        if ! grep -Fxq -- "$line" "$f"; then
            problems="${problems:+$problems; }missing exact line: $line"
        fi
    done
    if [[ -z "$problems" ]]; then
        pass "$(basename -- "$f") has [Desktop Entry] on line 1 and the required Type/Terminal/Name/Exec lines"
    else
        fail "$(basename -- "$f"): $problems"
    fi
}

check_required_lines "$ANDROID" "Name=Android Apps Setup" "Exec=konsole --hold -e ujust setup-waydroid"
check_required_lines "$STREAMING" "Name=Game Streaming Setup" "Exec=konsole --hold -e ujust setup-sunshine"

# Check 4 — desktop-file-validate, only when the tool is installed.
if command -v desktop-file-validate >/dev/null 2>&1; then
    bad=""
    for f in "$ANDROID" "$STREAMING"; do
        if [[ ! -f "$f" ]]; then
            continue # already reported by check 1
        fi
        if ! desktop-file-validate "$f"; then
            bad="${bad:+$bad, }$f"
        fi
    done
    if [[ -z "$bad" ]]; then
        pass "desktop-file-validate accepts both .desktop files"
    else
        fail "desktop-file-validate rejected: $bad"
    fi
else
    skip "desktop-file-validate not installed — skipping desktop file validation (install desktop-file-utils to enable)"
fi

# Check 5 — common-modules.yml has a `type: dnf` module whose install packages include `- kde-connect`.
if [[ ! -f "$RECIPE" ]]; then
    fail "cannot find recipe file: $RECIPE"
else
    # Print the entry if it appears exactly as `kde-connect` under a `packages:`
    # list inside a `type: dnf` module. Tolerates CRLF input and comments.
    found="$(awk '
        function lead_ws(s,    t) { t = s; sub(/^[ \t]*/, "", t); return length(s) - length(t) }
        { sub(/\r$/, "") } # tolerate CRLF input
        /^[ \t]*-[ \t]+type:[ \t]*dnf[ \t]*(#.*)?$/ { in_dnf = 1; next }
        in_dnf && /^[ \t]*-[ \t]+type:/ { in_dnf = 0; in_pkgs = 0; next } # a different module ends the dnf block
        in_dnf && /^[ \t]*packages:[ \t]*(#.*)?$/ { in_pkgs = 1; indent = lead_ws($0); next }
        in_pkgs && /^[ \t]*$/ { next }
        in_pkgs {
            if (lead_ws($0) <= indent) { in_pkgs = 0; next } # dedent ends the block
            if ($0 ~ /^[ \t]*#/) next                         # comment inside the block
            if ($0 !~ /^[ \t]*-[ \t]*/) { in_pkgs = 0; next } # any other line ends it
            entry = $0
            sub(/^[ \t]*-[ \t]*/, "", entry)
            sub(/[ \t]+#.*$/, "", entry)
            gsub(/[ \t]+$/, "", entry)
            if (entry == "kde-connect") print entry
        }
    ' "$RECIPE")"
    if [[ "$found" == "kde-connect" ]]; then
        pass "$RECIPE has a type: dnf module whose install packages include - kde-connect"
    else
        fail "$RECIPE does not have a type: dnf module with the exact package line - kde-connect"
    fi
fi

echo "----------------------------------------"
if (( failures > 0 )); then
    echo "RESULT: ${failures} check(s) failed" >&2
    exit 1
fi
echo "RESULT: all checks passed"

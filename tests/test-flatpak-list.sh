#!/usr/bin/env bash
# tests/test-flatpak-list.sh — automatic check for the default Flatpak app list (Step 2).
# Reads recipes/common-modules.yml (or a path given as $1) and verifies that the
# `install:` list is complete, duplicate-free, free of the end-of-life
# Thunderbird ID, and made up of valid reverse-DNS app IDs.
# Uses only bash + grep/sed/awk — no Python, no yq (nothing to install).
set -euo pipefail

RECIPE="${1:-recipes/common-modules.yml}"

if [[ ! -f "$RECIPE" ]]; then
    echo "FAIL: cannot find recipe file: $RECIPE" >&2
    exit 1
fi

# The approved app list (blueprint Job 2, Claude-verified on Flathub 2026-10-23).
APPROVED_IDS=(
    com.brave.Browser
    com.usebottles.bottles
    com.heroicgameslauncher.hgl
    com.jeffser.Alpaca
    com.github.tchx84.Flatseal
    org.onlyoffice.desktopeditors
    org.mozilla.thunderbird
    org.gimp.GIMP
    com.github.PintaProject.Pinta
    org.kde.kdenlive
    com.obsproject.Studio
    org.kde.haruna
    org.kde.elisa
    org.kde.gwenview
    org.keepassxc.KeePassXC
    org.gnome.World.PikaBackup
    io.missioncenter.MissionCenter
    org.localsend.localsend_app
    com.rustdesk.RustDesk
    com.github.jeromerobert.pdfarranger
    org.kde.okular
    org.kde.skanpage
    org.kde.kcalc
    org.kde.filelight
    it.mijorus.gearlever
    net.mkiol.SpeechNote
    com.github.wwmm.easyeffects
    com.moonlight_stream.Moonlight
    io.gitlab.adhami3310.Impression
)

EOL_ID='org.mozilla.Thunderbird' # end-of-life ID — must not appear anywhere (case-sensitive)
ID_RE='^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2,}$'

# Print every app ID listed under an `install:` key, one per line.
# Strips the leading `- `, trailing whitespace and any `# comment`.
extract_install_ids() {
    awk '
        function lead_ws(s,    t) { t = s; sub(/^[ \t]*/, "", t); return length(s) - length(t) }
        { sub(/\r$/, "") } # tolerate CRLF input
        /^[ \t]*install:[ \t]*(#.*)?$/ { in_install = 1; indent = lead_ws($0); next }
        in_install && /^[ \t]*$/ { next }
        in_install {
            if (lead_ws($0) <= indent) { in_install = 0; next } # dedent ends the block
            if ($0 ~ /^[ \t]*#/) next                            # group comment inside the block
            if ($0 !~ /^[ \t]*-[ \t]*/) { in_install = 0; next } # any other line ends it
            entry = $0
            sub(/^[ \t]*-[ \t]*/, "", entry)
            sub(/[ \t]+#.*$/, "", entry)
            gsub(/[ \t]+$/, "", entry)
            if (entry != "") print entry
        }
    ' "$RECIPE"
}

INSTALL_IDS="$(extract_install_ids)"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# Check 1 — every approved ID is present in the install list.
missing=""
for id in "${APPROVED_IDS[@]}"; do
    if ! grep -Fxq -- "$id" <<<"$INSTALL_IDS"; then
        missing="${missing:+$missing, }$id"
    fi
done
if [[ -z "$missing" ]]; then
    pass "all ${#APPROVED_IDS[@]} approved app IDs are present in $RECIPE"
else
    fail "approved app ID(s) missing from install list: $missing"
fi

# Check 2 — no ID is listed more than once under install:.
dups="$(awk 'NF { c[$0]++ } END { for (id in c) if (c[id] > 1) print id }' <<<"$INSTALL_IDS")"
if [[ -z "$dups" ]]; then
    pass "no app ID is listed more than once under install:"
else
    fail "app ID(s) listed more than once: ${dups//$'\n'/, }"
fi

# Check 3 — the end-of-life Thunderbird ID must not appear anywhere (case-sensitive).
if grep -Fq -- "$EOL_ID" "$RECIPE"; then
    fail "end-of-life ID $EOL_ID found in $RECIPE (use lowercase org.mozilla.thunderbird)"
else
    pass "end-of-life ID $EOL_ID does not appear in $RECIPE"
fi

# Check 4 — every install entry is a valid reverse-DNS app ID.
invalid=""
while IFS= read -r id; do
    if [[ -n "$id" && ! "$id" =~ $ID_RE ]]; then
        invalid="${invalid:+$invalid, }$id"
    fi
done <<<"$INSTALL_IDS"
if [[ -z "$invalid" ]]; then
    pass "every install entry is a valid reverse-DNS app ID"
else
    fail "invalid app ID(s) under install: $invalid"
fi

echo "----------------------------------------"
if (( failures > 0 )); then
    echo "RESULT: ${failures} check(s) failed" >&2
    exit 1
fi
echo "RESULT: all checks passed"

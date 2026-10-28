#!/usr/bin/env bash
# Tests for GhostFinder (Job 12), case T: the build files - run bits, background watch on for every
# user, the free packages, the units, the menu entry, the CI steps, the beep, small LF-only files.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-ghost-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/ghost-fakes.sh
. "$ROOT/tests/ghost-fakes.sh"

SETUP="$ROOT/files/scripts/forgeos-setup.sh"; LIB="$FORGEOS_GHOST_LIB/ghostlib"; U="$ROOT/files/system/usr/lib/systemd/user"
D="$ROOT/files/system/usr/share/applications/forgeos-ghostfinder.desktop"
check T1 'grep -q "^chmod 0755 .* /usr/bin/forgeos-ghost /usr/bin/forgeos-ghost-gui /usr/libexec/forgeos-ghost-meter\( \|$\)" "$SETUP" && grep -qx "systemctl --global enable forgeos-ghost-watch.timer" "$SETUP"'
check T2 '(for p in python3-dbus avahi-tools hwdata; do grep -q "^        - $p  *# GhostFinder (Job 12)" "$ROOT/recipes/common-modules.yml" || exit 1; done) && grep -q "GHOST_PY=/usr/bin/python3 bash tests/test-ghost-real.sh ." "$ROOT/.github/workflows/tests.yml"'
check T3 'python3 -c "import ast,sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]" "$ENGINE" "$LIB"/*.py && [ "$(head -n 1 "$ENGINE")" = "#!/usr/bin/python3" ] && [ ! -e "$LIB/__pycache__" ]'
check T4 '(for f in "$ENGINE" "$GUI" "$METER" "$LIB"/*.py "$U"/forgeos-ghost-watch.* "$D" "$ROOT"/tests/*ghost*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  too big, CRLF or no last newline: $f"; exit 1; }; done)'
check T5 'grep -qx "ExecStart=/usr/bin/forgeos-ghost watch-tick" "$U/forgeos-ghost-watch.service" && grep -qx "Nice=19" "$U/forgeos-ghost-watch.service" && grep -qx "OnUnitActiveSec=10min" "$U/forgeos-ghost-watch.timer" && grep -qx "WantedBy=timers.target" "$U/forgeos-ghost-watch.timer"'
check T6 'grep -qx "Exec=/usr/bin/forgeos-ghost-gui" "$D" && grep -qx "Categories=System;Security;" "$D" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$D"; }'
check T7 'python3 -c "import wave,sys; w=wave.open(sys.argv[1]); assert (w.getnchannels(), w.getframerate(), w.getnframes()) == (1, 22050, 2205)" "$(G beep-file)"'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1

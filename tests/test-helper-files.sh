#!/usr/bin/env bash
# Tests for Forge Helper (Job 13c), cases Y-Z: the files are complete and in the image, the help
# library and the test questions are good, the selftest scores, and "models" only switches to a better model.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-helper-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/helper-fakes.sh
. "$ROOT/tests/helper-fakes.sh"
T=$'\t'
U="$ROOT/files/system/usr"
LIB="$U/lib/forgeos-helper/helperlib"

# Y: every file is there, small enough for the Rabbit Team (< 6000 characters), and Python 3.10-safe
MODS="__init__ actions ai checks cli helpdocs looks memory router rulelist rules selftest talk tools watch"
for m in $MODS; do [ -f "$LIB/$m.py" ] || echo "missing $m.py" >> "$WORK/missing"; done
for f in "$U/bin/forgeos-helper" "$U/bin/forgeos-helper-gui" "$U/libexec/forgeos-helper-krunner" \
  "$U/share/applications/forgeos-helper.desktop" "$U/share/krunner/dbusplugins/forgeos-helper.desktop" \
  "$U/share/dbus-1/services/org.forgeos.helper.service" "$U/share/forgeos/helper/candidates.txt" \
  "$U/lib/systemd/user/forgeos-helper-watch.service" "$U/lib/systemd/user/forgeos-helper-watch.timer" \
  "$U/lib/systemd/user/forgeos-helper-warm.service" "$U/lib/systemd/user/forgeos-helper-models.service" \
  "$U/lib/systemd/user/forgeos-helper-models.timer"; do [ -f "$f" ] || echo "missing $f" >> "$WORK/missing"; done
check Y1 '[ ! -s "$WORK/missing" ]'
BIG="$(find "$LIB" "$U/bin/forgeos-helper"* "$U/libexec/forgeos-helper-krunner" "$U/share/forgeos/helper" "$ROOT"/tests/*helper* -type f -size +5999c ! -name "*.pyc")"
check Y2 '[ -z "$BIG" ] || { echo "  too big: $BIG"; false; }'
check Y3 'python3 -B -c "import ast,sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "$U/bin/forgeos-helper" "$U/libexec/forgeos-helper-krunner"'
check Y4 'grep -q "^Exec=/usr/bin/forgeos-helper-gui$" "$U/share/applications/forgeos-helper.desktop" && grep -q "^X-KDE-Shortcuts=Meta+H$" "$U/share/applications/forgeos-helper.desktop"'
check Y5 'grep -q "^X-Plasma-API=DBus$" "$U/share/krunner/dbusplugins/forgeos-helper.desktop" && grep -q "^X-Plasma-DBusRunner-Service=org.forgeos.helper$" "$U/share/krunner/dbusplugins/forgeos-helper.desktop" && grep -q "^X-Plasma-DBusRunner-Path=/runner$" "$U/share/krunner/dbusplugins/forgeos-helper.desktop" && grep -q "^Exec=/usr/libexec/forgeos-helper-krunner$" "$U/share/dbus-1/services/org.forgeos.helper.service" && grep -q "^BUS_NAME = \"org.forgeos.helper\"$" "$U/libexec/forgeos-helper-krunner"'
if command -v desktop-file-validate >/dev/null 2>&1; then
  check Y6 'desktop-file-validate "$U/share/applications/forgeos-helper.desktop"'
else
  echo "SKIP Y6 desktop-file-validate is not installed"
fi
S="$ROOT/files/scripts/forgeos-setup.sh"
check Y7 'for p in /usr/bin/forgeos-helper /usr/bin/forgeos-helper-gui /usr/libexec/forgeos-helper-krunner; do grep -q "^chmod 0755 .*$p\( \|$\)" "$S" || exit 1; done; grep -q "^systemctl --global enable forgeos-helper-watch.timer forgeos-helper-warm.service forgeos-helper-models.timer$" "$S"'
check Y8 'grep -q "^        - python3-gobject-base " "$ROOT/recipes/common-modules.yml" && grep -q "^        - python3-dbus " "$ROOT/recipes/common-modules.yml" && grep -q "^OnUnitActiveSec=15min$" "$U/lib/systemd/user/forgeos-helper-watch.timer" && grep -q "^Nice=19$" "$U/lib/systemd/user/forgeos-helper-watch.service"'
check Y9 'grep -q "bash tests/test-helper-files.sh ." "$ROOT/.github/workflows/tests.yml" && grep -q "bash tests/test-helper-krunner.sh ." "$ROOT/.github/workflows/tests.yml" && grep -q "bash tests/test-helper-brains.sh ." "$ROOT/.github/workflows/tests.yml"'

# Z: help library (60+ good cards), 300+ test questions that name real tools and cards, scores
CARDS="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import helpdocs
c = helpdocs.load(); print(len(c)); print(min(len(x['body']) for x in c)); print(max(len(x['body']) for x in c))" "$FORGEOS_HELPER_LIB")"
check Z1 '[ "$(sed -n 1p <<< "$CARDS")" -ge 60 ] && [ "$(sed -n 2p <<< "$CARDS")" -ge 40 ] && [ "$(sed -n 3p <<< "$CARDS")" -le 900 ] && [ "$(ls "$U/share/forgeos/helper/help" | wc -l)" = "$(sed -n 1p <<< "$CARDS")" ]'
check Z2 'python3 -B "$ROOT/tests/helper-check-tests.py" "$FORGEOS_HELPER_LIB" >/dev/null'
OUT="$(F selftest --no-ai)"
RULES="$(awk -F "$T" '$1 == "SCORE" {print int($2)}' <<< "$OUT")"
check Z3 '[ "${RULES:-0}" -ge 90 ] && grep -q "^Score: " <<< "$OUT"'
start_fake_ollama
cp "$ROOT/tests/helper-ai-map.json" "$WORK/ai-map"
echo '{"models":[{"name":"gemma4:e4b"}]}' > "$WORK/ai-tags"
OUT="$(F selftest)"
WITH_AI="$(awk -F "$T" '$1 == "SCORE" {print int($2)}' <<< "$OUT")"
check Z4 '[ "${WITH_AI:-0}" -ge 97 ] && [ "$WITH_AI" -gt "$RULES" ] && grep -q "\"tool\"" "$WORK/ai-bodies.jsonl"'

echo
if [ "$failures" -eq 0 ]; then echo "All Forge Helper tests Y-Z passed."; else echo "$failures Forge Helper test(s) failed."; fi
exit "$((failures > 0))"

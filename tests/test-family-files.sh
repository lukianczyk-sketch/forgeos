#!/usr/bin/env bash
# Tests for Family Mode (Job 13), case R: the build files - run bits, menu entries, the CI step,
# Python that parses, small LF-only files (Cline limit), no new packages needed.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-family-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/family-fakes.sh
. "$ROOT/tests/family-fakes.sh"

SETUP="$ROOT/files/scripts/forgeos-setup.sh"; LIB="$FORGEOS_FAMILY_LIB/familylib"
A="$ROOT/files/system/usr/share/applications"; M="$ROOT/recipes/common-modules.yml"
check R1 'grep -q "^chmod 0755 .* /usr/libexec/forgeos-ghost-meter /usr/bin/forgeos-family /usr/bin/forgeos-family-gui /usr/libexec/forgeos-family-call\( \|$\)" "$SETUP"'
check R2 'grep -qx "Exec=/usr/bin/forgeos-family-gui" "$A/forgeos-family.desktop" && grep -qx "Exec=/usr/libexec/forgeos-family-call" "$A/forgeos-callhelp.desktop" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$A/forgeos-family.desktop" "$A/forgeos-callhelp.desktop"; }'
check R3 'python3 -c "import ast,sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]" "$ENGINE" "$LIB"/*.py && [ "$(head -n 1 "$ENGINE")" = "#!/usr/bin/python3" ] && [ ! -e "$LIB/__pycache__" ]'
check R4 '(for f in "$ENGINE" "$GUI" "$CALL" "$LIB"/*.py "$A"/forgeos-family.desktop "$A"/forgeos-callhelp.desktop "$ROOT"/tests/*family*; do [ "$(wc -c < "$f")" -lt 6000 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  too big, CRLF, tab or no last newline: $f"; exit 1; }; done)'
check R5 'grep -q "bash tests/test-family-files.sh ." "$ROOT/.github/workflows/tests.yml" && (for p in kde-connect libnotify python3; do grep -q "^        - $p\( \|$\)" "$M" || exit 1; done) && grep -q "^          - com.rustdesk.RustDesk " "$M"'
check R6 'grep -qx "Name=Family Mode" "$A/forgeos-family.desktop" && grep -qx "Name=Call for help" "$A/forgeos-callhelp.desktop" && (for d in forgeos-scamshield forgeos-askpc; do [ -f "$A/$d.desktop" ] || exit 1; done)'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1

#!/usr/bin/env bash
# tests/test-recipes.sh — checks the two ForgeOS images (NVIDIA variant, 2026-10-26).
# recipe.yml (forgeos, AMD/Intel) and recipe-nvidia.yml (forgeos-nvidia) must
# differ ONLY in name/base, and both must load the one shared module list
# recipes/common-modules.yml. build.yml must build both.
# Uses only bash + grep/awk (plus python3-yaml if it is installed).
set -uo pipefail

ROOT="${1:-.}"
R="$ROOT/recipes/recipe.yml"
N="$ROOT/recipes/recipe-nvidia.yml"
C="$ROOT/recipes/common-modules.yml"
B="$ROOT/.github/workflows/build.yml"
export R N C B   # used inside the check strings
failures=0

check() {
  local name=$1 cond=$2
  if eval "$cond"; then echo "PASS $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}

check A1 '[ -f "$R" ] && [ -f "$N" ] && [ -f "$C" ] && [ -f "$B" ]'
check A2 '! LC_ALL=C grep -q $'"'"'\r'"'"' "$R" "$N" "$C" "$B"'
check B1 'grep -qx "name: forgeos" "$R" && grep -qx "base-image: ghcr.io/ublue-os/bazzite" "$R" && grep -qx "image-version: stable" "$R"'
check B2 'grep -qx "name: forgeos-nvidia" "$N" && grep -qx "base-image: ghcr.io/ublue-os/bazzite-nvidia-open" "$N" && grep -qx "image-version: stable" "$N"'
# Each recipe: exactly one module, the shared file, and no modules of its own.
for f in "$R" "$N"; do
  check "C1 $(basename "$f")" '[ "$(grep -cx "  - from-file: common-modules.yml" "$f")" -eq 1 ] && ! grep -q "^ *- type:" "$f" && [ "$(grep -cx "modules:" "$f")" -eq 1 ]'
done
check D1 '[ "$(grep -cx "modules:" "$C")" -eq 1 ] && ! grep -q "^name:\|^base-image:\|^ *- from-file" "$C"'
for t in files dnf script default-flatpaks signing; do
  check "D2 $t" '[ "$(grep -cx "  - type: $t" "$C")" -eq 1 ]'
done
check D3 '[ "$(grep -x "  - type: [a-z-]*" "$C" | tail -n 1)" = "  - type: signing" ]'
check E1 'grep -qx "          - recipe.yml *\(#.*\)\?" "$B" && grep -qx "          - recipe-nvidia.yml *\(#.*\)\?" "$B"'

if python3 -c "import yaml" 2>/dev/null; then
  check F1 'python3 - "$R" "$N" "$C" <<'"'"'PY'"'"'
import sys, yaml
r, n, c = (yaml.safe_load(open(p)) for p in sys.argv[1:])
assert r["modules"] == n["modules"] == [{"from-file": "common-modules.yml"}]
assert [m["type"] for m in c["modules"]] == ["files", "dnf", "script", "default-flatpaks", "signing"]
assert set(r) == set(n) == {"name", "description", "base-image", "image-version", "modules"}
PY'
else
  echo "SKIP F1 (python3-yaml not installed)"
fi

echo
if [ "$failures" -eq 0 ]; then echo "All recipe tests passed."; else echo "$failures recipe test(s) failed."; exit 1; fi

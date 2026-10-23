#!/usr/bin/env bash
# Automated tests for forgeos-ai-setup (Step 5).
# Runs the --dry-run "brain" with fake VRAM values and checks the chosen model tag.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
AI_SETUP="$REPO_ROOT/files/system/usr/bin/forgeos-ai-setup"

if [[ ! -f "$AI_SETUP" ]]; then
    echo "FAIL: cannot find $AI_SETUP" >&2
    exit 1
fi

# check_case <vram_mb> <expected_tag>: run one dry-run and compare the chosen tag.
check_case() {
    local vram_mb=$1 expected=$2 output tag
    if ! output=$(FORGEOS_FAKE_VRAM_MB="$vram_mb" bash "$AI_SETUP" --dry-run 2>&1); then
        echo "FAIL VRAM=${vram_mb} MB — forgeos-ai-setup exited non-zero:"
        printf '%s\n' "$output" | sed 's/^/    /'
        return 1
    fi
    if grep -q 'unknown size' <<<"$output"; then
        echo "FAIL VRAM=${vram_mb} MB — output contains 'unknown size'"
        return 1
    fi
    tag=$(printf '%s\n' "$output" | awk '/^Model: / { sub(/^Model: /, ""); sub(/ .*/, ""); print; exit }')
    if [[ -n "$tag" && "$tag" == "$expected" ]]; then
        echo "PASS VRAM=${vram_mb} MB -> ${tag}"
        return 0
    fi
    echo "FAIL VRAM=${vram_mb} MB — expected '${expected}', got '${tag:-<no Model line>}'"
    return 1
}

failures=0
total=0
for pair in \
    "0 gemma4:e2b" \
    "4096 gemma4:e2b" \
    "7999 gemma4:e2b" \
    "8000 gemma4:e4b" \
    "11999 gemma4:e4b" \
    "12000 gpt-oss:20b" \
    "16384 gpt-oss:20b" \
    "19999 gpt-oss:20b" \
    "20000 qwen3.8:27b" \
    "24576 qwen3.8:27b"; do
    total=$((total + 1))
    vram_mb=${pair% *}
    expected=${pair#* }
    if check_case "$vram_mb" "$expected"; then
        :
    else
        failures=$((failures + 1))
    fi
done

echo "----------------------------------------"
if (( failures > 0 )); then
    echo "RESULT: ${failures} of ${total} cases FAILED" >&2
    exit 1
fi
echo "RESULT: all ${total} cases passed"

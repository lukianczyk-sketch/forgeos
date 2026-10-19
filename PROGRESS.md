# ForgeOS — Rabbit Team progress log

(Rabbit appends one report per blueprint step below.)

## Step 1 — Find the Ollama download (research only) — 2026-10-19
Files changed: PROGRESS.md (this report only; no code written, as required by Step 1)
What I did: Checked https://github.com/ollama/ollama/releases/latest and its API for the latest release and asset names. Verified all three model tags on https://ollama.com/library. Findings below.

Findings:
- Latest Ollama version: **v0.40.6** (published 2026-10-16)
- Linux x86-64 (amd64) download file: **`ollama-linux-amd64.tar.zst`** — it is `.tar.zst`, NOT `.tgz`.
  Full URL: https://github.com/ollama/ollama/releases/download/v0.40.6/ollama-linux-amd64.tar.zst
- Model tags on ollama.com/library — all three exist exactly as written in the blueprint (no corrections needed):
  - `qwen3.6:27b` ✅ exists (site lists it at 18GB–19GB; a `qwen3.6:27b-q4_K_M` variant is listed at 17GB)
  - `gpt-oss:20b` ✅ exists (listed at 14GB — matches the blueprint's ~14 GB)
  - `gemma4:e2b` ✅ exists (site lists it at 4.6GB–7.5GB)

What I ran + output: Fetched https://github.com/ollama/ollama/releases/latest and https://api.github.com/repos/ollama/ollama/releases/latest via web fetch; also ran in PowerShell: `Invoke-RestMethod -Uri 'https://api.github.com/repos/ollama/ollama/releases/latest' | Select-Object -ExpandProperty assets | ForEach-Object { $_.name }` → output (asset names): install.ps1, install.sh, ollama-darwin.tgz, Ollama-darwin.zip, ollama-linux-amd64-mlx.tar.zst, ollama-linux-amd64-rocm.tar.zst, **ollama-linux-amd64.tar.zst**, ollama-linux-arm64-jetpack5.tar.zst, ollama-linux-arm64-jetpack6.tar.zst, ollama-linux-arm64.tar.zst, ollama-windows-amd64-mlx.zip, ollama-windows-amd64-rocm.zip, ollama-windows-amd64.zip, ollama-windows-arm64.zip, Ollama.dmg, OllamaSetup.exe, sha256sum.txt. Fetched https://ollama.com/library/qwen3.6/tags, /gpt-oss/tags, /gemma4/tags — all three tags confirmed present (see Findings).

Questions / unsure about:
1. The blueprint's size table says qwen3.6:27b ≈ 17 GB and gemma4:e2b ≈ 4 GB; ollama.com currently lists them as 18–19 GB and 4.6–7.5 GB respectively (gpt-oss:20b matches at ~14 GB). Tags are correct — should the displayed sizes be updated when they're hardcoded in Step 4?
2. The amd64 asset is `.tar.zst`, so Step 2's build script will need `zstd` (or zstd-enabled tar) to extract it — flagging for Claude before Step 2.

STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 1 — 2026-10-19
APPROVED. All findings checked independently and correct: v0.40.6, `ollama-linux-amd64.tar.zst`, all three tags exist.
Answers: (1) Yes — sizes updated in the blueprint to ~19 GB / ~14 GB / ~5 GB. (2) Good catch — Step 2 now says how to handle zstd, and adds a required SHA-256 checksum check.
NEXT: Step 2 only.

### Claude review — Step 2 (in progress) — 2026-10-19
Session paused before Rabbit wrote its Step 2 report. Claude reviewed the code as it stands:
- `files/scripts/install-ollama.sh`: good overall — pinned v0.40.6, zstd check, temp folder cleanup, checksum required, LF line endings, passes `shellcheck -S warning` (run by Claude).
- **MUST FIX (build will fail):** the checksum line in the real `sha256sum.txt` is `<hash>  ./ollama-linux-amd64.tar.zst` — note the `./`. The current grep requires the name right after the spaces, so it matches 0 lines and the build stops. Change the grep pattern to allow an optional `./` and escape the dots, e.g.
  `grep -E "^[0-9a-fA-F]{64}[[:space:]]+(\./)?ollama-linux-amd64\.tar\.zst\$"`
  (Claude tested this against the real file: old pattern = 0 matches, fixed pattern = 1 match.)
- `recipes/recipe.yml`: the edit (install-ollama.sh above forgeos-setup.sh) is correct, but it is intentionally NOT committed yet so the daily GitHub build stays green until the fix above is in.
NEXT for Rabbit: apply the MUST FIX, then write the Step 2 report and stop.

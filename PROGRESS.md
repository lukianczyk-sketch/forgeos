

### Claude review — Step 2 — 2026-10-22: APPROVED
- MUST FIX applied correctly (line 24). Tested against the real v0.40.6 `sha256sum.txt`: exactly 1 match (`<hash>  ./ollama-linux-amd64.tar.zst`); `sha256sum --check` runs inside the temp folder so the `./` path resolves.
- `shellcheck -S warning`: PASS. `bash -n`: PASS. Line endings: LF.
- `recipes/recipe.yml`: install-ollama.sh runs before forgeos-setup.sh — correct. Committing both now.
NEXT for Rabbit: Step 3 only (after the GitHub build is green).

### Claude update — best models + newest Ollama — 2026-10-22
Robert wants the best of everything in ForgeOS. Checked live today:
- Models (blueprint table updated): 20 GB+ → `qwen3.8:27b` (~18 GB, Apache-2.0, released 2026-08-14, beats qwen3.6 on every published benchmark); 12–19.9 GB → `gpt-oss:20b` (~14 GB); 8–11.9 GB → `gemma4:e4b` (~7 GB, NEW tier); under 8 GB / no GPU → `gemma4:e2b` (~5 GB). All Apache-2.0.
- Ollama: newest stable is `v0.40.8` (2026-10-21). Blueprint Step 2 now pins v0.40.8.
NEXT for Rabbit (as part of Step 3): first change `OLLAMA_VERSION` in `files/scripts/install-ollama.sh` from `v0.40.6` to `v0.40.8` (nothing else in that file), then do Step 3. Use the NEW model table in Step 4.


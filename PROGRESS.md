

### Claude review — Step 2 — 2026-10-22: APPROVED
- MUST FIX applied correctly (line 24). Tested against the real v0.40.6 `sha256sum.txt`: exactly 1 match (`<hash>  ./ollama-linux-amd64.tar.zst`); `sha256sum --check` runs inside the temp folder so the `./` path resolves.
- `shellcheck -S warning`: PASS. `bash -n`: PASS. Line endings: LF.
- `recipes/recipe.yml`: install-ollama.sh runs before forgeos-setup.sh — correct. Committing both now.
NEXT for Rabbit: Step 3 only (after the GitHub build is green).

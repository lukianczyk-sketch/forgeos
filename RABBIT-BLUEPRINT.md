# RABBIT BLUEPRINT — ForgeOS Job 1: "ForgeOS AI Setup"

**For:** Rabbit Team (Cline in VS Code). **Reviewer:** Claude.
**Repo:** `lukianczyk-sketch/forgeos` (BlueBuild image, base `ghcr.io/ublue-os/bazzite:stable`).

## Rules (read every time)
1. Do **ONE step only**, then stop. Write what you did in `PROGRESS.md` (format at the bottom) and wait for Claude's OK before the next step.
2. **Free only.** No paid tools, services, keys or accounts.
3. Don't touch files a step doesn't name. Never edit `cosign.pub`, `.github/` (except where a step says), or anything under `files/system/usr/bin/forgeos-cleansweep*`.
4. Bash scripts start with `#!/usr/bin/env bash` and `set -euo pipefail` (build scripts: `set -oue pipefail`), and must pass `shellcheck -S warning`.
5. Never claim "tested" or "passed" unless you actually ran it — say exactly what you ran and paste the output.
6. The AI may **suggest** only. Nothing downloads or changes without the user clicking **Yes**.

## Goal
When a ForgeOS user opens **"ForgeOS AI Setup"**, it checks how much graphics memory (VRAM) the computer has, recommends the best free local AI model that fits, shows its download size, and downloads it **only if the user says yes**. The model then works in Alpaca (already in the image).

## Model choice (Apache-2.0 models only)
| Detected VRAM | Model tag | Approx. download |
|---|---|---|
| 20 GB or more | `qwen3.8:27b` | ~18 GB |
| 12 – 19.9 GB | `gpt-oss:20b` | ~14 GB |
| 8 – 11.9 GB | `gemma4:e4b` | ~7 GB |
| under 8 GB, or no GPU found | `gemma4:e2b` | ~5 GB |

Keep these four tags and sizes in ONE place at the top of the script (variables), so they're easy to change later.
(Claude update 2026-10-22: upgraded to the best free models available today — `qwen3.8:27b` replaces `qwen3.6:27b` (newer, Apache-2.0, better on every published benchmark); added the `gemma4:e4b` tier for 8–12 GB cards. All four tags checked live on ollama.com/library; all Apache-2.0.)

---

## Step 1 — Find the Ollama download (research only, no code)
Open https://github.com/ollama/ollama/releases/latest and write in PROGRESS.md:
- the exact latest version number,
- the exact file name of the **Linux x86-64 (amd64)** download,
- whether it's `.tgz` or `.tar.zst`,
- the exact model tags above as listed on https://ollama.com/library (confirm `qwen3.6:27b`, `gpt-oss:20b`, `gemma4:e2b` exist; if a tag is different, write the real one).
Do not write any code in this step.

## Step 2 — Build-time Ollama install
Create `files/scripts/install-ollama.sh` that runs at **image build time**:
- Variable `OLLAMA_VERSION="v0.40.8"` (pinned, no "latest"). Claude update 2026-10-22: v0.40.8 is the newest stable release (2026-10-21); was v0.40.6.
- Make sure `zstd` exists first: `command -v zstd || dnf install -y zstd`.
- Download BOTH into a temp folder with `curl -fL`:
  `https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}/ollama-linux-amd64.tar.zst`
  and `https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}/sha256sum.txt`
- **Security check:** verify the download against `sha256sum.txt` (only the `ollama-linux-amd64.tar.zst` line) with `sha256sum -c`. If it doesn't match, the script must FAIL (exit 1) — never install an unverified download.
- Extract into `/usr` with `tar --zstd -xf <file> -C /usr` (so `/usr/bin/ollama` exists), then delete the temp folder.
- Prints `ollama --version` at the end (if it errors because no server is running, `ollama -v` output or `/usr/bin/ollama --help | head -1` is fine — just prove the binary runs).
- Note: AMD GPU support (`ollama-linux-amd64-rocm.tar.zst`, ~1 GB more) is NOT part of this job — skip it.
Then add `install-ollama.sh` to the `script` module list in `recipes/recipe.yml`, **above** `forgeos-setup.sh`.

## Step 3 — Ollama background service
Create:
- `files/system/usr/lib/sysusers.d/ollama.conf` → creates system user/group `ollama` with home `/var/lib/ollama`.
- `files/system/usr/lib/systemd/system/ollama.service` → runs `/usr/bin/ollama serve` as user `ollama`, `Environment=OLLAMA_HOST=127.0.0.1:11434` (local only — never open to the network), `Environment=OLLAMA_MODELS=/var/lib/ollama/models`, `Restart=always`, `WantedBy=multi-user.target`.
- In `files/scripts/forgeos-setup.sh` add one line at the end: `systemctl enable ollama.service`

## Step 4 — The "pick a model" brain
Create `files/system/usr/bin/forgeos-ai-setup` (bash) with these functions:
- `detect_vram_mb` — prints total VRAM in MB:
  1. if env var `FORGEOS_FAKE_VRAM_MB` is set → print it (for tests);
  2. else NVIDIA: `nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits` (take the largest if several GPUs);
  3. else AMD: largest value from `/sys/class/drm/card*/device/mem_info_vram_total` (bytes → MB);
  4. else print `0`.
- `choose_model <vram_mb>` — prints the model tag using the table above.
- `model_size <tag>` — prints the approx. download size text (use the sizes in the table above: ~18 GB, ~14 GB, ~7 GB, ~5 GB).
- Option `--dry-run` → prints `VRAM: <n> MB` and `Model: <tag> (<size>)` and exits 0 without downloading anything.
No downloading yet in this step.

## Step 5 — Automatic tests on GitHub (free)
Create `tests/test-ai-setup.sh` that runs `forgeos-ai-setup --dry-run` with `FORGEOS_FAKE_VRAM_MB` set to: `0`, `4096`, `11999`, `12000`, `16384`, `19999`, `20000`, `24576` and checks the chosen tag each time (exit 1 on any mismatch, print PASS/FAIL per case).
Create `.github/workflows/tests.yml` that, on every push and pull request, installs `shellcheck`, runs `shellcheck -S warning` on every script under `files/` and `tests/`, then runs `tests/test-ai-setup.sh`. Ubuntu runner, free.

## Step 6 — Ask, then download
Extend `forgeos-ai-setup` (normal run, no `--dry-run`):
1. If `ollama` isn't running (`curl -s http://127.0.0.1:11434/api/version` fails) → show a message and exit.
2. Show a Yes/No dialog (use `kdialog`, fall back to `zenity`, fall back to terminal `read`): "Your computer has <X> GB graphics memory. Recommended AI: <tag> (<size> download). Download now?"
3. Only on **Yes**: `ollama pull <tag>`, with a progress dialog if possible.
4. Save the choice to `~/.config/forgeos/ai-model` (one line: the tag).
5. Finish with a message: "Done — open Alpaca to chat with your AI."
On **No** → exit quietly, change nothing.

## Step 7 — Menu entry + first-login prompt
- `files/system/usr/share/applications/forgeos-ai-setup.desktop` → Name "ForgeOS AI Setup", Exec `/usr/bin/forgeos-ai-setup`, Icon `applications-science`, Categories `System;`.
- `files/system/etc/xdg/autostart/forgeos-ai-setup-once.desktop` → runs a tiny wrapper that only starts the setup if `~/.config/forgeos/ai-model` does NOT exist, and only once per user (create `~/.config/forgeos/ai-setup-offered` after the first offer).
- Add `chmod 0755 /usr/bin/forgeos-ai-setup` to `forgeos-setup.sh`.

## Done when
- GitHub "tests" workflow is green, and the main image build is green.
- Claude has reviewed every step.

---

## PROGRESS.md format (append one block per step)
```
## Step N — <title> — <date>
Files changed: <list>
What I did: <2–5 lines>
What I ran + output: <exact command and pasted result, or "nothing run">
Questions / unsure about: <list or "none">
STATUS: WAITING FOR CLAUDE REVIEW
```

# RABBIT BLUEPRINT — Job 10b: NVIDIA image + AI Setup size fix

Goal (Robert, 2026-10-26): (1) a second ForgeOS image for NVIDIA cards (his Predator has an RTX 5090 Laptop GPU, 24 GB), (2) AI Setup must not pick a model that is too big for a 12 GB card. Claude wrote and tested a prototype; Cline types it in, Claude reviews by diff.

## Facts (checked by Claude 2026-10-26)
- Bazzite builds `bazzite-nvidia-open` (KDE, NVIDIA open kernel driver, `nvidia-open` akmods) and `bazzite-nvidia` (closed `nvidia-lts`, older GTX 9xx/10xx). RTX 50 (Blackwell) needs the OPEN driver -> base `ghcr.io/ublue-os/bazzite-nvidia-open`, tag `stable`. Source: ublue-os/bazzite build.yml + Containerfile (main).
- The NVIDIA image keeps Waydroid (swapped to `waydroid-nvidia`), so Will It Run? still works.
- BlueBuild: a module list file in `recipes/` (`modules:` key, schema module-list-v1) is loaded with `- from-file: name.yml`; each extra image = another recipe file with its own `name:` + a line in the build.yml matrix (blue-build.org how-to/multiple-files + multiple-images).
- Ollama sizes (ollama.com, 2026-10-26): gemma4:12b ~7.7-8.0 GB, gpt-oss:20b 14 GB, qwen3.8:27b 18 GB. gpt-oss:20b does NOT fit a 12 GB card.

## Design
- `recipes/common-modules.yml` = ALL modules that were in recipe.yml, unchanged (files, dnf, script, default-flatpaks, signing). New packages/apps go here from now on.
- `recipes/recipe.yml` -> `forgeos` on `ghcr.io/ublue-os/bazzite` (AMD/Intel). Only module: `- from-file: common-modules.yml`.
- `recipes/recipe-nvidia.yml` -> `forgeos-nvidia` on `ghcr.io/ublue-os/bazzite-nvidia-open`. Same single module.
- `.github/workflows/build.yml` matrix builds both.
- Tests that read recipe.yml now read common-modules.yml. New `tests/test-recipes.sh` (A-F) + CI step.
- AI Setup tiers: 20+ GB qwen3.8:27b · 16-19.9 GB gpt-oss:20b · NEW 12-15.9 GB gemma4:12b (~8 GB) · 8-11.9 GB gemma4:e4b · under 8 GB gemma4:e2b. test-ai-setup.sh gets 12000/15999 -> gemma4:12b and 16000 -> gpt-oss:20b.
- README: "Which image?" section + Secure Boot key note (`ujust enroll-secure-boot-key`, password `universalblue`, docs.bazzite.gg).

## Steps
1. Recipes: common-modules.yml (new), recipe.yml (replace), recipe-nvidia.yml (new), build.yml matrix, README.
2. AI tiers + tests: forgeos-ai-setup, test-ai-setup.sh, 4 test path edits, tests/test-recipes.sh (new), tests.yml step.

## To check on a real machine
- forgeos-nvidia boots on the Predator (hybrid Intel/AMD + RTX 5090 Laptop), `nvidia-smi` works, Ollama uses the GPU (`ollama ps` shows 100% GPU), AI Setup picks qwen3.8:27b.
- GHCR: the new `forgeos-nvidia` package may start PRIVATE — set it Public in GitHub package settings.

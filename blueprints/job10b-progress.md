# PROGRESS — Job 10b: NVIDIA image + AI Setup size fix

- 2026-10-26 Claude: blueprint + prototype written and tested (test-recipes A-F, test-ai-setup 12 cases, all old tests that read the recipe; 10 mutations caught; shellcheck clean). Next: Step 1 (Cline).
- Step 1 (Cline): created recipes/common-modules.yml + recipes/recipe-nvidia.yml, replaced recipes/recipe.yml, build.yml matrix builds both, README "Which image?". Waiting for Claude's review.
- Step 1 review (Claude): all 5 files byte-identical to the prototype after CRLF fix (Cline wrote CRLF in common-modules.yml, recipe-nvidia.yml, build.yml, README.md). Not committed yet: the old tests read recipe.yml until Step 2 moves them to common-modules.yml, so Steps 1+2 are committed together to keep CI green.
- Step 2 (Cline): AI Setup 12-15.9 GB tier = gemma4:12b, 16-19.9 GB = gpt-oss:20b; tests read common-modules.yml; new tests/test-recipes.sh + CI step. Waiting for Claude's review.
- Step 2 review (Claude): 7 of 8 files byte-identical after CRLF fix; tests/test-recipes.sh was missing its last newline -> replaced with the prototype. All 13 changed files now equal the prototype. PC VM: test-recipes, test-ai-setup (12), test-flatpak-list, test-cool-stuff + all 13 older suites pass. Steps 1+2 committed together.
- Committed 4bfe775 (pushed). CI: tests green, bluebuild green for BOTH images (recipe.yml + recipe-nvidia.yml). ghcr.io/lukianczyk-sketch/forgeos-nvidia published (Public, signed, tags latest / 44 / 4bfe775-44). Tagged v0.11.1 on the docs commit.

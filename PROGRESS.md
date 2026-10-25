# ForgeOS — Progress log (Job 5: Undo Button)

## Step 0 — Research + prototype (Claude) — 2026-10-25
- Verified facts are in RABBIT-BLUEPRINT.md. Prototype engine + setup script tested on a real btrfs loop disk with snapper 0.10.6 (Ubuntu); Fedora 44 ships 0.13.0 (same commands/keys, man page 0.13.2 checked).
- STATUS: READY FOR STEP 1

## Step 1 — Turn on the Undo Button — 2026-10-25
What I did:
- Created forgeos-undo-setup, forgeos-undo-setup.service and the snapper-cleanup.timer.d/forgeos-hourly.conf drop-in exactly as given.
- forgeos-setup.sh: chmod for forgeos-undo-setup; enabled forgeos-undo-setup.service, snapper-timeline.timer, snapper-cleanup.timer.
- recipe.yml: added jq.
Files changed:
- files/system/usr/libexec/forgeos-undo-setup (new)
- files/system/usr/lib/systemd/system/forgeos-undo-setup.service (new)
- files/system/usr/lib/systemd/system/snapper-cleanup.timer.d/forgeos-hourly.conf (new)
- files/scripts/forgeos-setup.sh
- recipes/recipe.yml
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 1 — 2026-10-25 — APPROVED
- forgeos-undo-setup is byte-identical to Claude's tested prototype except the header line (expected). Service, hourly-cleanup drop-in, forgeos-setup.sh (chmod + enable) and recipe.yml (jq) match the prompt exactly.
- Fixed: the 3 new files came out with CRLF line endings → converted to LF (now 0 CR).
- shellcheck -S warning: clean.
- Real test (cloud VM, 1 GB btrfs loop disk, snapper 0.10.6), all exit 0:
  1. fresh btrfs subvolume → config `root` created, ALLOW_GROUPS=wheel, SYNC_ACL=yes, TIMELINE_CREATE=yes, TIMELINE_LIMIT_HOURLY=1-12, FREE_LIMIT=0.2; marker "enabled <date> UTC"
  2. run again → "already set up", nothing changed
  3. config already exists, no marker → left alone, marker "skipped: config already existed"
  4. ext4 folder → marker "skipped: not btrfs"
  5. btrfs plain folder (not a subvolume) → marker "skipped: not a subvolume"
  6. after setup, `snapper -c root create` makes snapshot #1.
- STATUS: READY FOR STEP 2

## Step 2 — Undo Button engine — 2026-10-25
What I did:
- Created forgeos-undo exactly as given (status, versions, restore with virus check, snapshot-now, updates, undo-update).
- forgeos-setup.sh: chmod for /usr/bin/forgeos-undo.
Files changed:
- files/system/usr/bin/forgeos-undo (new)
- files/scripts/forgeos-setup.sh
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 2 — 2026-10-25 — APPROVED (after fixes)
- Cline's file tool rejects writes over 6000 characters, so Cline wrote forgeos-undo in 3 chunks. Joining them broke the file:
  - BUG (fixed): the closing `}` of cmd_versions was moved to the very end of the file, so the whole command dispatcher sat inside cmd_versions and never ran — `forgeos-undo <anything>` silently did nothing and exited 0. Moved the `}` back.
  - Removed a stray extra blank line; file now ends with exactly one newline.
  - Converted CRLF → LF (215 CR).
- After the fixes the file is byte-identical to Claude's tested prototype (md5 8caeffae5c319c9637f341af616095c5). forgeos-setup.sh chmod line correct.
- shellcheck -S warning: clean.
- Prototype tests (cloud VM, real btrfs + snapper 0.10.6), all as expected:
  status (ON/count/dates; non-wheel user → exit 3), versions (file + folder; identical copies hidden; none → exit 1; outside home or inside .snapshots → exit 2),
  restore (existing file → "taxes (from DATE).txt", again → "#2"; deleted file/folder/hidden file → old name; bad number/usage → exit 2; missing → exit 1),
  virus check (fake clamscan 0/1/2 + REAL clamscan with an EICAR signature: infected file or folder → copy removed, exit 4; scan error → kept + warning),
  snapshot-now via snapperd, updates + undo-update (fake rpm-ostree JSON).
- Note for Step 3: the window must handle exit 4 ("virus found — not restored").
- STATUS: READY FOR STEP 3

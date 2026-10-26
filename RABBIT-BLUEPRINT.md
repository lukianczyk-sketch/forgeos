# RABBIT BLUEPRINT — Job 8: Scam Shield

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype. Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
"Is this a scam?" in one click, for regular people and seniors. Copy a text, email or link (or
right-click a saved email in Dolphin) and Scam Shield answers in plain English:
**Looks like a scam** / **Be careful** / **No scam signs found**, with the reasons why and what to do.
1. **Rule check** (always works, even with no AI): known scam websites (a free list downloaded
   every day), fake company names in links (paypa1-account.com, usps-redeliver.top), hidden
   addresses after an @, bare-number addresses, look-alike letters (xn--), short links, risky
   endings (.top, .zip ...), and warning words (gift cards, crypto/wire, remote-control apps,
   "send me the code", fake virus alerts, threats, prizes, secrecy, rushing, stuck packages,
   family-in-trouble).
2. **Private AI second opinion**: the local Ollama model from ForgeOS AI Setup reads the message
   and the rule findings and answers scam / suspicious / safe with short reasons. The AI may make a
   warning stronger, but it can NEVER make it weaker than the rule check (a scam message could try
   to talk the AI into saying "safe").
3. Links are never opened. Nothing the user checks ever leaves the computer.

## How (key facts — all verified by Claude)
- AI: Ollama on 127.0.0.1:11434 only. Model = `~/.config/forgeos/ai-model` (written by AI Setup) if
  Ollama has it, else the first model in `/api/tags`. `POST /api/chat` with `stream: false`,
  `options.temperature: 0` and `format` = a JSON schema (Ollama structured outputs:
  verdict enum scam|suspicious|safe, reasons max 3, advice). The schema is also described in the
  prompt (Ollama docs recommend both). Message cut to 6000 characters. Timeout 180 s.
- Scam website lists: malware-filter by curbengh — phishing-filter (sources OpenPhish, PhishTank,
  IPThreat; CC BY-SA 4.0) and urlhaus-filter (URLhaus, CC0). Hosts format, lines `0.0.0.0 <name>`,
  updated twice a day. Mirrors tried in order: malware-filter.gitlab.io, curbengh.github.io,
  malware-filter.pages.dev. Saved as /var/lib/forgeos-scamshield/phishing.list and urlhaus.list (one
  name per line). A list with fewer than 100 names is ignored and the old one kept.
- Downloaded by a hardened system service (root, ProtectSystem=strict, StateDirectory) from a daily
  timer (also 10 min after start-up, Persistent=true). It only downloads; it sends nothing.
- Lookup: exact name, then each parent (login.bad.example.com -> bad.example.com -> example.com).
  The lists hold exact names (e.g. one bad x.weebly.com), so neighbours are never flagged.
- Fake company names: `/usr/share/forgeos/scamshield-brands.txt` (name + its real websites). The
  name must be a whole part of the address (paypal-login.com yes, pineapple.com no). Digits used as
  letters are undone first (0->o 1->l 3->e 5->s). .gov and .mil addresses are always trusted.
- Warning words: `/usr/share/forgeos/scamshield-words.txt`, one rule per line:
  `id ~ points ~ grep -E pattern ~ plain-English reason`. Each kind of warning counts once.
- Score: 6+ = Looks like a scam (exit 2), 3-5 = Be careful (exit 1), 0-2 = No scam signs (exit 0).
  Exit 3 = could not check.
- Clipboard: `wl-paste` (package wl-clipboard, added to the recipe), falling back to Klipper over
  D-Bus. No literal TAB characters anywhere (Cline turns them into "\t").
- awk: no `{n,m}` intervals (mawk on the CI runner does not support them).

## Files
- `files/system/usr/libexec/forgeos-scamshield-lib` (new) — the rule check (sourced).
- `files/system/usr/share/forgeos/scamshield-words.txt` (new) — warning words.
- `files/system/usr/share/forgeos/scamshield-brands.txt` (new) — names scammers copy.
- `files/system/usr/bin/forgeos-scamshield` (new) — `check [--no-ai] [FILE|-]`, `check-clipboard [--no-ai]`.
- `files/system/usr/libexec/forgeos-scamshield-update` (new) — downloads the scam lists.
- `files/system/usr/lib/systemd/system/forgeos-scamshield-update.service` + `.timer` (new).
- `files/system/usr/bin/forgeos-scamshield-gui` (new) — the window; `--file F` for right-click.
- `files/system/usr/share/applications/forgeos-scamshield.desktop` (new) — menu entry "Scam Shield".
- `files/system/usr/share/kio/servicemenus/forgeos-scamshield.desktop` (new) — Dolphin "Check for scams".
- `files/scripts/forgeos-setup.sh` — chmod 0755 the 3 new scripts + enable the timer.
- `recipes/recipe.yml` — add `wl-clipboard`.
- `tests/test-scamshield.sh` (A-K) + `tests/test-scamshield-extras.sh` (L-T) (new), `.github/workflows/tests.yml`.

## Steps (ONE per Cline task, then stop)
1. Blueprint + progress log + rule check (lib, words, brands).
2. Command + list downloader + service + timer + setup + recipe.
3. Window + menu entry + Dolphin right-click + setup chmod.
4. Tests + CI step.

## Report format (append to PROGRESS.md)
```
## Step N — <title>
- Files changed: <list>
- Notes: <anything odd, or "none">
- STATUS: WAITING FOR CLAUDE REVIEW
```

## Honest limits (shown in "How Scam Shield works")
No check is perfect. New scam websites appear every hour, and a message with no warning signs can
still be a scam. The AI can make mistakes, which is why it can only raise a warning. If a message
asks for money, passwords or codes, stop and ask someone you trust.

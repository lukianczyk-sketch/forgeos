# RABBIT BLUEPRINT — Job 19: Find My PC (private)

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-K pass, plus every other ForgeOS test).
Each step prompt gives you the EXACT file contents. Copy them exactly.
Do not research, do not "improve", do not run commands.

## What it does
If this PC is lost or stolen, your phone can see where it is, ring it, show a "please return" message and
lock it - with no company account. Approved by Robert 2026-11-07.
1. **Setup** (`forgeos-locate-gui`, kdialog): asks "webcam photo while lost?", then the root helper
   (`pkexec /usr/libexec/forgeos-locate-root setup [--photo]`, polkit auth_admin = ALWAYS the PC password)
   makes a new secret key (32 random bytes, root-only /var/lib/forgeos-locate/key.json) and shows a QR code
   (qrencode, the link on stdin - never on a command line) of the phone link `https://lukianczyk-sketch.github.io/forgeos/find/#k=KEY`, the PC's serial
   number (for the police) and the optional ntfy app "bell" topic. Then "Test it with my phone".
2. **The lock** (`locatelib/seal.py` = `docs/find/fmp-crypto.js`): AES-256-GCM (python3-cryptography / Web
   Crypto). The key makes the 3 relay topics (HMAC-SHA256): cmd (phone -> PC), rep (PC -> phone), bell (plain
   "checked in", no details) and the lock key. Message = "FMP1." + base64url(nonce + locked text); the
   direction is locked in. The key is after the "#", which a phone never sends to any website.
3. **The relay**: ntfy.sh (free, no account, keeps messages 12 hours, only sees locked text). settings.json
   can point at your own ntfy server (then the link gets "&r=").
4. **The root watcher** (`forgeos-locate.service`, also at the sign-in screen): normal days it only polls
   the cmd topic every 10 minutes (every 15 s for 15 minutes after setup or a command) and SENDS NOTHING.
   A command counts only if it opens with the key, is less than 13 hours old and newer than the last one.
   Commands: lost, found, ring, message, lock (`loginctl lock-sessions`), shutdown (lock + `systemctl
   poweroff` after the answer), ping. Every command gets a locked answer ("ack").
5. **Lost mode**: money websites locked (Fake Tech Support Guard's `forgeos-techguard root-money lock`),
   password safe locked, polls every minute; a locked report every 10 minutes (every 20 after 2 hours):
   place from nearby Wi-Fi (nmcli -> beaconDB, 2+ networks) or rough from the internet address (ipinfo.io),
   Wi-Fi name, battery, who is signed in. A bell once an hour. Webcam photo (ffmpeg, 320 wide or 240, at most 12 KB,
   in pieces of 2,400 letters) at the start then every 3 hours, only if turned on. No internet: tries the
   strongest open Wi-Fi once every 10 minutes ("ForgeOS-FindMyPC", forgotten on Found it). The relay says
   429: waits 30 minutes. **Found it**: lost mode off, money websites open again (only if Find My PC locked
   them), old "lost"/"message" alerts cleared, reports wiped from the PC. A phone clock more than 5 minutes
   ahead gets "set your clock" (nothing done). The state is saved before a command runs (never twice), and
   one bad command or a broken relay answer never stops the watcher. "Test it" in the window touches
   $XDG_RUNTIME_DIR/forgeos-locate-poke = the watcher checks right away (15 fast minutes).
6. **Your session** (`forgeos-locate-alert.service`, `forgeos-locate alert-watch`, every 2 s): ring (sound
   unmuted, 100%, paplay a loud sound for 2 minutes), message (critical note + big kdialog; still shown to
   someone who signs in up to 12 hours later), lost (KeePassXC --lock), found ("welcome back").
7. **The phone page** (`docs/find/`, GitHub Pages from main /docs): reads the rep topic (since=12h), shows
   lost / where on an OpenStreetMap map / Wi-Fi / battery / who / the newest photo / the history (kept on
   the phone until "Clear"), and sends locked commands. Only its own 3 scripts; text only (no innerHTML).
8. **Ties in**: Forge Helper rule FIRST (`find_my_pc`, before Digital Will) + tool + help card + 3 test
   questions; qrencode + python3-cryptography in the image.

## Files
- files/system/usr/bin/forgeos-locate (status | report | serial | watch [--once] | alert-watch [--once] |
  root setup [--photo] / link / photo on|off / off), files/system/usr/bin/forgeos-locate-gui
- files/system/usr/lib/forgeos-locate/locatelib/: __init__ seal relay where commands watch setup alert
  report cli (.py)
- files/system/usr/libexec/forgeos-locate-root (root helper), forgeos-locate-setup (the window's set-up
  screens, sourced)
- polkit org.forgeos.locate.policy; system unit forgeos-locate.service; user unit forgeos-locate-alert.service;
  applications/forgeos-locate.desktop; helper/help/find-my-pc.md; share/forgeos/locate/settings.json
- docs/.nojekyll, docs/find/: index.html, find.css, fmp-crypto.js, find-show.js, find.js
- edits: forgeos-setup.sh (a NEW chmod line + 2 enable lines), recipes/common-modules.yml (qrencode,
  python3-cryptography), helperlib rules/tools/actions/looks, tools-2.jsonl, tests/test-helper-ai.sh (G3),
  .github/workflows/tests.yml
- tests/locate-fakes.sh, locate-fake-relay.py, test-locate.sh (A-C), test-locate-watch.sh (D-E),
  test-locate-commands.sh (E8-F), test-locate-alert.sh (G), test-locate-gui.sh (H-I), test-locate-page.sh
  (J, Node.js), test-locate-files.sh (K)

## Steps (one Cline task each)
1. bin/forgeos-locate, locatelib __init__.py, seal.py, relay.py
2. locatelib where.py, commands.py
3. locatelib watch.py, setup.py, alert.py
4. locatelib report.py, cli.py, root helper, polkit, 2 units, menu entry, help card, settings.json
5. the window: bin/forgeos-locate-gui + libexec/forgeos-locate-setup
6. phone page part 1: docs/.nojekyll, index.html, find.css, fmp-crypto.js
7. phone page part 2: find-show.js, find.js
8. edits: forgeos-setup.sh, common-modules.yml, tools-2.jsonl, test-helper-ai.sh
9. edits: Forge Helper rules.py, tools.py, actions.py, looks.py
10. tests/locate-fakes.sh, locate-fake-relay.py
11. tests/test-locate.sh, test-locate-watch.sh
12. tests/test-locate-commands.sh, test-locate-alert.sh
13. tests/test-locate-gui.sh, test-locate-page.sh
14. tests/test-locate-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.
- Run bits (Claude sets them in git): bin/forgeos-locate, bin/forgeos-locate-gui, libexec/forgeos-locate-root = 755.

## Honest limits
A PC that is turned off, or has no internet, cannot report until it wakes with internet (the disk lock
stops a thief at power-on). Ring needs someone signed in or the lock screen (not the sign-in screen). Wi-Fi
places are rougher in the country (beaconDB has less data than Google); the internet address is a rough city.
A thief who wipes the drive removes it. No remote wipe on purpose. Anyone with the phone link can find the
PC: keep it secret ("Set up again" makes a new one). ForgeOS side only. Robert turns on GitHub Pages once
(Settings > Pages > main, /docs). Checked on the real PC at the end of the full build: ntfy.sh CORS from the
phone page and its free limits, beaconDB answers, nmcli as root at the sign-in screen, loginctl
lock-sessions, paplay at the lock screen, ffmpeg webcam capture, qrencode image in kdialog, the QR scan on
iPhone/Android and Add to Home Screen, KeePassXC --lock.

#!/usr/bin/env bash
# Tests for Show Me How (Job 22), cases E-F: the step rules (no skipping ahead, Back / Next, places on the
# screen, Try again, our own panel never pointed at), the right place opened first, Family Mode big text.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-showme-steps.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/showme-fakes.sh
. "$ROOT/tests/showme-fakes.sh"
PY() { python3 -B -c "import sys; sys.path.insert(0, '$FORGEOS_SHOWME_LIB'); $1"; }

# E1: Print: "Print" is already on the screen when Ctrl+P is shown -> it waits for Next (no skipping ahead);
#     it goes away for 2 looks and the print window shows it again -> it moves on by itself
fresh
screen 1 "File Edit Print@10,10"
screen 2 "File Edit@10,10"
screen 3 "File Edit@10,10"
screen 4 "Print@900,700" "Cancel@1100,700"
OUT="$(PY "
from showlib import guides, screen, walk
g = guides.load('print'); w = walk.Walk(g['steps'], 0)
look = lambda: screen.read('$WORK/x')
open('$WORK/x', 'w').close()
for t in (2, 4, 6, 8):
    v = w.tick(look(), [], t); print(v['mode'], v['step'], v.get('x', '-'))
")"
check E1 '[ "$OUT" = "say 1 -
say 1 -
say 1 -
point 2 0.4688" ]'
# E2: Back / Next, Next on the last step = done; a place points at a part of the screen; the panel corner
OUT="$(PY "
from showlib import guides, walk
w = walk.Walk(guides.load('wifi')['steps'], 0)
v = w.tick(None, [], 1); print(v['mode'], v['x'], v['y'], v['corner'], v['say'])
w.go(1, 2); print(w.tick(None, [], 2)['mode'], w.i); w.go(-1, 3); w.go(-1, 3); print(w.i)
w.go(1, 4); w.go(1, 4); w.go(1, 4); print(w.end, w.tick(None, [], 5)['mode'])
")"
check E2 '[ "$OUT" = "point 0.905 0.95 lt Click the network icon. (bottom right)
say 1
0
done end" ]'
# E3: Try again starts looking afresh; avoid = our own panel is never pointed at
fresh; screen 0 "Scan@100,100"
OUT="$(PY "
from showlib import guides, screen, walk
open('$WORK/x', 'w').close(); s = screen.read('$WORK/x')
w = walk.Walk(guides.load('scan')['steps'], 0)
print(w.tick(None, [], 2)['mode'], w.tick(s, [[0, 0, 0.5, 0.5]], 4)['mode'], w.tick(s, [[0, 0, 0.5, 0.5]], 12)['mode'])
w.again(8); print(w.missing, w.tick(s, [], 10)['mode'])
")"
check E3 '[ "$OUT" = "look look lost
0 point" ]'

# E4: the next words were already on the screen (a "Print" link) -> no skipping; the print window's own
#     "Print" button shows up in a NEW place -> it moves on by itself (while the link is still there)
fresh
screen 1 "Print@10,10"
screen 2 "Print@10,10"
screen 3 "Print@10,10" "Print@900,700"
OUT="$(PY "
from showlib import guides, screen, walk
open('$WORK/x', 'w').close(); w = walk.Walk(guides.load('print')['steps'], 0)
for t in (2, 4, 6):
    v = w.tick(screen.read('$WORK/x'), [], t); print(v['mode'], v['step'], v.get('x', '-'))
")"
check E4 '[ "$OUT" = "say 1 -
say 1 -
point 2 0.4688" ]'
# E5: our own step panel read by the OCR ("...what you want to print...") never counts as the Print button
fresh; screen 0 "Open what you want to print, then press Ctrl and P together.@1500,900" "Step 1 of 2@1500,870"
OUT="$(PY "
from showlib import guides, screen, walk
open('$WORK/x', 'w').close(); w = walk.Walk(guides.load('print')['steps'], 0)
print([w.tick(screen.read('$WORK/x'), [], t)['step'] for t in (2, 4, 6)])
")"
check E5 '[ "$OUT" = "[1, 1, 1]" ]'
# E6: a window that takes a while to open: no "I can't see it" in the first 10 seconds
fresh; screen 0 "Settings@600,100"
OUT="$(PY "
from showlib import guides, screen, walk
open('$WORK/x', 'w').close(); w = walk.Walk(guides.load('scan')['steps'], 0)
print('|'.join(w.tick(screen.read('$WORK/x'), [], t)['mode'] for t in (2, 4, 6, 8, 10)))
")"
check E6 '[ "$OUT" = "look|look|look|look|lost" ]'

# F1: the right place opens first: a settings page, a ForgeOS window, an app that is not there = nothing
fresh
OUT="$(PY "
from showlib import guides, session
print(session.open_place(guides.load('add-printer')), session.open_place(guides.load('updates')),
      session.open_place(guides.load('email')), session.open_place(guides.load('print')))
")"
sleep 1
check F1 '[ "$OUT" = "True False False False" ] && grep -qx "systemsettings kcm_printer_manager" "$WORK/calls.log" && ! grep -q "^gio" "$WORK/calls.log"'
# F2: Family Mode big text = everything drawn bigger; the overlay's message is only numbers and words
printf 'STATUS\ton\nSIZE\tbigger\n' > "$WORK/say/family"
OUT="$(PY "
from showlib import size, session
print(size(), session.state({'show': True, 'x': 0.1, 'mode': 'point', 'say': 'Hi'}, 1.8))
print(session.own('[[0.1, 0.2, 2, -1], [1], \"bad\"]'), session.own('nonsense'))
")"
check F2 '[ "$OUT" = "1.8 {\"show\": true, \"x\": 0.1, \"say\": \"Hi\", \"size\": 1.8}
[[0.1, 0.2, 1.0, 0.0]] []" ]'
# F3: the step panel is made again only for a new step (OCR flicker never respawns it or grabs the keyboard)
OUT="$(PY "
from showlib import guides, show, walk
made = []
show.start = lambda cmd: made.append(cmd) or type('P', (), {'poll': lambda self: None, 'terminate': lambda self: None})()
g = guides.load('scan'); s = show.Show(walk.Walk(g['steps'], 0), g)
for mode, step in (('point', 1), ('look', 1), ('point', 1), ('point', 2), ('lost', 2)):
    s.view = dict(s.view, mode=mode, step=step, total=2, say='x'); s.show_panel()
print(len(made), made[0][4], made[0][6], made[-1][4], made[-1][6], sep='|')
")"
check F3 '[ "$OUT" = "3|Next|Back|Try again|Show me where to start" ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Show Me How tests E-F passed."; else echo "$failures Show Me How test(s) failed."; exit 1; fi

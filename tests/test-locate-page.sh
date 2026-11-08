#!/usr/bin/env bash
# Tests for Find My PC (Job 19), case J: the phone page (docs/find, GitHub Pages). Its lock (Web Crypto in
# Node.js) and the PC's lock (Python) open each other's messages; the screen shows lost / where / the photo;
# the page loads only its own files and puts everything on the screen as plain text.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-locate-page.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
Q="'"  # a single quote, for checking Python output
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
P="$ROOT/docs/find"
LIB="$ROOT/files/system/usr/lib/forgeos-locate"
if ! node -e 'process.exit(globalThis.crypto && crypto.subtle ? 0 : 1)' 2>/dev/null; then
  echo "SKIP: Node.js 20 or newer is needed for the phone page tests."; exit 1
fi

# J1: the PC locks, the phone opens - and the other way round; same topic names; the wrong direction stays shut
cat > "$WORK/both.js" <<'JS'
const FMP = require(process.argv[2]);
(async () => {
  const [key, fromPc] = [process.argv[3], process.argv[4]];
  console.log(JSON.stringify({ cmd: await FMP.topic(key, "cmd"), rep: await FMP.topic(key, "rep"), bell: await FMP.topic(key, "bell"),
    sealed: await FMP.seal(key, "cmd", { c: "ring", t: 1800000000123 }), opened: await FMP.unseal(key, "rep", fromPc),
    wrong: await FMP.unseal(key, "cmd", fromPc), good: FMP.goodKey(key), bad: FMP.goodKey("abc") }));
})();
JS
J1="$(python3 -B -c "
import json, subprocess, sys; sys.path.insert(0, sys.argv[1])
from locatelib.seal import new_key, seal, unseal, topic
k = new_key(); s = seal(k, 'rep', {'k': 'where', 'lat': 35.13, 'users': ['robert']})
o = json.loads(subprocess.check_output(['node', sys.argv[2], sys.argv[3], k, s]))
print(o['cmd'] == topic(k, 'cmd'), o['rep'] == topic(k, 'rep'), o['bell'] == topic(k, 'bell'), o['opened'] == {'k': 'where', 'lat': 35.13, 'users': ['robert']},
      o['wrong'], unseal(k, 'cmd', o['sealed']), unseal(k, 'rep', o['sealed']), o['good'], o['bad'])" "$LIB" "$WORK/both.js" "$P/fmp-crypto.js")"
check J1 '[ "$J1" = "True True True True None {${Q}c${Q}: ${Q}ring${Q}, ${Q}t${Q}: 1800000000123} None True False" ]'
check J2 'node --check "$P/fmp-crypto.js" && node --check "$P/find-show.js" && node --check "$P/find.js"'
check J3 '[ "$(grep -o "<script src=\"[^\"]*\"" "$P/index.html" | tr "\n" " ")" = "<script src=\"fmp-crypto.js\" <script src=\"find-show.js\" <script src=\"find.js\" " ] && grep -q "<meta name=\"referrer\" content=\"no-referrer\">" "$P/index.html" && ! grep -q "innerHTML\|eval(\|document.write" "$P"/*.js && [ -s "$ROOT/docs/.nojekyll" ]'

# J4: the screen (a tiny pretend page): lost + seen near Tehachapi on the map, the photo put back together,
# a text from the PC shown as text (never as page code), and Found it hides the map again
cat > "$WORK/screen.js" <<'JS'
const els = {};
const el = (id) => els[id] || (els[id] = { id, hidden: false, textContent: "", className: "", href: "", src: "", attrs: {}, kids: [],
  setAttribute(k, v) { this.attrs[k] = v; }, getAttribute(k) { return this.attrs[k] || null; }, appendChild(c) { this.kids.push(c); } });
global.document = { getElementById: el, createElement: () => el("new" + Math.random()) };
eval(require("fs").readFileSync(process.argv[2], "utf8") + "\nglobal.FindShow = FindShow;");
const now = Math.floor(Date.now() / 1000);
const hist = {
  a: { k: "ack", c: "lost", lost: true, text: "Lost mode is ON.", t: now - 900, mt: now - 900 },
  b: { k: "where", lat: 35.1322, lon: -118.449, acc: 40, src: "wifi", city: "Tehachapi, California, US", wifi: "Cafe", bat: 57, chg: false, users: ["robert"], t: now - 300, mt: now - 300 },
  c: { k: "photo", id: 7, i: 1, n: 2, d: "BBBB", mt: now - 200 }, d: { k: "photo", id: 7, i: 0, n: 2, d: "/9j/", mt: now - 201 },
  e: { k: "ack", c: "message", lost: true, text: "<img src=x onerror=alert(1)>", t: now - 100, mt: now - 100 } };
FindShow.render(hist);
const out = [els.pill.textContent, els.headline.textContent, els["b-lost"].hidden, els["b-found"].hidden, els.mapbox.hidden,
  els.map.attrs.src.includes("marker=35.1322,-118.449"), els.photo.src, els.details.textContent, els.log.kids[0].textContent];
hist.f = { k: "ack", c: "found", lost: false, text: "Lost mode is OFF.", t: now, mt: now };
FindShow.render(hist);
out.push(els.pill.textContent, els.mapbox.hidden, els.headline.textContent);
console.log(out.join("|"));
JS
J4="$(node "$WORK/screen.js" "$P/find-show.js")"
check J4 '[ "$J4" = "LOST|Seen near Tehachapi, California, US - 5 minutes ago|true|false|false|true|data:image/jpeg;base64,/9j/BBBB|From the Wi-Fi around it (about 40 m) · On Wi-Fi: Cafe · Battery: 57% · Signed in: robert|<img src=x onerror=alert(1)>|Not lost|true|Your PC is not marked lost" ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Find My PC tests J passed."; else echo "$failures Find My PC test(s) failed."; fi
exit "$((failures > 0))"

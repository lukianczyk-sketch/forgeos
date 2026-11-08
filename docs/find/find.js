// ForgeOS Find My PC (Job 19): the phone page. Reads the PC's locked reports from the relay, shows where the
// PC is, and sends locked commands (lost, found, ring, message, lock, shutdown, ping). Keeps a copy of the
// reports on this phone only (until "Clear the history").
"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const store = {
    get: (k) => { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set: (k, v) => { try { localStorage.setItem(k, v); } catch (e) { /* private window: fine */ } },
    del: (k) => { try { localStorage.removeItem(k); } catch (e) { /* fine */ } }
  };
  const hash = new URLSearchParams(location.hash.slice(1));
  let key = hash.get("k");
  let relay = hash.get("r") || "https://ntfy.sh";
  if (FMP.goodKey(key)) { store.set("fmp-key", key); store.set("fmp-relay", relay); }
  else { key = store.get("fmp-key"); relay = store.get("fmp-relay") || relay; }
  relay = relay.replace(/\/+$/, "");
  if (!/^https:\/\/[a-z0-9.-]+(:[0-9]+)?(\/[a-z0-9._~-]+)*$/i.test(relay)) relay = "https://ntfy.sh";
  if (!FMP.goodKey(key)) { $("nokey").hidden = false; $("pill").textContent = "No link"; return; }
  $("app").hidden = false;
  let topics = null;
  let hist = {};
  try { hist = JSON.parse(store.get("fmp-hist") || "{}") || {}; } catch (e) { hist = {}; }

  const say = (text) => { $("said").textContent = text; };
  const render = () => FindShow.render(hist);

  async function refresh() {
    try {
      const r = await fetch(relay + "/" + topics.rep + "/json?poll=1&since=12h", { cache: "no-store" });
      const text = await r.text();
      for (const line of text.split("\n")) {
        let m = null;
        try { m = JSON.parse(line); } catch (e) { continue; }
        if (!m || m.event !== "message" || hist[m.id]) continue;
        const o = await FMP.unseal(key, "rep", m.message);
        if (o) { o.mt = m.time; hist[m.id] = o; }
      }
      const ids = Object.keys(hist).sort((a, b) => hist[a].mt - hist[b].mt);
      ids.slice(0, Math.max(0, ids.length - 300)).forEach((id) => delete hist[id]);
      store.set("fmp-hist", JSON.stringify(hist));
    } catch (e) {
      say("No internet on this phone right now.");
    }
    render();
  }

  async function send(c, extra) {
    const obj = Object.assign({ c: c, t: Date.now() }, extra || {});
    try {
      const r = await fetch(relay + "/" + topics.cmd, { method: "POST", body: await FMP.seal(key, "cmd", obj) });
      say(r.ok ? "Sent. Your PC answers within a minute if it is on and has internet (up to 10 minutes when not lost)."
        : "The relay did not take it (" + r.status + "). Try again in a minute.");
    } catch (e) { say("No internet on this phone right now."); }
    let n = 0;
    const fast = setInterval(() => { refresh(); if (++n >= 24) clearInterval(fast); }, 5000);
  }

  $("b-lost").onclick = () => confirm("Mark your PC as lost? It will report where it is every 10 minutes.") && send("lost");
  $("b-found").onclick = () => send("found");
  $("b-ring").onclick = () => send("ring");
  $("b-lock").onclick = () => send("lock");
  $("b-ping").onclick = () => send("ping");
  $("b-shutdown").onclick = () => confirm("Lock and shut down your PC? It cannot report again until someone turns it on.") && send("shutdown");
  $("b-message").onclick = () => {
    const text = prompt("Message to show on your PC's screen:", store.get("fmp-msg") || "This PC is lost. Reward! Please call ");
    const short = Array.from(text || "").slice(0, 200).join("");  // whole letters and emoji only
    if (short.trim()) { store.set("fmp-msg", short); send("message", { text: short }); }
  };
  $("b-clear").onclick = () => { if (confirm("Clear the history on this phone?")) { hist = {}; store.del("fmp-hist"); render(); } };

  (async () => {
    topics = { cmd: await FMP.topic(key, "cmd"), rep: await FMP.topic(key, "rep") };
    render();
    refresh();
    setInterval(() => { if (!document.hidden) refresh(); }, 30000);
  })();
})();

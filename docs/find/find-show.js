// ForgeOS Find My PC (Job 19): the phone page's screen - where the PC was seen (map, Wi-Fi, battery, who),
// lost or not, the newest webcam photo, and the history. Everything is put on the page as plain text.
"use strict";
const FindShow = (() => {
  const $ = (id) => document.getElementById(id);
  const ago = (t) => {
    const s = Math.max(0, Date.now() / 1000 - t);
    if (s < 90) return "just now";
    if (s < 5400) return Math.round(s / 60) + " minutes ago";
    if (s < 129600) return Math.round(s / 3600) + " hours ago";
    return new Date(t * 1000).toLocaleString();
  };
  const place = (r) => r.city ? "near " + r.city : (r.lat !== undefined ? r.lat + ", " + r.lon : "place unknown");

  function render(hist) {
    const all = Object.keys(hist).map((id) => hist[id]).sort((a, b) => a.mt - b.mt);
    let lost = false;
    let where = null;
    const photos = {};
    for (const e of all) {
      if (e.k === "ack" && typeof e.lost === "boolean") lost = e.lost;
      if (e.k === "where") { where = e; lost = true; }
      if (e.k === "ack" && e.c === "found") where = null;
      if (e.k === "photo") { (photos[e.id] = photos[e.id] || []).push(e); }
    }
    $("pill").textContent = lost ? "LOST" : "Not lost";
    $("pill").className = "pill " + (lost ? "lost" : "ok");
    $("b-lost").hidden = lost;
    $("b-found").hidden = false;  // always there: this phone may not know the PC is still lost
    if (where && where.lat !== undefined) {
      $("headline").textContent = "Seen " + place(where) + " - " + ago(where.t);
      const bits = [where.src === "wifi" ? "From the Wi-Fi around it (about " + where.acc + " m)" : "Rough place from its internet address"];
      if (where.wifi) bits.push("On Wi-Fi: " + where.wifi);
      if (where.bat !== null && where.bat !== undefined) bits.push("Battery: " + where.bat + "%" + (where.chg ? " (charging)" : ""));
      if (where.users && where.users.length) bits.push("Signed in: " + where.users.join(", "));
      $("details").textContent = bits.join(" · ");
      const d = Math.max(0.004, (where.acc || 500) / 111000 * 1.6);
      const bbox = [where.lon - d, where.lat - d, where.lon + d, where.lat + d].map((x) => x.toFixed(5)).join(",");
      const src = "https://www.openstreetmap.org/export/embed.html?bbox=" + bbox + "&layer=mapnik&marker=" + where.lat + "," + where.lon;
      if ($("map").getAttribute("src") !== src) $("map").setAttribute("src", src);
      $("maplink").href = "https://www.openstreetmap.org/?mlat=" + where.lat + "&mlon=" + where.lon + "#map=16/" + where.lat + "/" + where.lon;
      $("mapbox").hidden = false;
    } else {
      $("headline").textContent = lost ? "Lost mode is ON - waiting for your PC to report" : "Your PC is not marked lost";
      $("details").textContent = lost ? "It reports every 10 minutes while it is on and has internet."
        : "Nothing is sent on normal days. If it is lost or stolen, tap Mark as lost.";
      $("mapbox").hidden = true;
    }
    const done = Object.keys(photos).map((id) => photos[id]).filter((p) => p.length && new Set(p.map((x) => x.i)).size === p[0].n);
    if (done.length) {
      const p = done[done.length - 1].sort((a, b) => a.i - b.i);
      $("photo").src = "data:image/jpeg;base64," + p.filter((x, i) => i === 0 || x.i !== p[i - 1].i).map((x) => x.d).join("");
      $("photo").hidden = false;
    } else { $("photo").hidden = true; }
    const log = $("log");
    log.textContent = "";
    for (const e of all.slice().reverse().slice(0, 60)) {
      if (e.k === "photo" && e.i !== 0) continue;
      const li = document.createElement("li");
      const when = document.createElement("div");
      when.className = "when";
      when.textContent = new Date((e.t || e.mt) * 1000).toLocaleString();
      li.textContent = e.k === "where" ? "Seen " + place(e) : e.k === "photo" ? "Webcam photo" : (e.text || "Your PC answered");
      li.appendChild(when);
      log.appendChild(li);
    }
  }

  return { render: render };
})();

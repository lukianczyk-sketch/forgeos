// ForgeOS Find My PC (Job 19): the phone page's lock - the same as the PC (locatelib/seal.py).
// One secret key (32 random bytes, after the "#" in the link) makes the relay topic names (HMAC-SHA256)
// and the AES-256-GCM lock key. A locked message is "FMP1." + base64url(12-byte nonce + locked text);
// the direction ("cmd" phone -> PC, "rep" PC -> phone) is locked in too.
"use strict";
const FMP = (() => {
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  function unb64(s) {
    s = String(s).trim().replace(/-/g, "+").replace(/_/g, "/");
    while (s.length % 4) s += "=";
    const b = atob(s);
    const u = new Uint8Array(b.length);
    for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i);
    return u;
  }
  function b64(u) {
    let s = "";
    for (const x of u) s += String.fromCharCode(x);
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  async function mac(key, label) {
    const k = await crypto.subtle.importKey("raw", unb64(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    return new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(label)));
  }
  async function topic(key, name) {
    return "fmp" + b64(await mac(key, "topic:" + name)).slice(0, 21);
  }
  async function aes(key) {
    return crypto.subtle.importKey("raw", await mac(key, "seal"), { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
  }
  async function seal(key, kind, obj) {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: iv, additionalData: enc.encode(kind) },
      await aes(key), enc.encode(JSON.stringify(obj))));
    const all = new Uint8Array(12 + ct.length);
    all.set(iv);
    all.set(ct, 12);
    return "FMP1." + b64(all);
  }
  async function unseal(key, kind, text) {
    try {
      if (typeof text !== "string" || !text.startsWith("FMP1.")) return null;
      const raw = unb64(text.slice(5));
      if (raw.length < 28) return null;
      const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: raw.slice(0, 12), additionalData: enc.encode(kind) },
        await aes(key), raw.slice(12));
      const o = JSON.parse(dec.decode(pt));
      return o && typeof o === "object" && !Array.isArray(o) ? o : null;
    } catch (e) {
      return null;
    }
  }
  function goodKey(k) {
    try {
      return typeof k === "string" && k.length === 43 && unb64(k).length === 32;
    } catch (e) {
      return false;
    }
  }
  return { topic: topic, seal: seal, unseal: unseal, goodKey: goodKey, b64: b64, unb64: unb64 };
})();
if (typeof module !== "undefined") module.exports = FMP;

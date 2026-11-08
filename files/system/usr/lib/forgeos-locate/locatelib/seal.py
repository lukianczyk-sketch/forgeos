"""The lock between the PC and your phone: AES-256-GCM (python3-cryptography), the same as the phone page's
Web Crypto. One secret key (32 random bytes) makes everything:
- the three relay topic names (HMAC-SHA256 of the key): "cmd" (phone -> PC), "rep" (PC -> phone) and
  "bell" (a plain "your PC checked in" for the free ntfy app - no place, no details);
- the lock key (HMAC-SHA256 of the key with "seal").
A locked message is "FMP1." + base64url(12-byte nonce + locked text). The direction ("cmd" / "rep") is
locked in too, so a report can never be played back as a command. Anything changed = it does not open.
"""
import base64
import hashlib
import hmac
import json
import os
import urllib.parse

PREFIX = "FMP1."
KINDS = ("cmd", "rep")


def b64(raw):
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def unb64(text):
    text = str(text).strip()
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def new_key():
    """A new secret key: 43 letters (32 random bytes)."""
    return b64(os.urandom(32))


def good_key(key):
    try:
        return isinstance(key, str) and len(key) == 43 and len(unb64(key)) == 32
    except ValueError:
        return False


def _mac(key, label):
    return hmac.new(unb64(key), label.encode(), hashlib.sha256).digest()


def topic(key, name):
    """The relay topic for cmd / rep / bell: "fmp" + 21 letters nobody can guess without the key."""
    return "fmp" + b64(_mac(key, "topic:" + name))[:21]


def _aes(key):
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    return AESGCM(_mac(key, "seal"))


def seal(key, kind, obj):
    """Lock a small dict for one direction (kind = cmd or rep)."""
    assert kind in KINDS
    nonce = os.urandom(12)
    data = json.dumps(obj, separators=(",", ":"), sort_keys=True).encode()
    return PREFIX + b64(nonce + _aes(key).encrypt(nonce, data, kind.encode()))


def unseal(key, kind, text):
    """Open a locked message; None when it is not ours, changed, or for the other direction."""
    if kind not in KINDS or not isinstance(text, str) or not text.startswith(PREFIX):
        return None
    try:
        raw = unb64(text[len(PREFIX):])
        if len(raw) < 12 + 16:
            return None
        obj = json.loads(_aes(key).decrypt(raw[:12], raw[12:], kind.encode()).decode())
    except Exception:  # noqa: BLE001 - any broken or foreign message is simply not ours
        return None
    return obj if isinstance(obj, dict) else None


def phone_link(page, key, relay="https://ntfy.sh"):
    """The phone page link. The key is after the "#": a phone never sends that part to any website.
    Your own relay (not ntfy.sh) is added as &r=."""
    relay = relay.rstrip("/")
    extra = "" if relay == "https://ntfy.sh" else "&r=" + urllib.parse.quote(relay, safe=":/")
    return page.split("#")[0] + "#k=" + key + extra

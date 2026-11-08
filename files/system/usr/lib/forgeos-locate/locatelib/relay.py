"""The free relay in the middle (ntfy.sh by default; settings.json can point at your own ntfy server).
It only ever carries locked text, and keeps it 12 hours. Python's own urllib: nothing extra to install.
"""
import json
import urllib.error
import urllib.parse
import urllib.request

from . import clean, settings

AGENT = "ForgeOS-FindMyPC/1"
TOO_MANY = 429


def _open(url, data=None, headers=None, timeout=20):
    """(HTTP status, body). No network = (0, "")."""
    h = {"User-Agent": AGENT}
    h.update(headers or {})
    req = urllib.request.Request(url, data=data, headers=h, method="POST" if data is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(400000).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception:  # noqa: BLE001 - a dropped or broken answer (bad Wi-Fi) is the same as no network
        return 0, ""


def post(topic, text, title=None):
    """Send one message to a topic. Returns the HTTP status (200 = sent, 429 = too many, 0 = no network)."""
    headers = {"Content-Type": "text/plain"}
    if title:
        headers["Title"] = clean(title, 60)
    return _open(settings()["relay"].rstrip("/") + "/" + topic, text.encode(), headers)[0]


def poll(topic, since):
    """Messages on a topic after `since` (a message id, or like "12h"). Returns (status, [(id, time, text)])."""
    url = "%s/%s/json?poll=1&since=%s" % (settings()["relay"].rstrip("/"), topic, urllib.parse.quote(since, safe=""))
    status, body = _open(url)
    found = []
    for line in body.splitlines():
        try:
            m = json.loads(line)
        except ValueError:
            continue
        if isinstance(m, dict) and m.get("event") == "message" and isinstance(m.get("message"), str):
            found.append((clean(m.get("id", ""), 40), m.get("time", 0), m["message"]))
    return status, found


def get_json(url, body=None):
    """GET (or POST JSON) a location service; {} when it did not work."""
    data = json.dumps(body).encode() if body is not None else None
    status, text = _open(url, data, {"Content-Type": "application/json"} if data else None)
    if status != 200:
        return {}
    try:
        out = json.loads(text)
    except ValueError:
        return {}
    return out if isinstance(out, dict) else {}

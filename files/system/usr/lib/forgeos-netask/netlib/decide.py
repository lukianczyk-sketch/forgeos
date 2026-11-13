"""The brain: what to do with one new connection OpenSnitch asks about.

Order: program gone = no. Known scam site = blocked, one note. ForgeOS's own programs, the apps ForgeOS
installs and Steam = yes, no question. A saved answer = that answer. Lock down = no for anything new.
In a game or away from the desk = no for now, asked after. Otherwise the question (red for Downloads,
temp and hidden folders, the Fake Tech Support Guard question for remote-control apps).
Returns (action, duration, who): action allow|deny, duration always|once.
"""
import os
import threading

from . import ASK_SECONDS, EXPLAIN_SECONDS, HOSTS, LOCK, clean, now
from . import dialog, history, store, who as whom

BEGIN = "# >>> ForgeOS Always-On Guard"
END = "# <<< ForgeOS Always-On Guard"
_SCAM = {"mtime": None, "set": frozenset()}
_NOTED = {}
_ASKED = {}
MOST_ASKS = int(os.environ.get("FORGEOS_NETASK_MOST_ASKS") or 3)  # more than 3 questions a minute = one list later


def scam_sites():
    """The scam and virus websites Always-On Guard blocks (its marked block in /etc/hosts)."""
    try:
        mtime = os.stat(HOSTS).st_mtime
    except OSError:
        return frozenset()
    if _SCAM["mtime"] != mtime:
        found, inside = set(), False
        try:
            with open(HOSTS, encoding="utf-8", errors="replace") as f:
                for line in f:
                    if line.startswith(BEGIN):
                        inside = True
                    elif line.startswith(END):
                        inside = False
                    elif inside and line.split()[:1] in (["0.0.0.0"], ["::"], ["127.0.0.1"]) and len(line.split()) > 1:
                        found.add(line.split()[1].lower())
        except OSError:
            pass
        _SCAM.update(mtime=mtime, set=frozenset(found))
    return _SCAM["set"]


def is_scam(host):
    host = (host or "").lower().rstrip(".")
    sites = scam_sites()
    while host and "." in host:
        if host in sites:
            return True
        host = host.split(".", 1)[1]
    return False


def note_once(uid, key, text):
    """At most one note per program every 10 minutes."""
    with LOCK:
        if now() - _NOTED.get((uid, key), 0) < 600:
            return
        _NOTED[(uid, key)] = now()
    threading.Thread(target=dialog.note, args=(uid, text), daemon=True).start()


def question(w, host):
    """Ask the person. Returns allow | block | once | "" (no answer = no for now)."""
    to = clean(host or "the internet", 80)
    if w["remote"]:
        mode, extra = "remote", w["remote"][1]
    elif w["red"]:
        mode, extra = "red", w["red"]
    else:
        mode, extra = "normal", w.get("kind", "app")
    got = dialog.ask(w["uid"], [mode, w["name"], to, extra, w.get("path", "")[:300], str(ASK_SECONDS)],
                     ASK_SECONDS + EXPLAIN_SECONDS)
    return got if got in ("allow", "block", "once") else ""


def keep(w, action):
    """Duration for a decision: always (an OpenSnitch rule) when the program can be matched safely, else once."""
    return "always" if w.get("rule_ok") and w.get("md5") and w.get("path") else "once"


def decided(w, answer, host=""):
    """Keep an answer (as an OpenSnitch rule when the program can be matched safely) and return the verdict."""
    action = "allow" if answer == "allow" else "deny"
    d = keep(w, action)
    store.remember(w, answer, store.rule_name(w, action) if d == "always" else "")
    if answer == "block":
        history.blocked(w["uid"], w["key"], w["name"], host, "you blocked it")
    return action, d, w


def handle(c):
    w = whom.identify(c)
    uid, host = w["uid"], c.get("host") or c.get("ip", "")
    if w["gone"]:
        return "deny", "once", w
    if is_scam(host):
        history.blocked(uid, w["key"], w["name"], host, "scam")
        note_once(uid, w["key"], "ForgeOS stopped %s from reaching a known scam website." % w["name"])
        return "deny", "once", w
    saved = store.apps(uid).get(w["key"], {})
    if saved.get("answer") == "block":   # your Block wins, even over ForgeOS's own apps
        return decided(w, "block", host)
    if w["trusted"] and not w["red"] and not w["remote"]:
        if keep(w, "allow") == "always" or saved.get("answer") != "allow":
            return decided(w, "allow")
        return "allow", "once", w
    if w["kind"] == "script" and w.get("system") and not w["red"]:
        return "allow", "once", w
    changed = w["kind"] == "app" and saved.get("md5") and w.get("md5") and saved["md5"] != w["md5"]
    if saved.get("answer") == "allow" and not w["red"] and not changed and w["kind"] != "tool":
        return decided(w, "allow") if keep(w, "allow") == "always" else ("allow", "once", w)
    if store.settings()["lockdown"]:
        history.blocked(uid, w["key"], w["name"], host, "lock down")
        return "deny", "once", w
    with LOCK:
        recent = [t for t in _ASKED.get(uid, []) if now() - t < 60]
        _ASKED[uid] = recent + [now()]
    if len(recent) >= MOST_ASKS or dialog.gaming(uid) or dialog.session_env(uid) is None:
        store.mark_later(w)
        history.blocked(uid, w["key"], w["name"], host, "asked later")
        return "deny", "once", w
    got = question(w, host)
    if got == "allow" and not w["red"] and w["kind"] != "tool":   # a typed command or a tool: never for good
        return decided(w, "allow")
    if got in ("allow", "once"):
        store.remember(w, "ask")
        return "allow", "once", w
    if got == "block":
        return decided(w, "block", host)
    store.remember(w, "ask")
    history.blocked(uid, w["key"], w["name"], host, "no answer")
    return "deny", "once", w

"""Answers given outside a question: the after-game list, and changes from the window (allow / block / ask)."""
from . import ENV, LOCK, clean, now
from . import dialog, store
from .decide import keep

_BUSY = {}
_TRIES = {}
MOST = int(ENV("FORGEOS_NETASK_CONFIRMS") or 5)   # at most 5 confirm questions a minute per person


def after_games(uid):
    """After a game (or back at the desk): one quiet list of the programs that tried meanwhile."""
    waiting = {k: e for k, e in store.apps(uid).items() if e.get("later")}
    if not waiting or dialog.gaming(uid) or dialog.session_env(uid) is None:
        return 0
    # Only plain programs can be ticked; red ones, remote-control apps and typed commands are asked next time.
    can = sorted([(k, e) for k, e in waiting.items() if allowable(e)], key=lambda x: x[1].get("name", "").lower())[:20]
    picked = set()
    if can:
        got = dialog.ask(uid, ["later", str(len(can))] + [clean(e.get("name", "A program"), 60) for _k, e in can], 300)
        picked = {can[int(i) - 1][0] for i in got.split(",") if i.isdigit() and 0 < int(i) <= len(can)}
    with LOCK:   # answers given while the list was open win: only touch what is still waiting, unchanged
        now_saved = store.apps(uid)
        for k, e in waiting.items():
            cur = now_saved.get(k, {})
            if not cur.get("later") or cur.get("md5") != e.get("md5"):
                continue
            w = who_of(uid, k, cur)
            if k in picked:
                allow_saved(w)
            else:
                store.remember(w, "ask")
    return len(waiting)


def allowable(e):
    return not e.get("red") and not e.get("remote") and e.get("kind") != "tool"


def who_of(uid, key, e):
    return dict(e, uid=uid, key=key, rule_ok=bool(e.get("md5") and e.get("kind") not in ("script", "tool", "wine")))


def allow_saved(w):
    """Allow a program from the window or the after-game list (writes its rule right away if it can)."""
    with LOCK:
        name = ""
        if keep(w, "allow") == "always":
            r = store.rule(w, "allow", "always")
            store.write_rule(r)
            name = r["name"]
        store.remember(w, "allow", name)


def block_saved(w):
    with LOCK:
        name = ""
        if keep(w, "deny") == "always":
            r = store.rule(w, "deny", "always")
            store.write_rule(r)
            name = r["name"]
        store.remember(w, "block", name)


def forget(w):
    """Back to "asks each time" (its rules are deleted)."""
    with LOCK:
        store.remember(w, "ask")


def confirm(uid, text):
    """The person said yes on a question the service showed (one at a time, at most 5 a minute)."""
    with LOCK:
        tries = [t for t in _TRIES.get(uid, []) if now() - t < 60]
        if _BUSY.get(uid) or len(tries) >= MOST:
            return False
        _TRIES[uid] = tries + [now()]
        _BUSY[uid] = True
    try:
        return dialog.ask(uid, ["confirm", clean(text, 200)], 90) == "yes"
    finally:
        _BUSY[uid] = False

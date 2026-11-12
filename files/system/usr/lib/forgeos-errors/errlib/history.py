"""What Went Wrong: the plain-English history of the last 30 days, kept only on this PC.

The same error again within a day = one line with a count (and no new pop-up). At most one pop-up every
10 minutes, none while a game runs; serious (red) ones always show, and so does one that got more serious.
"""
import hashlib
import os

from . import GAP, KEEP_DAYS, LEVELS, Lock, clean, data_dir, gaming, load_json, now, save_json

DAY = 86400


def path():
    return os.path.join(data_dir(), "history.json")


def load():
    """Every entry of the last 30 days, newest last."""
    cut = now() - KEEP_DAYS * DAY
    return [e for e in load_json(path(), []) if isinstance(e, dict) and e.get("last", 0) >= cut]


def key_of(card, text):
    """The same error = the same key. AI, unsure and scam cards also carry a short fingerprint of the words,
    so two different messages never become one line."""
    key = card["id"] + ("/" + card["program"] if card.get("program") else "")
    if card["id"] in ("ai", "unsure", "scam-fake-error"):
        key += "/" + hashlib.sha1(clean(text, 4000).encode()).hexdigest()[:10]
    return key


def record(card, src, text="", kept=None):
    """Write CARD down (src = notice, crash, log, screen, copied, asked; KEPT = the words to keep, when not all
    of TEXT). Returns (entry, show a pop-up?)."""
    with Lock():
        items, t, key = load(), now(), key_of(card, text)
        rank = list(LEVELS).index
        for e in reversed(items):
            if e["key"] == key and t - e["first"] < DAY and not e.get("fixed"):
                rose = rank(card["level"]) > rank(e.get("level", "green"))
                e["count"] += 1
                e["last"] = t
                fill(e, card)
                save_json(path(), items)
                return e, (rose or e["level"] == "red") and should_pop(e, again=not rose)
        e = {"key": key, "first": t, "last": t, "count": 1, "src": src, "fixed": False,
             "text": clean(text if kept is None else kept, 300)}
        fill(e, card)
        items.append(e)
        save_json(path(), items[-500:])
        return e, should_pop(e)


def fill(e, card):
    """The card's words on the entry (newest wins)."""
    for k in ("id", "level", "title", "say", "do", "fix", "show", "program"):
        if card.get(k):
            e[k] = card[k]


def should_pop(e, again=False):
    """New serious errors always show; the same serious one again waits 10 minutes like the rest."""
    state_file = os.path.join(data_dir(), "state.json")
    state = load_json(state_file, {})
    if (e["level"] != "red" or again) and (now() - state.get("last_pop", 0) < GAP or gaming()):
        return False
    state["last_pop"] = now()
    save_json(state_file, state)
    return True


def find(key):
    """The newest entry with this key, or None."""
    return next((e for e in reversed(load()) if e["key"] == key), None)


def mark_fixed(key):
    with Lock():
        items = load()
        hit = [e for e in items if e["key"] == key]
        for e in hit:
            e["fixed"] = True
        save_json(path(), items)
        return bool(hit)


def count(prefix, days=7):
    """How many times errors whose key starts with PREFIX happened in the last DAYS days."""
    cut = now() - days * DAY
    return sum(e["count"] for e in load() if e["key"].startswith(prefix) and e["last"] >= cut)

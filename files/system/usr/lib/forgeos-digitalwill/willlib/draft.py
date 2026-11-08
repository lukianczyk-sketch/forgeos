"""Your Digital Will's answers - NO passwords: trusted people, accounts and what should happen to each,
the password safe file, folders to keep, letters and a note. Kept only on this PC (draft.json, only you
can read it). Every change returns "" when it worked, else a plain-English reason."""
import os
import re

from . import DRAFT, HOME, SHARE, clean, load_json, now, save_json

PLANS = {"keep": "Keep it going", "close": "Close it", "give": "Give it to", "memorial": "Make it a memorial page"}
MOST_PEOPLE = 3
MOST_TEXT = 20000


def load():
    d = load_json(DRAFT)
    for key, empty in (("people", []), ("accounts", {}), ("folders", []), ("letters", {}), ("legacy", {})):
        if not isinstance(d.get(key), type(empty)):
            d[key] = empty
    for key in ("note", "safe"):
        d[key] = d.get(key) if isinstance(d.get(key), str) else ""
    return d


def save(d):
    d.setdefault("started", now())
    d["changed"] = now()
    save_json(DRAFT, d)
    return ""


def _list(name):
    """Lines 'a ~ b ~ c' of a list file in /usr/share/forgeos/digitalwill (comments skipped)."""
    rows = []
    try:
        with open(os.path.join(SHARE, name), encoding="utf-8") as f:
            for line in f.read().splitlines():
                parts = [p.strip() for p in line.split(" ~ ")]
                if not line.startswith("#") and len(parts) >= 3 and all(parts):
                    rows.append(parts)
    except OSError:
        pass
    return rows


def catalog():
    """[(id, name, group)] of the account pick-list."""
    return [tuple(r[:3]) for r in _list("accounts.txt")]


def legacy_list():
    """[(id, company, web page or '-', what to do)] of the companies' own after-I'm-gone settings."""
    return [tuple(r[:4]) for r in _list("legacy.txt") if len(r) >= 4]


def person_names(d):
    return [p["name"] for p in d["people"]]


def add_person(name, phone=""):
    d, name, phone = load(), clean(name, 40), clean(phone, 25)
    if not name:
        return "Type a name."
    if name.lower() in (n.lower() for n in person_names(d)):
        return "%s is already on your list." % name
    if len(d["people"]) >= MOST_PEOPLE:
        return "You can pick up to %d trusted people." % MOST_PEOPLE
    d["people"].append({"name": name, "phone": phone})
    return save(d)


def remove_person(name):
    d = load()
    keep = [p for p in d["people"] if p["name"] != name]
    if len(keep) == len(d["people"]):
        return "%s is not on your list." % clean(name, 40)
    d["people"] = keep
    d["letters"].pop(name, None)
    return save(d)


def account_name(d, acc_id):
    for cid, name, _group in catalog():
        if cid == acc_id:
            return name
    return d["accounts"].get(acc_id, {}).get("name", "")


def set_account(acc_id, plan, who="", note="", name=""):
    d = load()
    if plan not in PLANS:
        return "Pick what should happen: " + ", ".join(PLANS) + "."
    if acc_id == "other":
        name = clean(name, 60)
        if not name:
            return "Type the name of the account."
        acc_id = "other-" + (re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:30] or "account")
    elif not account_name(d, acc_id):
        return "That account is not on the list."
    who = clean(who, 40)
    if plan == "give" and who not in person_names(d):
        return "Pick who gets it from your trusted people."
    entry = {"plan": plan, "who": who if plan == "give" else "", "note": clean(note, 200)}
    if acc_id.startswith("other-"):
        entry["name"] = name or d["accounts"].get(acc_id, {}).get("name", "")
    d["accounts"][acc_id] = entry
    return save(d)


def remove_account(acc_id):
    d = load()
    if d["accounts"].pop(acc_id, None) is None:
        return "That account is not on your list."
    return save(d)


def set_safe(path):
    d = load()
    if path:
        path = os.path.realpath(path)
        if not (path.endswith(".kdbx") and os.path.isfile(path)):
            return "Pick your KeePassXC password safe file (it ends in .kdbx)."
    d["safe"] = path
    return save(d)


def set_folders(paths):
    d, real = load(), []
    home = os.path.realpath(HOME)
    for p in paths:
        r = os.path.realpath(p)
        if not os.path.isdir(r) or not r.startswith(home + os.sep):
            return "%s is not a folder in your home folder." % clean(p, 80)
        if os.path.basename(r).startswith("."):
            return "Pick a normal folder, not a hidden one."
        if r not in real:
            real.append(r)
    d["folders"] = real
    return save(d)


def set_letter(name, text):
    d = load()
    if name not in person_names(d):
        return "%s is not one of your trusted people." % clean(name, 40)
    text = text.replace("\r", "").strip()[:MOST_TEXT]
    if text:
        d["letters"][name] = text
    else:
        d["letters"].pop(name, None)
    return save(d)


def set_note(text):
    d = load()
    d["note"] = text.replace("\r", "").strip()[:MOST_TEXT]
    return save(d)


def legacy_done(item, done=True):
    d = load()
    if item not in (r[0] for r in legacy_list()):
        return "That is not on the checklist."
    if done:
        d["legacy"][item] = now()
    else:
        d["legacy"].pop(item, None)
    return save(d)

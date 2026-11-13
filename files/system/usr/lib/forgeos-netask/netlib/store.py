"""What each person answered and the OpenSnitch rules that keep those answers.

Kept by the root service in /var/lib/forgeos-netask (only root can change it): apps-UID.json (one entry per
program: name, answer allow / block / ask, its file and fingerprint) and settings.json (Lock down).
Counts and the blocked list are in history.py.
"""
import hashlib
import json
import os
import re
import time

from . import LOCK, PREFIX, RULES, VAR, load_json, now, save_json


def apps_file(uid):
    return os.path.join(VAR, "apps-%d.json" % int(uid))


def apps(uid):
    return load_json(apps_file(uid), {})


def save_apps(uid, value):
    save_json(apps_file(uid), value)


def settings():
    s = load_json(os.path.join(VAR, "settings.json"), {})
    return {"lockdown": s.get("lockdown") is True}


def save_settings(**changes):
    with LOCK:
        s = settings()
        s.update(changes)
        save_json(os.path.join(VAR, "settings.json"), s, 0o644)


def remember(who, answer, rule=""):
    """Save a person's answer for a program (and the rule that keeps it, if any)."""
    with LOCK:
        a = apps(who["uid"])
        e = a.get(who["key"], {})
        e.update(name=who["name"], kind=who["kind"], answer=answer, path=who.get("path", ""), md5=who.get("md5", ""),
                 when=int(now()), red=who.get("red", ""), later=False, remote=bool(who.get("remote")))
        if who.get("flatpak"):
            e["flatpak"] = who["flatpak"]
        drop_rules({"rules": [r for r in e.get("rules", []) if r != rule]})  # older fingerprints, older answers
        e["rules"] = [rule] if rule else []
        a[who["key"]] = e
        save_apps(who["uid"], a)


def mark_later(who):
    """A program that tried while the person was in a game or away: asked about after the game."""
    with LOCK:
        a = apps(who["uid"])
        e = a.get(who["key"], {"answer": "ask"})
        if e.get("md5") != who.get("md5", "") and e.get("answer") == "allow":
            e["answer"] = "ask"   # its file changed: an old Allow never carries over to the new file
        e.update(name=who["name"], kind=who["kind"], path=who.get("path", ""), md5=who.get("md5", ""),
                 red=who.get("red", ""), later=True, when=int(now()), remote=bool(who.get("remote")))
        a[who["key"]] = e
        save_apps(who["uid"], a)


def rule_name(who, action):
    """500-forgeos-netask-u1000-allow-brave-1a2b3c4d: the answer is in the name, so a changed answer is a new
    file (and the old one is deleted, which OpenSnitch notices)."""
    slug = re.sub(r"[^a-z0-9]+", "-", who["name"].lower()).strip("-")[:30] or "app"
    tag = hashlib.sha1((who["key"] + "|" + who.get("md5", "")).encode("utf-8")).hexdigest()[:8]
    return "%su%d-%s-%s-%s" % (PREFIX, int(who["uid"]), "allow" if action == "allow" else "block", slug, tag)


def rule(who, action, duration):
    """An OpenSnitch rule (as JSON-ready dict) for this program: matches its real file AND its fingerprint
    (MD5) AND the person, so a fake program with the same name or a changed file never matches."""
    ops = [{"type": "simple", "operand": "process.path", "data": who["path"], "sensitive": False, "list": []},
           {"type": "simple", "operand": "user.id", "data": str(int(who["uid"])), "sensitive": False, "list": []}]
    if who.get("md5"):
        ops.insert(1, {"type": "simple", "operand": "process.hash.md5", "data": who["md5"], "sensitive": False,
                       "list": []})
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now()))
    return {"created": stamp, "updated": stamp, "name": rule_name(who, action),
            "description": "ForgeOS Ask Before Connecting: %s (%s)" % (who["name"], action),
            "action": action, "duration": duration, "enabled": True, "precedence": False, "nolog": False,
            "operator": {"type": "list", "operand": "list", "data": "", "sensitive": False, "list": ops}}


def write_rule(r):
    """Write a rule file into OpenSnitch's rules folder (it notices new files by itself)."""
    if not re.match(r"^%s[a-z0-9-]+$" % re.escape(PREFIX), r["name"]):
        raise ValueError("bad rule name")
    # Written in place in one go (OpenSnitch reloads a rule on a write; it ignores a file renamed into place).
    fd = os.open(os.path.join(RULES, r["name"] + ".json"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(json.dumps(r, indent=2) + "\n")


def drop_rules(entry):
    """Delete every rule file this tool wrote for one program."""
    for name in entry.get("rules", []):
        if re.match(r"^%s[a-z0-9-]+$" % re.escape(PREFIX), name):
            try:
                os.unlink(os.path.join(RULES, name + ".json"))
            except FileNotFoundError:
                pass

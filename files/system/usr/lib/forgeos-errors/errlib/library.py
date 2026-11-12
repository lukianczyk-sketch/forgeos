"""The built-in error library: errors we wrote and tested, so the plain words are never a guess.

/usr/share/forgeos/errors/library/*.txt, one error per block (blocks are split by an empty line):
  id: wine-0xc000007b          a short name (small letters, numbers, -)
  match: 0xc000007b            what the error says (a pattern; more match: lines = any of them)
  log: yes                     also look for it in the system log (hidden problems)
  general: yes                 a catch-all: used only when no other entry fits
  level: green|yellow|red      not serious / needs a look / serious
  title: / say: / do:          the card: a short name, what happened, what to do
  fix: open:willitrun          the Fix it button (only from the checked list in fixes.py; may be left out)
  example: ...                 a real error text; 'forgeos-errors check' proves it finds THIS entry
"""
import os
import re

from . import LEVELS, LIBRARY
from . import fixes

KEYS = ("id", "match", "log", "general", "level", "title", "say", "do", "fix", "show", "example")
MANY = ("match", "example")


def parse(text, name):
    """The entries in one file: a list of dicts (match = one compiled pattern). Bad lines -> ValueError."""
    out = []
    for block in re.split(r"\n\s*\n", text.strip()):
        e = {"file": name, "match": [], "example": []}
        for line in block.splitlines():
            if line.startswith("#") or not line.strip():
                continue
            key, sep, value = line.partition(": ")
            if not sep or key not in KEYS:
                raise ValueError("%s: bad line: %s" % (name, line[:60]))
            if key in MANY:
                e[key].append(value.strip())
            elif key in e:
                raise ValueError("%s: %s twice in %s" % (name, key, e.get("id", "?")))
            else:
                e[key] = value.strip()
        if len(e) == 3 and not e["match"]:
            continue
        e["rx"] = re.compile("|".join("(?:%s)" % m for m in e["match"]), re.I)
        out.append(e)
    return out


def load(folder=None):
    """Every entry, file by file in name order."""
    folder = folder or LIBRARY
    entries = []
    try:
        names = sorted(n for n in os.listdir(folder) if n.endswith(".txt"))
    except OSError:
        return []
    for n in names:
        with open(os.path.join(folder, n), encoding="utf-8") as f:
            entries.extend(parse(f.read(), n))
    return entries


def best(text, entries, log=False):
    """The entry that fits TEXT best, or None: a catch-all (general: yes) only when nothing else fits, then
    the longest match wins, then the first one. log=True: only the entries marked 'log: yes' (the system log
    is full of harmless noise)."""
    found = None
    for e in entries:
        if log and e.get("log") != "yes":
            continue
        m = e["rx"].search(text)
        score = (e.get("general") != "yes", len(m.group(0))) if m else None
        if m and (found is None or score > found[0]):
            found = (score, e)
    return found[1] if found else None


def words(text, entries, eid):
    """Only the words of TEXT that matched entry EID (the rest of a pop-up is never kept)."""
    for e in entries:
        m = e["rx"].search(text) if e.get("id") == eid else None
        if m:
            return m.group(0)
    return ""


def problems(entries):
    """What is wrong with the library (empty list = all good): every entry complete, ids unique, fixes and
    guides checked, and every example finds its own entry."""
    bad, seen = [], set()
    for e in entries:
        i = e.get("id", "")
        where = "%s %s" % (e["file"], i or "?")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,40}", i) or i in seen:
            bad.append(where + ": id missing, bad or used twice")
        seen.add(i)
        for k in ("level", "title", "say", "do"):
            if not e.get(k):
                bad.append(where + ": no " + k)
        if e.get("level") not in LEVELS:
            bad.append(where + ": level must be green, yellow or red")
        if e.get("log") not in (None, "yes") or e.get("general") not in (None, "yes"):
            bad.append(where + ": log and general can only be yes")
        if e.get("fix") and not fixes.ok(e["fix"]):
            bad.append(where + ": fix not on the checked list: " + e["fix"])
        if e.get("show") and not fixes.has_guide(e["show"]):
            bad.append(where + ": no Show Me How guide " + e["show"])
        if not e["example"]:
            bad.append(where + ": no example")
        for ex in e["example"]:
            got = best(ex, entries)
            if got is not e:
                bad.append(where + ": example finds %s: %s" % (got.get("id") if got else "nothing", ex[:50]))
        for k in ("title", "say", "do"):
            if re.search(r"\d{3}[-. )]\d{3}[-. ]\d{4}|sudo |\$ |`", e.get(k, "")):
                bad.append(where + ": " + k + " has a phone number or a command")
    return bad

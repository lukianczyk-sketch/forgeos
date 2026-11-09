"""The report cards kept on this PC (one a month, 12 months) and "what changed since last month".

The daily timer (10 minutes after login and every day at 10:00) saves this month's card once, so a missed
month is caught up. If the overall grade went down or a new F showed up, Forge Helper says so
once, with the one thing that would help most - never during a game or a full-screen video.
"""
import json
import os
import re
import time

from . import CARDS, game_on, now, run, start

ORDER = "ABCDF"
KEEP = 12


def month(t):
    return time.strftime("%Y-%m", time.localtime(t))


def load():
    """Saved cards, oldest first. A broken line is skipped."""
    out = []
    try:
        with open(CARDS, encoding="utf-8") as f:
            for line in f:
                try:
                    x = json.loads(line)
                except ValueError:
                    continue
                if isinstance(x, dict) and re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", str(x.get("month"))) \
                        and isinstance(x.get("grades"), dict):
                    out.append(x)
    except OSError:
        pass
    return out


def small(c):
    return {"t": c["time"], "month": month(c["time"]), "grade": c["grade"], "points": c["points"],
            "grades": {s["key"]: s["grade"] for s in c["subjects"] if s["points"] is not None},
            "names": {s["key"]: s["name"] for s in c["subjects"]}}


def save(c):
    keep = [x for x in load() if x["month"] != month(c["time"])] + [small(c)]
    keep.sort(key=lambda x: x["month"])
    os.makedirs(os.path.dirname(CARDS), exist_ok=True)
    with open(CARDS + ".new", "w", encoding="utf-8") as f:
        for x in keep[-KEEP:]:
            f.write(json.dumps(x, sort_keys=True) + "\n")
    os.replace(CARDS + ".new", CARDS)


def before(c):
    """The newest card saved in an earlier month, or None."""
    old = [x for x in load() if x["month"] < month(c["time"])]
    return old[-1] if old else None


def change(c):
    prev = before(c)
    if not prev:
        return "This is the first report card. Next month it shows what changed."
    name = time.strftime("%B", time.strptime(prev["month"], "%Y-%m"))
    moved = []
    for s in c["subjects"]:
        was = prev["grades"].get(s["key"])
        if s["points"] is not None and was and was != s["grade"]:
            moved.append("%s %s to %s (%s)" % (s["name"], was, s["grade"], "better" if s["grade"] < was else "worse"))
    if not moved:
        return "Since %s: no grade changed." % name
    return "Since %s: %s." % (name, "; ".join(moved))


def worse(c, prev):
    """The reason to speak up, or "": the overall grade went down or a subject newly got an F."""
    if not prev or c["points"] is None:
        return ""
    new_f = [s["name"] for s in c["subjects"] if s["grade"] == "F" and prev["grades"].get(s["key"]) != "F"]
    if new_f:
        return "%s got an F on this month's PC Report Card." % " and ".join(new_f)
    if prev.get("grade") in ORDER and ORDER.index(c["grade"]) > ORDER.index(prev["grade"]):
        return "Your PC's report card went from %s to %s this month." % (prev["grade"], c["grade"])
    return ""


def monthly(make):
    """Save this month's card once; say so if it got worse. make() builds the card."""
    if any(x["month"] == month(now()) for x in load()) or game_on():
        return 0
    c = make()
    if c["points"] is None:
        return 0
    prev = before(c)
    save(c)
    why = worse(c, prev)
    if why:
        first = next((s for s in c["subjects"] if s["points"] is not None), None)
        text = why + (" What would help most: %s - %s" % (first["name"], first["why"]) if first else "")
        code, out = run(["notify-send", "--app-name=Forge Helper", "--icon=help-browser", "--wait",
                         "--action=open=Show me", "--action=later=Not now", "Forge Helper", text], 3600)
        if code == 0 and out.strip() == "open":
            start(["forgeos-reportcard-gui"])
    return 0


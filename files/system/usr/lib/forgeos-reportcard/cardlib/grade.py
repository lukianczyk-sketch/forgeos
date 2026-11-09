"""Puts the report card together: every subject at once (the slowest tool sets the time), the overall grade,
and the card as TAB lines (the window), plain words (people, Forge Helper) or JSON.

Overall = the average of the graded subjects, with Safety and Drive health counted double. One F holds the
overall grade to C or lower, so a failing drive can't hide behind good grades elsewhere.
"""
import json
import threading

from . import WORDS, clean, letter, now
from . import drives, more, ready, safety

DOUBLE = ("safety", "drive")
CAP = 79  # the top of a C


def subjects():
    jobs = [safety.safety, safety.updates, drives.drive_and_backup, more.speed, more.space, drives.undo,
            more.privacy, ready.ghost, ready.ready, ready.battery]
    got = [None] * len(jobs)

    def one(i):
        try:
            got[i] = jobs[i]()
        except Exception:  # noqa: BLE001 - one broken reader must never stop the whole card
            got[i] = None

    threads = [threading.Thread(target=one, args=(i,), daemon=True) for i in range(len(jobs))]
    for t in threads:
        t.start()
    for t in threads:
        t.join(180)
    flat = []
    for g in got:
        flat.extend(g if isinstance(g, tuple) else [g] if g else [])
    return flat + [ready.passwords()]


def order(s):
    """Worst first; then "not checked yet"; Passwords (not graded) last."""
    return (0, s["points"], s["name"]) if s["points"] is not None else (1 if s["grade"] else 2, 0, s["name"])


def card(subs=None):
    subs = sorted(subs if subs is not None else subjects(), key=order)
    graded = [s for s in subs if s["points"] is not None]
    if not graded:
        return {"time": int(now()), "grade": "-", "points": None, "words": "Not checked yet",
                "why": "Nothing could be checked yet. Open each tool once, then look again.", "subjects": subs}
    weight = sum(2 if s["key"] in DOUBLE else 1 for s in graded)
    pts = round(sum(s["points"] * (2 if s["key"] in DOUBLE else 1) for s in graded) / weight)
    fails = [s["name"] for s in graded if s["grade"] == "F"]
    if fails and pts > CAP:
        pts = CAP
    g = letter(pts)
    if fails:
        why = "%s %s failing, so the overall grade can't be above C. Fix %s first." % (
            " and ".join(fails), "is" if len(fails) == 1 else "are", "that" if len(fails) == 1 else "those")
    elif graded[0]["grade"] in ("A", "B"):
        why = "Your PC is in good shape. Keep it that way: let it update and keep backing up."
    else:
        why = "Do this first: %s - %s" % (graded[0]["name"], graded[0]["why"])
    return {"time": int(now()), "grade": g, "points": pts, "words": WORDS[g], "why": clean(why, 300), "subjects": subs}


def lines(c, change=""):
    out = ["OVERALL\t%s\t%s\t%s\t%s" % (c["grade"], "-" if c["points"] is None else c["points"], c["words"], c["why"])]
    for s in c["subjects"]:
        out.append("\t".join(["SUBJECT", s["key"], s["grade"] or "-", "-" if s["points"] is None else str(s["points"]),
                              s["name"], s["button"] or "-", s["tool"], s["why"]]))
    if change:
        out.append("CHANGE\t" + clean(change, 300))
    return out


def words(c, change=""):
    head = "PC Report Card: %s" % (c["grade"] + " - " + c["words"] if c["points"] is not None else c["words"])
    out = [head, c["why"], ""]
    for s in c["subjects"]:
        g = s["grade"] if s["points"] is not None else ("not checked yet" if s["grade"] else "not graded")
        out.append("%s: %s. %s" % (s["name"], g, s["why"]))
    if change:
        out += ["", change]
    return "\n".join(out)


def as_json(c, change=""):
    return json.dumps(dict(c, change=change), indent=1, sort_keys=True)


def is_good(c):
    """True when every graded subject is an A or a B."""
    return c["points"] is not None and all(s["grade"] in ("A", "B") for s in c["subjects"] if s["points"] is not None)

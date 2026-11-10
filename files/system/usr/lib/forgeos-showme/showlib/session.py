"""One Show Me How walk: open the right place first, then look at the screen every 2 seconds.

draw() (show.py) points with the KWin overlay and shows the Back / Next / Stop panel. plain() is the same walk
with no drawing: it prints one VIEW line per look (for the tests and for a terminal).
"""
import json
import os
import time

from . import ENV, QML, SCRIPT, TICK, clean, now, run, start, stranger
from . import screen

TITLE = "Show Me How"
ENDS = {"done": "All done! You did it yourself.",
        "stuck": "Show Me How stopped: nothing changed for 2 minutes.",
        "unsure": "I'm not sure what to click next, so I won't guess.",
        "stranger": "Show Me How stopped because someone else can see or control this screen right now."
                    " Nobody should guide you from outside this PC.",
        "stopped": "Stopped."}


def desktop_file(app):
    """The .desktop file of an app (normal or Flatpak), or None."""
    home = os.path.expanduser("~")
    dirs = [os.path.join(ENV("XDG_DATA_HOME") or os.path.join(home, ".local", "share"))]
    dirs += (ENV("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    dirs += [os.path.join(home, ".local/share/flatpak/exports/share"), "/var/lib/flatpak/exports/share"]
    for d in dirs:
        path = os.path.join(d, "applications", app + ".desktop")
        if d and os.path.isfile(path):
            return path
    return None


def open_place(guide):
    """Open the exact page the guide starts on (fewer steps, fewer places to get lost). True when started."""
    kind, arg = guide["open"] if guide else ("none", "")
    if kind == "settings":
        return start(["systemsettings", arg]) is not None
    if kind == "window":
        return start([arg]) is not None
    if kind == "app":
        path = desktop_file(arg)
        return bool(path) and start(["gio", "launch", path]) is not None
    return False


def written(guide, card=None):
    """The steps in writing, for when it can't point (or the person wants to read them)."""
    if guide:
        return "\n".join("%d. %s" % (n, s["say"]) for n, s in enumerate(guide["steps"], 1))
    return card[1] if card else "Ask Forge Helper (Meta+H) in your own words."


def plain(walk, guide, card=None):
    """The walk with no drawing. FORGEOS_SHOWME_FAST=1: no waiting, the clock moves 2 s per look."""
    fast = ENV("FORGEOS_SHOWME_FAST") == "1"
    t0 = now()
    open_place(guide)
    for n in range(int(ENV("FORGEOS_SHOWME_LOOKS") or 200)):
        if stranger():
            print("END\tstranger\t" + ENDS["stranger"])
            return 1
        t = t0 + n * TICK if fast else now()
        v = walk.tick(screen.look(), [], t)
        where = " ".join(str(v.get(k, "-")) for k in ("x", "y", "w", "h"))
        print("VIEW\t%s\t%d/%d\t%s\t%s\t%s" % (v["mode"], v["step"], v["total"], where, v["corner"], v["say"]))
        if v["mode"] == "lost":
            print("WRITTEN\t" + clean(written(guide, card).replace("\n", " / "), 600))
            return 1
        if walk.end:
            print("END\t%s\t%s" % (walk.end, ENDS[walk.end]))
            return 0 if walk.end == "done" else 1
        if not fast:
            time.sleep(TICK)
    print("END\tstuck\t" + ENDS["stuck"])
    return 1


def state(view, big):
    """The JSON the overlay reads over D-Bus (only numbers, a short sentence and a corner)."""
    v = {k: view.get(k) for k in ("show", "x", "y", "w", "h", "say", "step", "total", "corner") if k in view}
    v["size"] = big
    return json.dumps(v)


def own(text):
    """Our own label + step panel as parts of the screen (sent by the overlay), so they are never pointed at."""
    try:
        rects = json.loads(text)
        return [[max(0.0, min(1.0, float(n))) for n in r[:4]] for r in rects[:4] if len(r) >= 4]
    except (ValueError, TypeError):
        return []


KWIN = ["busctl", "--user", "call", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting"]


def overlay(on):
    """Load (and start) or unload our one fixed KWin overlay script. True when KWin took it."""
    run(KWIN + ["unloadScript", "s", SCRIPT], 10)
    if not on:
        return True
    code, out = run(KWIN + ["loadDeclarativeScript", "ss", QML, SCRIPT], 10)
    if code != 0 or out.strip() in ("", "i -1"):
        return False
    return run(KWIN + ["start"], 10)[0] == 0


def panel(v, guide, card=None):
    """The kdialog step panel: Next / Back / Stop (Esc = Stop), or Try again when it can't see the thing."""
    n = "Step %d of %d" % (v["step"], v["total"]) if v["total"] else "Step %d" % v["step"]
    if v["mode"] == "lost":
        labels = ["Try again", "Show me where to start", "Stop"]
        text = "%s\n\nThe steps in writing:\n%s" % (v["say"], written(guide, card))
    else:
        labels = ["Next", "Back", "Stop"]
        text = "%s\n\n%s\n\nYou do the clicking. Show Me How only points." % (n, v["say"])
    return ["kdialog", "--title", TITLE, "--yes-label", labels[0], "--no-label", labels[1],
            "--cancel-label", labels[2], "--yesnocancel", text]


def end_text(why, guide, card=None):
    text = ENDS.get(why, ENDS["stopped"])
    return text if why in ("done", "stopped") else text + "\n\nThe steps in writing:\n" + written(guide, card)

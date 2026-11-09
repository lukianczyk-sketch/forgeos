"""Checks 1-4: a busy program, memory, a full drive, a slow or failing drive (heat and power: hot.py).

Each check returns a list of findings: ("problem", id, red|yellow, text, fix, button) or ("ok", id, text).
"""
import os

from . import ENV, GB, HOME, clean, game_on, meminfo, pressure, run, size_words
from .procs import mine


def problem(cid, level, text, fix="-", button="-"):
    """Every part is one clean line, so a program's name can never add a fake line or button."""
    return ("problem", cid, level, clean(text, 600), clean(fix, 80), clean(button, 60))


def ok(cid, text):
    return ("ok", cid, clean(text, 200))


def busy(apps):
    top = next((a for a in apps if not a["keep"] and not a["bad"]), None)
    if not top or top["cpu"] < 80:
        return [ok("busy", "No program is hogging the computer's power.")]
    cpu = pressure("cpu").get("some10", 0)
    level = "red" if top["cpu"] >= 200 or cpu >= 40 else "yellow"
    text = "%s is using most of the computer's power." % top["name"]
    if top["game"] or game_on():
        return [problem("busy", "yellow", text + " That is normal while a game is running.")]
    if not mine(top):
        return [problem("busy", level, text + " It is part of the system and usually finishes by itself.")]
    return [problem("busy", level, text + " Closing it makes the PC fast again (unsaved work in it may be lost).",
                    "close %d %s" % (top["main"], top["app"]), "Close " + top["name"])]


def memory(apps):
    total, avail = meminfo()
    if not total:
        return []
    p = pressure("memory")
    pct = avail * 100.0 / total
    if pct >= 15 and p.get("some60", 0) < 10 and p.get("full10", 0) < 5:
        return [ok("memory", "Memory: %s free of %s." % (size_words(avail), size_words(total)))]
    level = "red" if pct < 5 or p.get("full10", 0) >= 10 else "yellow"
    big = max((a for a in apps if not a["keep"] and not a["bad"]), key=lambda a: a["rss"], default=None)
    text = "The memory is nearly full (%s free of %s), so the PC has to wait." % (size_words(avail), size_words(total))
    if big and big["rss"] >= total / 10:
        text += " %s is using %s." % (big["name"], size_words(big["rss"]))
        if big["app"].lower().endswith(("browser", "firefox", "chrome", "chromium", "brave")):
            text += " Every open tab uses memory - closing tabs you don't need helps."
    if total < 12 * GB:
        text += " This PC has %s of memory; 16 GB would fix this for good." % size_words(total)
    if big and mine(big) and big["rss"] >= total / 10:
        return [problem("memory", level, text, "close %d %s" % (big["main"], big["app"]), "Close " + big["name"])]
    return [problem("memory", level, text)]


def disk():
    fake = (ENV("FORGEOS_SLOW_DF") or "").split()  # the tests: "TOTAL FREE" in bytes
    try:
        s = os.statvfs(HOME)
        total, free = s.f_blocks * s.f_frsize, s.f_bavail * s.f_frsize
    except OSError:
        return []
    if len(fake) == 2:
        total, free = int(fake[0]), int(fake[1])
    if not total:
        return []
    pct = free * 100.0 / total
    if pct >= 10 and free >= 5 * GB:
        return [ok("disk", "Drive space: %s free." % size_words(free))]
    level = "red" if pct < 5 or free < 3 * GB else "yellow"
    return [problem("disk", level, "Your drive is nearly full (%s free). A full drive makes everything slow."
                    % size_words(free), "space", "Free up space")]


def drive():
    code, out = run(["forgeos-drivehealth", "status"], 30)
    lvl = next((x.split("\t")[2] for x in out.splitlines() if x.startswith("CHECKED\t") and x.count("\t") >= 2), "")
    if code in (1, 2) and lvl in ("watch", "danger"):
        word = "may be failing - back up your files today" if lvl == "danger" else "shows early warning signs"
        return [problem("drive", "red" if lvl == "danger" else "yellow",
                        "A drive %s. A failing drive is often very slow." % word, "drivehealth", "Open Drive Health")]
    if pressure("io").get("some60", 0) >= 30:
        return [problem("drive", "yellow", "The PC keeps waiting for the drive (something is reading or writing"
                        " a lot). If this happens often, open Drive Health.", "drivehealth", "Open Drive Health")]
    return [ok("drive", "The drive keeps up.")]

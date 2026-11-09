"""Subjects 9-11: hidden devices (GhostFinder's last sweep), ready for trouble (Digital Will + Find My PC),
the battery (laptops only) - and Passwords, shown but not graded until Job 28.
"""
import os
import re

from . import DATA, days_ago, load_json, one, rows, run, subject, worst


def ghost():
    s = load_json(os.path.join(DATA, "forgeos", "ghost", "last-sweep.json"), {})
    if not isinstance(s, dict) or s.get("level") not in ("red", "yellow", "green"):
        return subject("ghost", "Hidden devices", None, "No sweep for hidden cameras and trackers yet.", "ghost")
    days = days_ago(s["time"]) if isinstance(s.get("time"), (int, float)) else 0
    items = [i for i in s.get("items") or [] if isinstance(i, dict) and i.get("level") == s["level"]]
    what = (": " + str(items[0].get("what", ""))) if items else ""
    pts, why = {"red": (45, "The last sweep found something to check" + what),
                "yellow": (75, "The last sweep found something to look at" + what),
                "green": (100, "The last sweep found nothing worrying")}[s["level"]]
    if days > 90:
        pts, why = min(pts, 85), why + ". Sweep again - the last one was %d days ago" % days
    return subject("ghost", "Hidden devices", pts, why + ".", "ghost")


def ready():
    bad, heard = [], 0
    w = rows(run(["forgeos-digitalwill", "status"], 60)[1])
    if "ENVELOPE" in w:
        heard += 1
        made, old = one(w, "ENVELOPE"), one(w, "ENVELOPE", 1, "-")
        if made in ("", "-"):
            bad.append((20, "no Emergency Envelope yet (Digital Will)", "digitalwill"))
        elif old.isdigit() and int(old) > 365:
            bad.append((10, "the Emergency Envelope is over a year old", "digitalwill"))
    f = rows(run(["forgeos-locate", "status"], 60)[1])
    if "SETUP" in f:
        heard += 1
        if one(f, "SETUP") != "yes":
            bad.append((20, "Find My PC is not set up", "locate"))
    if not heard:
        return subject("ready", "Ready for trouble", None, "Digital Will and Find My PC did not answer.", "digitalwill")
    pts, why, tool = worst(bad, "Digital Will and Find My PC are set up.", "digitalwill")
    return subject("ready", "Ready for trouble", pts, why, tool)


def battery():
    """Laptops only (None on a desktop PC): how much the battery holds compared to new."""
    for dev in run(["upower", "-e"], 20)[1].split():
        info = run(["upower", "-i", dev], 20)[1]
        m = re.search(r"^\s*capacity:\s*([\d.]+)%", info, re.M)
        if "battery_" in dev and re.search(r"^\s*power supply:\s*yes", info, re.M) and m:
            c = min(100.0, float(m.group(1)))
            pts = 100 if c >= 80 else 85 if c >= 70 else 72 if c >= 60 else 62 if c >= 50 else 45
            tip = " A new battery brings back the hours." if c < 70 else ""
            return subject("battery", "Battery", pts, "It holds %d%% of what it held when new.%s" % (c, tip))
    return None


def passwords():
    s = subject("passwords", "Passwords", None, "Coming with Password Breach Alarm (Job 28) - not graded yet.")
    s.update(grade="", button="")
    return s

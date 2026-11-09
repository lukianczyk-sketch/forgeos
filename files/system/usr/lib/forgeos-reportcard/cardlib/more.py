"""Subjects 4, 5 and 8: speed, room to work, privacy.

Speed uses Why Is It Slow?'s own 7-day history and its own idea of "slow"; privacy reads the Privacy
Report's own notes. Nothing new is measured.
"""
import collections
import os
import re
import sys

from . import DAY, ENV, HOME, now, run, subject


def speed():
    sys.path.insert(0, ENV("FORGEOS_SLOW_LIB") or "/usr/lib/forgeos-slow")
    try:
        from slowlib import history
        samples = history.load(7 * DAY)
    except Exception:  # noqa: BLE001 - a broken history must never stop the report card
        return subject("speed", "Speed", None, "Why Is It Slow? could not be read.", "slow")
    if len(samples) < 12:
        return subject("speed", "Speed", None, "Not enough history yet - it fills in while the PC is on.", "slow")
    # A busy processor alone is left out: games use it all on purpose (Why Is It Slow? shows busy programs live).
    why = [re.sub(r" \(.*\)", "", history.cause(s)) for s in samples]
    why = [w for w in why if "most of the computer's power" not in w]
    slow = [w for w in why if w]
    pct = 100.0 * len(slow) / len(samples)
    pts = 100 if pct < 2 else 88 if pct < 5 else 78 if pct < 10 else 65 if pct < 20 else 50
    if not slow:
        return subject("speed", "Speed", pts, "It was never slow in the last 7 days.", "slow")
    top = collections.Counter(slow).most_common(1)[0][0]
    return subject("speed", "Speed", pts, "Slow about %d%% of the time in the last 7 days, mostly because %s."
                   % (max(1, round(pct)), top), "slow")


def space():
    try:
        free, total = (int(x) for x in ENV("FORGEOS_CARD_SPACE").split()) if ENV("FORGEOS_CARD_SPACE") else (
            (lambda v: (v.f_bavail * v.f_frsize, v.f_blocks * v.f_frsize))(os.statvfs(HOME)))
    except (OSError, ValueError, AttributeError):
        return subject("space", "Room to work", None, "The drive's free space could not be read.", "space")
    if not total:
        return subject("space", "Room to work", None, "The drive's free space could not be read.", "space")
    pct = 100.0 * free / total
    pts = 100 if pct >= 25 else 85 if pct >= 15 else 72 if pct >= 10 else 62 if pct >= 5 else 45
    tip = "" if pct >= 15 else " Free up space so the PC can work and update."
    return subject("space", "Room to work", pts, "%.0f GB free (%d%% of the drive).%s" % (free / 1e9, pct, tip), "space")


def privacy():
    out = run(["systemctl", "--user", "is-active", "forgeos-privacy-watch.service"], 10)[1]
    if out.strip() not in ("active", "inactive", "failed"):
        return subject("privacy", "Privacy", None, "The Privacy Report did not answer.", "privacy")
    if out.strip() != "active":
        return subject("privacy", "Privacy", 60, "The Privacy Report is off - it can't note which apps use "
                       "the camera and microphone.", "privacy")
    state = ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
    apps = set()
    try:
        with open(os.path.join(state, "forgeos-privacy", "usage.log"), encoding="utf-8", errors="replace") as f:
            for line in f:
                p = line.rstrip("\n").split("\t")
                if len(p) >= 5 and p[1] == "start" and p[0].isdigit() and now() - int(p[0]) < 7 * DAY:
                    apps.add(p[4])
    except OSError:
        pass
    if not apps:
        return subject("privacy", "Privacy", 100, "On. No app used the camera, microphone or screen this week.", "privacy")
    names = ", ".join(sorted(apps)[:3]) + (" and more" if len(apps) > 3 else "")
    return subject("privacy", "Privacy", 100, "On. %d app%s used the camera, microphone or screen this week (%s). "
                   "Have a look if one surprises you." % (len(apps), "" if len(apps) == 1 else "s", names), "privacy")

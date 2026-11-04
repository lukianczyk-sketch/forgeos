"""Is there a backup, and how old is it? (Pika Backup, the free backup app in ForgeOS.)"""
import json
import os

from . import DAY, ENV, HOME, now

PIKA = ENV("FORGEOS_DH_PIKA") or os.path.join(HOME, ".var", "app", "org.gnome.World.PikaBackup", "config",
                                               "pika-backup")


def status():
    """{"set": True/False, "last": time of the last backup or 0, "days": whole days since it or None}."""
    try:
        with open(os.path.join(PIKA, "backup.json"), encoding="utf-8") as f:
            set_up = bool(json.load(f))
    except (OSError, ValueError):
        set_up = False
    try:
        last = os.path.getmtime(os.path.join(PIKA, "histories.json")) if set_up else 0
    except OSError:
        last = 0
    days = int((now() - last) // DAY) if last else None
    return {"set": set_up, "last": last, "days": days}


def words(b):
    if not b["set"]:
        return "No backup is set up yet. Drives can die without any warning - set one up with \"Back up now\"."
    if b["days"] is None:
        return "A backup is set up, but it has not run yet. Press \"Back up now\"."
    when = "today" if b["days"] == 0 else "yesterday" if b["days"] == 1 else "%d days ago" % b["days"]
    old = " That is old - make a fresh one." if b["days"] >= 14 else ""
    return "Your last backup was %s.%s" % (when, old)

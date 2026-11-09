"""Checks 7, 8, 10, 11: background jobs, start-up, a restart that is due, a hidden program (internet: net.py)."""
import json
import re

from . import run
from .checks import ok, problem
from .hot import uptime_days
from .startup import entries

# Background jobs: (program names, at least this much processor %, what it is, fix, button)
JOBS = [
    (("rpm-ostree", "bootc", "uupd"), 5, "ForgeOS is downloading or installing an update. It finishes by itself"
     " - you can keep working.", "-", "-"),
    (("flatpak", "flatpak-system-helper"), 15, "Apps are being updated. It finishes by itself in a few minutes.",
     "-", "-"),
    (("clamscan", "clamd", "freshclam"), 30, "The virus checker is busy scanning. It finishes by itself.", "-", "-"),
    (("forgeos-find",), 15, "Find Anything is reading your files so it can find them later.", "pause find",
     "Pause it for now"),
    (("forgeos-cleansweep",), 15, "Clean Sweep's weekly safety check is running. It finishes by itself.", "-", "-"),
    (("fossilize_replay",), 15, "Steam is getting a game ready to play. It finishes by itself.", "-", "-"),
]


def background(apps):
    found = []
    for names, most, text, fix, button in JOBS:
        hit = [a for a in apps if any(a["comm"] == n or (len(a["comm"]) == 15 and n.startswith(a["comm"]))
                                      for n in names)]  # the kernel cuts names to 15 letters
        if hit and sum(a["cpu"] for a in hit) >= most and text not in [f[3] for f in found]:
            found.append(problem("background", "yellow", text, fix, button))
    return found or [ok("background", "No big jobs running in the background.")]


def seconds(text):
    """'1min 5.2s' -> 65.2 (systemd-analyze's way of writing times)."""
    total = 0.0
    for num, unit in re.findall(r"([0-9.]+)\s*(min|ms|s)\b", text):
        total += float(num) * {"min": 60, "s": 1, "ms": 0.001}[unit]
    return total


def startup():
    code, out = run(["systemd-analyze", "time"], 20)
    m = re.search(r"\+ ([0-9.minms ]+?) \(userspace\)", out) if code == 0 else None
    secs = seconds(m.group(1)) if m else 0  # only the part programs can change (not the BIOS or the disk password)
    on = [e for e in entries() if e["on"]]
    if secs < 60 and len(on) < 6:
        return [ok("startup", "Start-up: %d programs start with the PC." % len(on))]
    text = ("Starting the desktop and programs takes about %d seconds." % secs if secs >= 60
            else "%d programs start with the PC." % len(on))
    if on:
        text += " Programs that start with it: %s." % ", ".join(e["name"] for e in on[:5])
        return [problem("startup", "yellow", text + " Switching off the ones you don't need makes it faster.",
                        "startup", "Choose what starts")]
    return [problem("startup", "yellow", text)]


def update_waiting():
    code, out = run(["rpm-ostree", "status", "--json"], 30)
    try:
        dep = json.loads(out).get("deployments", []) if code == 0 else []
    except ValueError:
        dep = []
    return bool(dep) and dep[0].get("booted") is False


def restart():
    days, waiting = uptime_days(), update_waiting()
    if days < 14 and not waiting:
        return [ok("restart", "Restarted recently.")]
    parts = (["Your PC has been on for %d days." % days] if days >= 14 else []) + (
        ["An update is waiting for a restart."] if waiting else [])
    return [problem("restart", "yellow", " ".join(parts + ["A restart clears out old clutter."]), "restart",
                    "Restart now")]


def hidden(apps):
    bad = next((a for a in apps if a["cpu"] >= 30 and a["bad"]), None)
    if not bad:
        return []
    where = bad["exe"].replace(" (deleted)", " - a file that was deleted")
    return [problem("hidden", "red", "Something hidden is using the computer's power: \"%s\" runs from %s. That"
                    " is a trick some viruses use. Clean Sweep checks it and locks it away if it is bad."
                    % (bad["name"], where), "cleansweep", "Run Clean Sweep")]


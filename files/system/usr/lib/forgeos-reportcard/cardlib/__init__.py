"""ForgeOS PC Report Card (Job 21): shared paths and small helpers.

It runs as the person at the PC (no password) and only reads: the other ForgeOS tools' "status" answers and
their saved results. It keeps one small file of past report cards (12 months). Nothing is sent anywhere.
"""
import json
import os
import re
import subprocess
import time

ENV = os.environ.get
HOME = os.path.expanduser("~")
STATE = os.path.join(ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "forgeos", "reportcard")
CARDS = os.path.join(STATE, "cards.jsonl")
DATA = ENV("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
GB = 1024 ** 3
DAY = 86400
LETTERS = ((90, "A"), (80, "B"), (70, "C"), (60, "D"), (0, "F"))
WORDS = {"A": "Excellent", "B": "Good", "C": "Needs some care", "D": "Needs care soon", "F": "Needs help now"}


def now():
    """The clock (FORGEOS_CARD_NOW moves it for the tests)."""
    return float(ENV("FORGEOS_CARD_NOW") or time.time())


def run(cmd, timeout=60):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                           timeout=timeout, env=dict(os.environ, LC_ALL="C"))  # English output to read
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def start(cmd):
    """Start a window and do not wait for it."""
    try:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def rows(out):
    """A tool's TAB lines: {"FIRST WORD": [[the rest of line 1], [line 2]...]}."""
    found = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if parts[0] and parts[0].isupper():
            found.setdefault(parts[0], []).append(parts[1:])
    return found


def one(found, word, i=0, default=""):
    """Field i of the first WORD line, or default."""
    got = found.get(word) or [[]]
    return got[0][i] if len(got[0]) > i else default


def age(day):
    """Whole days since a "2026-11-01" / "2026-11-01 14:30" date; None when it is not a date."""
    try:
        return days_ago(time.mktime(time.strptime(day[:10], "%Y-%m-%d")))
    except (ValueError, TypeError, OverflowError):
        return None


def clean(text, most=160):
    """One line, no < > tabs or control characters, at most `most` characters."""
    text = re.sub(r"[<>\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def letter(points):
    return next(g for low, g in LETTERS if points >= low)


def subject(key, name, points, why, tool="-", check=False):
    """One line of the report card. points None = "Not checked yet" (no grade, no penalty)."""
    if points is not None:
        points = max(0, min(100, int(round(points))))
    return {"key": key, "name": name, "points": points, "grade": letter(points) if points is not None else "-",
            "why": clean(why), "tool": tool, "button": "Check now" if points is None else "Raise this grade"}


def worst(found, good, tool):
    """(points, sentence, tool) from [(points off, words, tool)...]; the biggest problems are said first."""
    found.sort(key=lambda x: -x[0])
    if not found:
        return 100, good, tool
    words = "; ".join(w for _, w, _ in found[:2])
    return 100 - sum(x[0] for x in found), words[:1].upper() + words[1:] + ".", found[0][2]


def days_ago(t):
    return int((now() - t) // DAY)


def load_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def game_on():
    """True while a game or a full-screen video is playing (same check as Why Is It Slow? and Forge Helper)."""
    code, out = run(["busctl", "--user", "call", "org.freedesktop.PowerManagement.Inhibit",
                     "/org/freedesktop/PowerManagement/Inhibit", "org.freedesktop.PowerManagement.Inhibit",
                     "HasInhibit"], 10)
    if code == 0 and out.strip() == "b true":
        return True
    code, out = run(["gamemoded", "-s"], 10)
    if code == 0 and "is active" in out:
        return True
    return run(["pgrep", "-x", "gamescope"], 10)[0] == 0

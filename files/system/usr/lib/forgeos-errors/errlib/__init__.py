"""ForgeOS Plain-English Errors (Job 23): shared paths and small helpers.

When something goes wrong, the PC says what happened in plain English: what happened, is it serious, what to
do, with one Fix it button. It runs as the person at the PC (no password). Fixes come only from a short checked
list and each one needs a Yes first. Nothing leaves the PC.
"""
import fcntl
import json
import os
import re
import shutil
import subprocess
import tempfile
import time

ENV = os.environ.get
SHARE = ENV("FORGEOS_ERRORS_SHARE") or "/usr/share/forgeos/errors"
LIBRARY = os.path.join(SHARE, "library")
APP = "ForgeOS Errors"   # our own pop-ups use this name, so the listener never explains itself
KEEP_DAYS = 30           # the What Went Wrong history is kept on the PC for 30 days
GAP = 600                # at most one pop-up every 10 minutes (serious ones may come sooner)
RULE = "Real errors never show a phone number and never ask for money."
LEVELS = {"green": "Not serious.", "yellow": "Needs a look soon.", "red": "Serious. Act now."}


def now():
    """The clock (FORGEOS_ERRORS_NOW moves it for the tests)."""
    return float(ENV("FORGEOS_ERRORS_NOW") or time.time())


def data_dir():
    """~/.local/share/forgeos/errors, only this person's."""
    base = ENV("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    path = os.path.join(base, "forgeos", "errors")
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def run(cmd, timeout=30, data=None):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, input=data, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           stdin=None if data is not None else subprocess.DEVNULL,
                           timeout=timeout, env=dict(os.environ, LC_ALL="C"))
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def start(cmd):
    """Start a program and do not wait for it (in its own scope, so stopping the watcher never stops a window
    it opened). Returns True when it started."""
    if not shutil.which(cmd[0]):
        return False
    try:
        subprocess.Popen(["systemd-run", "--user", "--scope", "--quiet", "--"] + cmd, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def clean(text, most=300):
    """One line, no < > tabs or control characters, at most `most` characters."""
    text = re.sub(r"[<>\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def load_json(path, empty):
    try:
        with open(path, encoding="utf-8") as f:
            got = json.load(f)
        return got if isinstance(got, type(empty)) else empty
    except (OSError, ValueError):
        return empty


def save_json(path, value):
    """Write a whole new file, then swap it in (a crash never leaves half a file)."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".new-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(value, f)
        os.replace(tmp, path)
    except OSError:
        os.unlink(tmp)
        raise


class Lock:
    """Only one program changes the history at a time (the watcher, the window and pop-ups run together)."""

    def __enter__(self):
        self.f = open(os.path.join(data_dir(), "history.lock"), "a")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *_):
        self.f.close()


def gaming():
    """True while a game runs (GameMode on, or Steam's gamescope / a Steam game): pop-ups wait, only serious
    ones still show."""
    code, out = run(["gamemoded", "-s"], 10)
    if code == 0 and "is active" in out:
        return True
    return run(["pgrep", "-f", "gamescope|SteamLaunch AppId="], 10)[0] == 0

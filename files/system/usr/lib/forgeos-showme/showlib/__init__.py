"""ForgeOS Show Me How (Job 22): shared paths and small helpers.

It runs as the person at the PC (no password). It only LOOKS at the screen (a quiet screenshot read with
Tesseract, deleted at once) and draws an arrow on top. It never clicks, types or changes a setting.
"""
import os
import re
import subprocess
import time

ENV = os.environ.get
SHARE = ENV("FORGEOS_SHOWME_SHARE") or "/usr/share/forgeos/showme"
GUIDES = os.path.join(SHARE, "guides")
QML = os.path.join(SHARE, "overlay.qml")
NAME = "org.forgeos.ShowMe"   # our D-Bus name; the overlay asks it where to point
PATH = "/ShowMe"
SCRIPT = "forgeos-showme"     # the KWin script name
TICK = 2.0                    # look at the screen every 2 seconds
STUCK = 120                   # stop after 2 minutes with no progress


def now():
    """The clock (FORGEOS_SHOWME_NOW moves it for the tests)."""
    return float(ENV("FORGEOS_SHOWME_NOW") or time.time())


def runtime():
    """A private folder in memory for the screenshots ($XDG_RUNTIME_DIR is RAM, only this person's)."""
    base = ENV("XDG_RUNTIME_DIR") or "/tmp"
    path = os.path.join(base, "forgeos-showme-%d" % os.getuid())
    os.makedirs(path, mode=0o700, exist_ok=True)
    os.chmod(path, 0o700)
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
    """Start a program and do not wait for it. Returns the process, or None."""
    try:
        return subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return None


def clean(text, most=160):
    """One line, no < > tabs or control characters, at most `most` characters."""
    text = re.sub(r"[<>\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def norm(text):
    """Words to compare: small letters, no punctuation ("Add Printer..." = "add printer")."""
    return " ".join(re.findall(r"[a-z0-9&+]+", text.lower()))


def facts(cmd):
    """A ForgeOS tool's TAB lines as {"FIRST": [rest of the first such line]}."""
    found = {}
    for line in run(cmd, 20)[1].splitlines():
        parts = line.split("\t")
        if len(parts) > 1 and parts[0].isupper():
            found.setdefault(parts[0], parts[1:])
    return found


def size():
    """How big to draw: 1, or Family Mode's big (1.4) / bigger (1.8) text."""
    f = facts(["forgeos-family", "status"])
    if (f.get("STATUS") or [""])[0] != "on":
        return 1.0
    return {"big": 1.4, "bigger": 1.8}.get((f.get("SIZE") or [""])[0], 1.0)


def stranger():
    """True when someone can see or control this screen (Fake Tech Support Guard): then Show Me How stops."""
    for line in run(["forgeos-techguard", "status"], 20)[1].splitlines():
        p = line.split("\t")
        if (p[0] == "SHARING" and len(p) > 1 and p[1] not in ("-", "")) or (p[0] == "ALARM" and p[2:3] == ["paused"]):
            return True
    return False

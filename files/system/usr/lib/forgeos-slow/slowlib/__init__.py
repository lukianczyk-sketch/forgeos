"""ForgeOS Why Is It Slow? (Job 20): shared paths, settings and small helpers.

Everything runs as the person at the PC (no password): it reads /proc and /sys, and the only changes it can
make are the fixes in fixes.py, each one after a Yes in the window. Nothing is sent anywhere.
"""
import json
import os
import re
import subprocess
import time

ENV = os.environ.get
HOME = os.path.expanduser("~")
PROC = ENV("FORGEOS_SLOW_PROC") or "/proc"
SYS = ENV("FORGEOS_SLOW_SYS") or "/sys"
STATE = os.path.join(ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "forgeos", "slow")
HISTORY = os.path.join(STATE, "history.jsonl")
SETTINGS = os.path.join(STATE, "settings.json")
LOG = os.path.join(STATE, "fixes.log")
CONFIG = ENV("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
AUTOSTART = os.path.join(CONFIG, "autostart")
SYS_AUTOSTART = ENV("FORGEOS_SLOW_XDG_AUTOSTART") or "/etc/xdg/autostart"
DOWNLOADS = os.path.join(HOME, "Downloads")
APPDIRS = (ENV("FORGEOS_SLOW_APPDIRS") or os.path.join(HOME, ".local/share/flatpak/exports/share/applications")
           + ":/var/lib/flatpak/exports/share/applications:/usr/share/applications").split(":")
WAIT = float(ENV("FORGEOS_SLOW_WAIT") or "1")
UID = int(ENV("FORGEOS_SLOW_UID") or os.getuid())
GB = 1024 ** 3


def now():
    """The clock (FORGEOS_SLOW_NOW moves it for the tests)."""
    return float(ENV("FORGEOS_SLOW_NOW") or time.time())


def run(cmd, timeout=30):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                           timeout=timeout, env=dict(os.environ, LC_ALL="C"))  # English output to read
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def start(cmd):
    """Start a program and do not wait for it."""
    try:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def read(path, default=""):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return default


def clean(text, most=60):
    """One line, no < > tabs or control characters, at most `most` characters."""
    text = re.sub(r"[<>\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_json(path, data):
    """Write a new file, then rename it, so it is never half written."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".new", "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.replace(path + ".new", path)


def log(text):
    os.makedirs(STATE, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(now())), clean(text, 200)))


def pressure(kind):
    """The kernel's "waiting for" meter (Linux pressure stall info): {'some10':..,'some60':..,'full10':..}."""
    out = {}
    for line in read(os.path.join(PROC, "pressure", kind)).splitlines():
        p = line.split()
        for part in p[1:3] if p else []:
            k, _, v = part.partition("=")
            try:
                out[p[0] + k.replace("avg", "")] = float(v)
            except ValueError:
                pass
    return out


def meminfo():
    """(total bytes, available bytes) from /proc/meminfo; (0, 0) when it can't be read."""
    m = {}
    for line in read(os.path.join(PROC, "meminfo")).splitlines():
        k, _, v = line.partition(":")
        if v.split() and v.split()[0].isdigit():
            m[k] = int(v.split()[0]) * 1024
    return m.get("MemTotal", 0), m.get("MemAvailable", 0)


def size_words(n):
    """Bytes as people say them: 5.1 GB, 300 MB."""
    if n >= GB:
        return ("%.1f GB" % (n / GB)).replace(".0 ", " ")
    return "%d MB" % max(1, round(n / 1024 ** 2))


def game_on():
    """True while a game or a full-screen video is playing (same check as Drive Health and Forge Helper)."""
    code, out = run(["busctl", "--user", "call", "org.freedesktop.PowerManagement.Inhibit",
                     "/org/freedesktop/PowerManagement/Inhibit", "org.freedesktop.PowerManagement.Inhibit",
                     "HasInhibit"], 10)
    if code == 0 and out.strip() == "b true":
        return True
    code, out = run(["gamemoded", "-s"], 10)
    if code == 0 and "is active" in out:
        return True
    return run(["pgrep", "-x", "gamescope"], 10)[0] == 0

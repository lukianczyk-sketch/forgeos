"""ForgeOS Driver & BIOS Autopilot (Job 13d): shared paths, settings, state, the log and small helpers.

Drivers come inside ForgeOS's own system updates (installed by themselves every night). Autopilot tells
you what changed, checks the PC still works after the restart, keeps BIOS and device firmware current
(signed, from the free LVFS) and finds devices with no driver. It never restarts the PC by itself.
"""
import json
import os
import re
import subprocess
import time

HOME = os.path.expanduser("~")
ENV = os.environ.get
CONFIG = ENV("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
STATE = ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
STATE_DIR = os.path.join(STATE, "forgeos", "autopilot")
STATE_FILE = os.path.join(STATE_DIR, "state.json")
LOG = os.path.join(STATE_DIR, "events.log")
SETTINGS = os.path.join(CONFIG, "forgeos", "autopilot.conf")
SYS = ENV("FORGEOS_AP_SYS") or "/sys"
ETC = ENV("FORGEOS_AP_ETC") or "/etc"
SHARE = ENV("FORGEOS_AP_SHARE") or "/usr/share/forgeos/autopilot"
HWDATA = ENV("FORGEOS_AP_HWDATA") or "/usr/share/hwdata"
GUI = ENV("FORGEOS_AP_GUI") or "/usr/bin/forgeos-autopilot-gui"
KEEP_LOG = 300


def run(cmd, timeout=60):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           stdin=subprocess.DEVNULL, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def run_json(cmd, timeout=60):
    """(exit code, parsed JSON or None)."""
    code, out = run(cmd, timeout)
    try:
        return code, json.loads(out) if out.strip() else None
    except ValueError:
        return code, None


def start(cmd):
    """Start a program and do not wait for it."""
    try:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def clean(text, most=120):
    """One line, no < > and no control characters, at most `most` characters."""
    text = re.sub(r"[<>\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def read(path, default=""):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().strip()
    except OSError:
        return default


def sysfs(*parts):
    return read(os.path.join(SYS, *parts))


def private_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def save_json(path, data):
    private_dir(os.path.dirname(path))
    with open(path + ".new", "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.replace(path + ".new", path)


def load_json(path):
    try:
        with open(path) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def state():
    return load_json(STATE_FILE)


def save_state(data):
    save_json(STATE_FILE, data)


def settings():
    """{'devices': 'auto' or 'ask'} - device firmware installs by itself unless set to ask."""
    found = {"devices": "auto"}
    for line in read(SETTINGS).splitlines():
        key, _, value = line.strip().partition("=")
        if key == "devices" and value.strip() in ("auto", "ask"):
            found["devices"] = value.strip()
    return found


def save_settings(found):
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    with open(SETTINGS + ".new", "w") as f:
        f.write("devices=%s\n" % found["devices"])
    os.replace(SETTINGS + ".new", SETTINGS)


def log(kind, text):
    """One line in the Autopilot log (tab-separated, newest last, last 300 kept)."""
    private_dir(STATE_DIR)
    line = "%s\t%s\t%s" % (time.strftime("%Y-%m-%d %H:%M:%S"), kind, clean(text, 300))
    old = read(LOG).splitlines()[-(KEEP_LOG - 1):]
    with open(LOG + ".new", "w") as f:
        f.write("\n".join([x for x in old if x] + [line]) + "\n")
    os.replace(LOG + ".new", LOG)


def log_lines(most=20):
    return [x.split("\t") for x in read(LOG).splitlines() if x.count("\t") == 2][-most:]


def busy():
    """True while a game or a full-screen video is playing (same check as Forge Helper)."""
    code, out = run(["busctl", "--user", "call", "org.freedesktop.PowerManagement.Inhibit",
                     "/org/freedesktop/PowerManagement/Inhibit", "org.freedesktop.PowerManagement.Inhibit",
                     "HasInhibit"], 10)
    if code == 0 and out.strip() == "b true":
        return True
    code, out = run(["gamemoded", "-s"], 10)
    if code == 0 and "is active" in out:
        return True
    return run(["pgrep", "-x", "gamescope"], 10)[0] == 0

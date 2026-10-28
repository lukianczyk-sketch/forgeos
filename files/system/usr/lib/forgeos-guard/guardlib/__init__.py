"""ForgeOS Always-On Guard (Job 13b): shared paths, settings, the warnings log and small helpers.

Three guards that run by themselves: every download is virus-checked, scam and virus websites are
blocked for the whole PC, and every new email is checked by Scam Shield. Nothing leaves this PC.
"""
import os
import re
import subprocess
import time

HOME = os.path.expanduser("~")
ENV = os.environ.get
CONFIG = ENV("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
STATE = ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
DATA = ENV("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
STATE_DIR = os.path.join(STATE, "forgeos", "guard")
EVENTS = os.path.join(STATE_DIR, "events.log")
WHY_DIR = os.path.join(STATE_DIR, "why")
MAIL_STATE = os.path.join(STATE_DIR, "mail.json")
QUAR_DIR = os.path.join(DATA, "forgeos", "guard", "quarantine")
SETTINGS = os.path.join(CONFIG, "forgeos", "guard.conf")
CLAMD_CONF = ENV("FORGEOS_GUARD_CLAMD_CONF") or "/etc/clamd.d/forgeos.conf"
HOSTS_STATUS = ENV("FORGEOS_GUARD_HOSTS_STATUS") or "/var/lib/forgeos-guard/status"
SCAMSHIELD = ENV("FORGEOS_GUARD_SCAMSHIELD") or "/usr/bin/forgeos-scamshield"
GUI = ENV("FORGEOS_GUARD_GUI") or "/usr/bin/forgeos-guard-gui"
BIGGEST = 400 * 1024 * 1024  # bigger files are not virus-checked (ClamAV's own limit is set the same)
GUARDS = ("downloads", "email")
KEEP_EVENTS = 500

# Windows programs, scripts and disk images: not a virus by themselves, but the #1 way scammers get in.
RISKY = {".exe", ".msi", ".bat", ".cmd", ".scr", ".js", ".jse", ".vbs", ".vbe", ".wsf", ".ps1", ".jar",
         ".hta", ".lnk", ".com", ".pif", ".cpl", ".reg", ".iso", ".img", ".vhd", ".appimage"}
MACRO = {".docm", ".xlsm", ".pptm", ".dotm", ".xltm"}
HIDE = {".pdf", ".doc", ".docx", ".xls", ".xlsx", ".jpg", ".jpeg", ".png", ".txt", ".mp3", ".mp4", ".zip"}


def run(cmd, timeout=60, data=None):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, input=data, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           stdin=None if data is not None else subprocess.DEVNULL, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def clean(text, most=120):
    """One line, no < > and no control characters, at most `most` characters (for logs and windows)."""
    text = re.sub(r"[<>\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def risky_name(name):
    """Why a file name is risky ('' = fine): a Windows program/script, a macro file, or a fake double ending."""
    low = name.lower().rstrip(". ")
    parts = low.rsplit(".", 2)
    end = "." + parts[-1] if len(parts) > 1 else ""
    if len(parts) == 3 and "." + parts[1] in HIDE and (end in RISKY or end in MACRO):
        return "fake double ending: it looks like a %s file but it is a program (%s)" % (parts[1].upper(), end)
    if end in RISKY:
        return "a Windows program or script (%s)" % end
    if end in MACRO:
        return "an Office file with macros (%s) - macros can run hidden programs" % end
    return ""


def settings():
    """{'downloads': True, 'email': True} - each guard is on unless turned off in guard.conf."""
    found = {g: True for g in GUARDS}
    try:
        with open(SETTINGS) as f:
            for line in f:
                key, _, value = line.strip().partition("=")
                if key in found:
                    found[key] = value.strip() != "off"
    except OSError:
        pass
    return found


def save_settings(found):
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    with open(SETTINGS + ".new", "w") as f:
        f.write("".join("%s=%s\n" % (g, "on" if found[g] else "off") for g in GUARDS))
    os.replace(SETTINGS + ".new", SETTINGS)


def private_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def log_event(kind, where, who, what, extra="", why=""):
    """Add a line to the warnings log (tab-separated, newest last, last 500 kept). Returns its id."""
    private_dir(STATE_DIR)
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    eid = "%s-%d" % (time.strftime("%Y%m%d%H%M%S"), int(time.time() * 1000) % 1000)
    if why:
        private_dir(WHY_DIR)
        with open(os.path.join(WHY_DIR, eid + ".txt"), "w") as f:
            f.write(why)
    line = "\t".join([stamp, kind, where, clean(who, 200), clean(what, 200), clean(extra, 200), eid])
    try:
        with open(EVENTS) as f:
            old = f.read().splitlines()[-(KEEP_EVENTS - 1):]
    except OSError:
        old = []
    with open(EVENTS + ".new", "w") as f:
        f.write("\n".join(old + [line]) + "\n")
    os.replace(EVENTS + ".new", EVENTS)
    return eid


def events(most=20):
    try:
        with open(EVENTS) as f:
            return [x.split("\t") for x in f.read().splitlines() if x.count("\t") == 6][-most:]
    except OSError:
        return []

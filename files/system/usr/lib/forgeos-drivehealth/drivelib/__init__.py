"""ForgeOS Drive Death Warning (Job 15): shared paths, settings and small helpers.

The daily check runs as root (forgeos-drivehealth.timer) because only root may read a drive's health.
It writes /var/lib/forgeos-drivehealth/report.json (readable by everyone, no serial numbers in it) and a
small history so it can tell when a drive is getting worse. Everything else only reads that report.
"""
import json
import os
import re
import subprocess
import time

ENV = os.environ.get
HOME = os.path.expanduser("~")
VAR = ENV("FORGEOS_DH_VAR") or "/var/lib/forgeos-drivehealth"
REPORT = os.path.join(VAR, "report.json")
HISTORY = os.path.join(VAR, "history.json")
SYS = ENV("FORGEOS_DH_SYS") or "/sys"
CHECKER = ENV("FORGEOS_DH_CHECKER") or "/usr/libexec/forgeos-drivehealth-check"
GUI = ENV("FORGEOS_DH_GUI") or "/usr/bin/forgeos-drivehealth-gui"
FILESYSTEMS = (ENV("FORGEOS_DH_FS") or "/var/home").split(":")
STATE = ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
USER_STATE = os.path.join(STATE, "forgeos", "drivehealth.json")
LEVELS = ("good", "watch", "danger")
DAY = 86400


def now():
    """The clock (FORGEOS_DH_NOW moves it for the tests)."""
    return float(ENV("FORGEOS_DH_NOW") or time.time())


def run(cmd, timeout=120):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           stdin=subprocess.DEVNULL, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def run_json(cmd, timeout=120):
    """(exit code, parsed JSON dict or None)."""
    code, out = run(cmd, timeout)
    try:
        data = json.loads(out) if out.strip() else None
    except ValueError:
        data = None
    return code, data if isinstance(data, dict) else None


def start(cmd):
    """Start a program and do not wait for it."""
    try:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def clean(text, most=80):
    """One line, no < > and no control characters, at most `most` characters."""
    text = re.sub(r"[<>\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_json(path, data, mode=0o644):
    """Write a new file, then rename it, so it is never half written."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def is_root():
    pretend = ENV("FORGEOS_DH_ROOT")  # the tests pretend to be root (1) or not (0)
    return pretend == "1" if pretend in ("0", "1") else os.geteuid() == 0


def worst(levels):
    """The worst of good / watch / danger (unknown counts as good)."""
    return max((x for x in levels if x in LEVELS), key=LEVELS.index, default="good")


def size_words(n):
    """Bytes as people say them on a drive box: 2 TB, 512 GB."""
    if n >= 10 ** 12:
        return ("%.1f TB" % (n / 10 ** 12)).replace(".0 ", " ")
    return "%d GB" % round(n / 10 ** 9)

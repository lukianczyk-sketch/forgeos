"""ForgeOS Ransomware Tripwire (Job 16): shared paths, settings and small helpers.

A root watcher (forgeos-tripwire.service) sees WHICH program finishes writing WHICH file in your folders.
When a program scrambles files fast, leaves a ransom note or touches a bait file, it is frozen (not killed),
the internet is cut and a snapshot is taken. Your own session (forgeos-tripwire-alert.service) then shows
the big window: put my files back, remove the program, or it's mine. Nothing leaves this PC.
"""
import json
import os
import re
import subprocess
import time

ENV = os.environ.get
HOME = os.path.expanduser("~")
VAR = ENV("FORGEOS_TW_VAR") or "/var/lib/forgeos-tripwire"
RUN = ENV("FORGEOS_TW_RUN") or "/run/forgeos-tripwire"
HOMES = ENV("FORGEOS_TW_HOMES") or "/var/home"
MEDIA = ENV("FORGEOS_TW_MEDIA") or "/run/media"
PROC = ENV("FORGEOS_TW_PROC") or "/proc"
CGROUP = ENV("FORGEOS_TW_CGROUP") or "/sys/fs/cgroup"
SNAPS = ENV("FORGEOS_TW_SNAPS") or os.path.join(HOMES, ".snapshots")
TRUSTED = ENV("FORGEOS_TW_TRUSTED") or "/etc/forgeos/tripwire-trusted.list"
HELPER = ENV("FORGEOS_TW_HELPER") or "/usr/libexec/forgeos-tripwire-helper"
RELEASE = ENV("FORGEOS_TW_RELEASE") or "/usr/libexec/forgeos-tripwire-release"
ENGINE = ENV("FORGEOS_TW_ENGINE") or "/usr/bin/forgeos-tripwire"
GUI = ENV("FORGEOS_TW_GUI") or "/usr/bin/forgeos-tripwire-gui"
GUARD_LIB = ENV("FORGEOS_TW_GUARD_LIB") or "/usr/lib/forgeos-guard"
INCIDENTS = os.path.join(VAR, "incidents")
ALLOWED = os.path.join(VAR, "allowed.json")
STATUS = os.path.join(VAR, "status.json")
STATE = os.path.join(ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "forgeos", "tripwire.json")
FOLDERS = ("Documents", "Pictures", "Desktop", "Downloads", "Music", "Videos")
TEST_DIR = "ForgeOS tripwire test"  # in Documents: the pretend attacker of "Test the tripwire"
FAST = (int(ENV("FORGEOS_TW_FAST") or 20), 10)  # 20 scrambled files in 10 seconds
SLOW = (int(ENV("FORGEOS_TW_SLOW") or 150), 600)  # or 150 in 10 minutes (slow attacks)
NOTE_WITH = 5  # a ransom note plus 5 scrambled files in 10 minutes
ID_RX = re.compile(r"^[0-9]{8}-[0-9]{6}-[0-9]{1,9}$")


def now():
    """The clock (FORGEOS_TW_NOW sets it for the tests)."""
    return float(ENV("FORGEOS_TW_NOW") or time.time())


def run(cmd, timeout=60):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           stdin=subprocess.DEVNULL, timeout=timeout)
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


def clean(text, most=120):
    """One line, no < > and no control characters, at most `most` characters."""
    text = re.sub(r"[<>\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def load_json(path, empty=None):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {} if empty is None else empty
    return data if isinstance(data, type({} if empty is None else empty)) else ({} if empty is None else empty)


def save_json(path, data, mode=0o644, owner=None):
    """Write a new file, then rename it, so it is never half written. owner = (uid, gid) or None."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.chmod(tmp, mode)
    if owner and is_root() and ENV("FORGEOS_TW_ROOT") != "1":
        os.chown(tmp, owner[0], owner[1])
    os.replace(tmp, path)


def my_uid():
    """Who you are (FORGEOS_TW_UID pretends to be someone else in the tests)."""
    return int(ENV("FORGEOS_TW_UID") or os.getuid())


def is_root():
    pretend = ENV("FORGEOS_TW_ROOT")  # the tests pretend to be root (1) or not (0)
    return pretend == "1" if pretend in ("0", "1") else os.geteuid() == 0


def stamp(t):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(t))


def say(text):
    """One line for the journal (journalctl -u forgeos-tripwire)."""
    print(clean(text, 400), flush=True)

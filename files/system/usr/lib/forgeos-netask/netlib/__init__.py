"""ForgeOS Ask Before Connecting (Job 24): shared paths and small helpers.

The first time a program tries to use the internet, the PC asks the person at the screen in plain English:
Allow / Block / Just this once. OpenSnitch (the free program firewall) is the engine: it stops each new
connection and asks us. Our service (forgeos-netask.service, root) answers it, shows the question on the
person's own screen, and keeps the answers as OpenSnitch rules. Nothing leaves the PC.
"""
import json
import os
import pwd
import re
import subprocess
import tempfile
import threading
import time

ENV = os.environ.get
TEST = bool(ENV("FORGEOS_NETASK_TEST"))   # the tests run everything as a normal user
PROC = ENV("FORGEOS_NETASK_PROC") or "/proc"
HOST = ENV("FORGEOS_NETASK_ROOT") or ""      # the tests put a pretend /usr and /var/lib/flatpak here
VAR = ENV("FORGEOS_NETASK_VAR") or "/var/lib/forgeos-netask"
UI_SOCK = ENV("FORGEOS_NETASK_SOCK") or "/run/forgeos-netask/osui.sock"          # OpenSnitch talks to us here
REQ_SOCK = ENV("FORGEOS_NETASK_REQ") or "/run/forgeos-netask-req/req.sock"      # the window and helper ask here
RULES = ENV("FORGEOS_NETASK_RULES") or "/etc/opensnitchd/rules"
SHARE = ENV("FORGEOS_NETASK_SHARE") or "/usr/share/forgeos/netask"
TG_SHARE = ENV("FORGEOS_TG_SHARE") or "/usr/share/forgeos/techguard"
HOSTS = ENV("FORGEOS_HOSTS") or "/etc/hosts"
ASK_SECONDS = int(ENV("FORGEOS_NETASK_ASK_SECONDS") or 30)  # no answer in 30 s = blocked for now, asked next time
EXPLAIN_SECONDS = 80   # after "What is this?" more time (OpenSnitch waits at most 120 for an answer)
KEEP_DAYS = 30        # counts and the blocked list are kept on the PC for 30 days
PREFIX = "500-forgeos-netask-"   # every rule this tool writes starts with this (system rules are 000-499)
LOCK = threading.RLock()         # one thread at a time changes the saved answers


def now():
    """The clock (FORGEOS_NETASK_NOW moves it for the tests)."""
    return float(ENV("FORGEOS_NETASK_NOW") or time.time())


def day(t=None):
    return time.strftime("%Y-%m-%d", time.localtime(now() if t is None else t))


def run(cmd, timeout=30, data=None):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, input=data, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           stdin=None if data is not None else subprocess.DEVNULL, timeout=timeout,
                           env=dict(os.environ, LC_ALL="C"))
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def clean(text, most=120):
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


def save_json(path, value, mode=0o600):
    """Write a whole new file, then swap it in (a crash never leaves half a file)."""
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".new-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(value, f, indent=1)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except OSError:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def home_of(uid):
    """A person's home folder (FORGEOS_NETASK_HOME stands in for every home in the tests), or "" if unknown."""
    if ENV("FORGEOS_NETASK_HOME"):
        return ENV("FORGEOS_NETASK_HOME").rstrip("/")
    try:
        return pwd.getpwuid(int(uid)).pw_dir.rstrip("/")
    except (KeyError, ValueError, OverflowError):
        return ""


def ids_of(uid):
    """(uid, gid, user name) of a person, or None."""
    try:
        p = pwd.getpwuid(int(uid))
        return p.pw_uid, p.pw_gid, p.pw_name
    except (KeyError, ValueError, OverflowError):
        return None


def read_lines(path):
    try:
        with open(path, encoding="utf-8") as f:
            return [x.strip() for x in f if x.strip() and not x.lstrip().startswith("#")]
    except OSError:
        return []

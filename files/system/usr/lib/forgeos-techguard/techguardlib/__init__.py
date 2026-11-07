"""ForgeOS Fake Tech Support Guard (Job 17): shared paths, settings and small helpers.

The #1 scam aimed at older people: "Your computer has a virus, call Microsoft", then a stranger on the
phone gets you to install a remote-control app (AnyDesk, TeamViewer...), takes over the PC and opens your
bank. Your session's watcher (forgeos-techguard.service) pauses any remote-control app the moment it starts
and asks you first, locks bank and payment websites while anyone can see the screen, and "Kick them out"
(Ctrl+Alt+K) throws everyone out at once. Nothing leaves this PC.
"""
import fcntl
import json
import os
import re
import subprocess
import time

ENV = os.environ.get
HOME = os.path.expanduser("~")
SHARE = ENV("FORGEOS_TG_SHARE") or "/usr/share/forgeos/techguard"
VAR = ENV("FORGEOS_TG_VAR") or "/var/lib/forgeos-techguard"
PROC = ENV("FORGEOS_TG_PROC") or "/proc"
CGROUP = ENV("FORGEOS_TG_CGROUP") or "/sys/fs/cgroup"
HOSTS = ENV("FORGEOS_HOSTS") or "/etc/hosts"
MONEY_HELPER = ENV("FORGEOS_TG_MONEY") or "/usr/libexec/forgeos-techguard-money"
TRUST_HELPER = ENV("FORGEOS_TG_TRUST") or "/usr/libexec/forgeos-techguard-trust"
GUI = ENV("FORGEOS_TG_GUI") or "/usr/bin/forgeos-techguard-gui"
GUARD_LIB = ENV("FORGEOS_TG_GUARD_LIB") or "/usr/lib/forgeos-guard"
STATE_DIR = os.path.join(ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "forgeos", "techguard")
STATE = os.path.join(STATE_DIR, "state.json")
FAMILY = os.path.join(ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "forgeos", "family")
TRUSTED = os.path.join(VAR, "trusted.json")
TEST_DIR = "forgeos-techguard-test"  # the pretend remote app of "Test the guard" lives in a folder with this name
CALL_TIMER = "forgeos-family-call-end.timer"  # Family Mode's Call for help is running while this timer waits
QUIET_AFTER = 10  # bank sites open again 10 seconds after the last screen sharing stopped
ID_RX = re.compile(r"^[0-9]{8}-[0-9]{6}-[0-9]{1,9}$")


def now():
    """The clock (FORGEOS_TG_NOW sets it for the tests)."""
    return float(ENV("FORGEOS_TG_NOW") or time.time())


def run(cmd, timeout=60, stdin=None):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=timeout,
                           input=stdin.encode() if stdin is not None else None,
                           stdin=None if stdin is not None else subprocess.DEVNULL)
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
    """One line, no < > & and no control characters, at most `most` characters (names come from strangers)."""
    text = re.sub(r"[<>&\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def load_json(path, empty=None):
    empty = {} if empty is None else empty
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return empty
    return data if isinstance(data, type(empty)) else empty


def save_json(path, data, mode=0o600):
    """Write a new file, then rename it, so it is never half written."""
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def my_uid():
    """Who you are (FORGEOS_TG_UID pretends to be someone else in the tests)."""
    return int(ENV("FORGEOS_TG_UID") or os.getuid())


def is_root():
    pretend = ENV("FORGEOS_TG_ROOT")  # the tests pretend to be root (1) or not (0)
    return pretend == "1" if pretend in ("0", "1") else os.geteuid() == 0


def stamp(t):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(t))


def new_id():
    t = now()
    return "%s-%d" % (time.strftime("%Y%m%d-%H%M%S", time.localtime(t)), int(t * 1000) % 1000000 + os.getpid() % 1000)


def read_state():
    return load_json(STATE)


def write_state(st):
    save_json(STATE, st, 0o600)


class Locked:
    """'with Locked() as st:' - read the state, change it, and it is saved at the end. The watcher and the
    window never write it at the same moment (a lock file)."""

    def __enter__(self):
        os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
        self.fd = os.open(STATE + ".lock", os.O_WRONLY | os.O_CREAT, 0o600)
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        self.st = read_state()
        return self.st

    def __exit__(self, kind, *_rest):
        try:
            if kind is None:
                write_state(self.st)
        finally:
            fcntl.flock(self.fd, fcntl.LOCK_UN)
            os.close(self.fd)
        return False

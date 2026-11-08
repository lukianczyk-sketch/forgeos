"""ForgeOS Digital Will (Job 18): shared paths, settings and small helpers.

If something happens to you, the people you picked can get into this PC, your accounts and your photos.
You answer a few questions once; ForgeOS makes one locked "Emergency Envelope" (a 7-Zip file, AES-256)
on a USB stick and in Documents, plus a printed letter that says how to open it. Nothing goes to the
cloud. Your answers are kept without any passwords; passwords only ever go inside the locked envelope.
"""
import html
import json
import os
import pwd
import re
import subprocess
import time

ENV = os.environ.get
HOME = os.path.expanduser("~")
SHARE = ENV("FORGEOS_WILL_SHARE") or "/usr/share/forgeos/digitalwill"
VAR = ENV("FORGEOS_WILL_VAR") or "/var/lib/forgeos-digitalwill"
MEDIA = ENV("FORGEOS_WILL_MEDIA") or "/run/media"
UNLOCK_HELPER = ENV("FORGEOS_WILL_UNLOCK") or "/usr/libexec/forgeos-digitalwill-unlock"
CHKPWD = ENV("FORGEOS_WILL_CHKPWD") or "/usr/sbin/unix_chkpwd"
SEVEN = ENV("FORGEOS_WILL_7Z") or "7z"
CRYPTSETUP = ENV("FORGEOS_WILL_CRYPTSETUP") or "cryptsetup"
GUI = ENV("FORGEOS_WILL_GUI") or "/usr/bin/forgeos-digitalwill-gui"
DATA = os.path.join(ENV("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share"), "forgeos", "will")
STATE_DIR = os.path.join(ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "forgeos", "will")
DRAFT = os.path.join(DATA, "draft.json")
STATE = os.path.join(STATE_DIR, "state.json")
# Work space in memory (tmpfs): the envelope's unlocked pages are put together here, never on the drive.
SCRATCH = os.path.join(ENV("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid(), "forgeos-digitalwill")
DOCS = os.path.join(HOME, "Documents")
FOLDER = "ForgeOS Emergency Envelope"
NAME_RX = re.compile(r"^Emergency-Envelope-[0-9]{4}-[0-9]{2}-[0-9]{2}(-[0-9]{1,3})?\.7z$")
DAY = 86400
OLD_AFTER = 182 * DAY  # "your Digital Will is 6 months old - update it?"
CODE_WORDS = 10        # the opening code: 10 words (two halves of 5 for the two-key lock)
KEY_WORDS = 8          # the PC unlock code typed when the PC starts: 8 words


def now():
    """The clock (FORGEOS_WILL_NOW sets it for the tests)."""
    return float(ENV("FORGEOS_WILL_NOW") or time.time())


def run(cmd, timeout=60, stdin=None, cwd=None):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, cwd=cwd,
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
    """One line, no control characters or TABs, at most `most` characters."""
    text = re.sub(r"[\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def esc(text):
    """Safe to put on a web page (the envelope's pages are HTML)."""
    return html.escape(str(text), quote=True)


def load_json(path, empty=None):
    empty = {} if empty is None else empty
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return empty
    return data if isinstance(data, type(empty)) else empty


def save_json(path, data, mode=0o600):
    """Write a new file, then rename it, so it is never half written. Only you can read it."""
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def write_private(path, text, mode=0o600):
    """A new file only you can read (never follows a link someone left there)."""
    if os.path.lexists(path):
        os.unlink(path)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)


def user():
    return ENV("FORGEOS_WILL_USER") or pwd.getpwuid(os.getuid()).pw_name


def full_name():
    try:
        gecos = pwd.getpwuid(os.getuid()).pw_gecos.split(",")[0].strip()
    except KeyError:
        gecos = ""
    return clean(ENV("FORGEOS_WILL_FULLNAME") or gecos or user(), 60)


def is_root():
    pretend = ENV("FORGEOS_WILL_ROOT")  # the tests pretend to be root (1) or not (0)
    return pretend == "1" if pretend in ("0", "1") else os.geteuid() == 0


def day(t):
    return time.strftime("%Y-%m-%d", time.localtime(t))


def nice_day(t):
    return time.strftime("%B %d, %Y", time.localtime(t)).replace(" 0", " ")


def read_state():
    return load_json(STATE)


def write_state(st):
    save_json(STATE, st, 0o600)

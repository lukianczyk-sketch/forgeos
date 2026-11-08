"""ForgeOS Find My PC (Job 19): shared paths, settings and small helpers.

If your PC is lost or stolen, your phone can see where it is, make it ring, show a "please return" message
and lock it - with no company account. Normal days the PC only checks for a message from your phone and
sends nothing. Everything between the PC and your phone is locked (AES-256-GCM) with a key only they know;
the free relay in the middle (ntfy.sh) sees scrambled text only.
"""
import json
import os
import pwd
import re
import subprocess
import time

ENV = os.environ.get
SHARE = ENV("FORGEOS_LOC_SHARE") or "/usr/share/forgeos/locate"
VAR = ENV("FORGEOS_LOC_VAR") or "/var/lib/forgeos-locate"
RUN = ENV("FORGEOS_LOC_RUN") or "/run/forgeos-locate"
ROOT_HELPER = ENV("FORGEOS_LOC_HELPER") or "/usr/libexec/forgeos-locate-root"
MONEY = ENV("FORGEOS_LOC_MONEY") or "/usr/bin/forgeos-techguard"
KEYFILE = os.path.join(VAR, "key.json")      # root only (600): the secret key
STATE = os.path.join(VAR, "state.json")      # root only (600): lost mode, last command, timers
TRAIL = os.path.join(VAR, "trail.json")      # root only (600): the reports sent while lost (wiped on Found)
STATUS = os.path.join(VAR, "status.json")    # everyone may read (644): no secrets, for the window
ALERT = os.path.join(RUN, "alert.json")      # everyone may read (644): ring / message / lost for your session
POKE = ENV("FORGEOS_LOC_POKE") or "/run/user/*/forgeos-locate-poke"  # the window's "check now" (Test it)
HOSTS = ENV("FORGEOS_LOC_HOSTS") or "/etc/hosts"
HOME = os.path.expanduser("~")
MY_STATE = os.path.join(ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "forgeos", "locate.json")
MINUTE = 60
NORMAL_EVERY = 10 * MINUTE   # normal days: look for a message from your phone every 10 minutes
FAST_EVERY = 15              # for 15 minutes after setup or a command: every 15 seconds
FAST_FOR = 15 * MINUTE
LOST_EVERY = MINUTE          # lost: look every minute
REPORT_FIRST = 10 * MINUTE   # lost: a report every 10 minutes for the first 2 hours...
REPORT_LATER = 20 * MINUTE   # ...then every 20 minutes (keeps well inside the free relay's limits)
PHOTO_EVERY = 3 * 3600       # lost + photo on: a webcam photo at the start, then every 3 hours
RING_FOR = 120               # Ring: 2 minutes
BACKOFF = 30 * MINUTE        # the relay said "too many": wait 30 minutes
DEFAULTS = {"relay": "https://ntfy.sh", "page": "https://lukianczyk-sketch.github.io/forgeos/find/",
            "geo": "https://api.beacondb.net/v1/geolocate", "ip": "https://ipinfo.io/json"}


def now():
    """The clock (FORGEOS_LOC_NOW sets it for the tests)."""
    return float(ENV("FORGEOS_LOC_NOW") or time.time())


def settings():
    """Where the relay, the phone page and the location services are (settings.json can point elsewhere,
    for example your own ntfy server). FORGEOS_LOC_RELAY / _PAGE / _GEO / _IP override it (tests)."""
    s = dict(DEFAULTS)
    s.update({k: v for k, v in load_json(os.path.join(SHARE, "settings.json")).items()
              if k in DEFAULTS and isinstance(v, str) and v.startswith("https://")})
    for k in DEFAULTS:
        s[k] = ENV("FORGEOS_LOC_" + k.upper()) or s[k]
    return s


def run(cmd, timeout=60, stdin=None):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout,
                           input=stdin.encode() if stdin is not None else None,
                           stdin=None if stdin is not None else subprocess.DEVNULL)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def start(cmd):
    """Start a program and do not wait for it. Returns it (or None)."""
    try:
        return subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return None


def clean(text, most=120):
    """One line, no control characters, TABs or broken (half) emoji, at most `most` characters."""
    text = re.sub(r"[\ud800-\udfff]", "", re.sub(r"[\x00-\x1f\x7f]", " ", str(text)))
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
    os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
    tmp = path + ".new"
    if os.path.lexists(tmp):
        os.unlink(tmp)
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def remove(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def is_root():
    pretend = ENV("FORGEOS_LOC_ROOT")  # the tests pretend to be root (1) or not (0)
    return pretend == "1" if pretend in ("0", "1") else os.geteuid() == 0


def hhmm(t):
    return time.strftime("%I:%M %p", time.localtime(t)).lstrip("0")


def when(t):
    return time.strftime("%b %d, ", time.localtime(t)) + hhmm(t)


def me():
    try:
        return pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        return str(os.getuid())

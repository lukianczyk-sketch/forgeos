"""ForgeOS Moving Day (Job 14): shared paths, settings and small helpers.

Moving Day brings your files, bookmarks, saved passwords and a list of your programs over from Windows
(the Windows drive on this PC, an old PC's drive, or a "Moving Box" USB stick). The Windows side is only
ever READ: it is opened read-only and nothing on it is changed or deleted.
"""
import os
import re
import subprocess

HOME = os.path.expanduser("~")
ENV = os.environ.get
STATE = ENV("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
STATE_DIR = os.path.join(STATE, "forgeos", "movingday")
SHARE = ENV("FORGEOS_MD_SHARE") or "/usr/share/forgeos/movingday"
MOUNT = ENV("FORGEOS_MD_MOUNT") or "/usr/libexec/forgeos-movingday-mount"
WIR_LISTS = ENV("FORGEOS_WIR_LISTS") or "/usr/share/forgeos/willitrun"
BRAVE = ENV("FORGEOS_MD_BRAVE") or os.path.join(HOME, ".var", "app", "com.brave.Browser", "config",
                                                 "BraveSoftware", "Brave-Browser")
PASS_DIR = os.path.join(HOME, "Moving Day passwords")
BOX = "ForgeOS Moving Box"
FOLDERS = ("Documents", "Pictures", "Music", "Videos", "Desktop", "Downloads")
NOT_USERS = {"public", "default", "default user", "all users", "defaultuser0", "wdagutilityaccount"}
MARGIN = 1 << 30  # always leave 1 GB free


def run(cmd, timeout=60, stdin=None):
    """Run a program; return (exit code, output). Missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, input=stdin.encode() if stdin is not None else None,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           stdin=None if stdin is not None else subprocess.DEVNULL, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def clean(text, most=120):
    """One line, no < > and no control characters, at most `most` characters."""
    text = re.sub(r"[<>\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r" +", " ", text).strip()[:most]


def norm(text):
    """Lower-case letters and digits with single spaces (the same as Will It Run?'s norm)."""
    return re.sub(r"[^a-z0-9]+", " ", str(text).lower()).strip()


def gb(n):
    """Bytes in plain words: 1.4 GB, 230 MB, 12 KB."""
    for unit, size in (("GB", 1 << 30), ("MB", 1 << 20), ("KB", 1 << 10)):
        if n >= size:
            v = n / size
            return ("%.1f %s" % (v, unit)).replace(".0 ", " ") if v < 10 else "%d %s" % (round(v), unit)
    return "%d bytes" % n


def child(folder, name):
    """The entry in `folder` whose name matches `name` in any case (Windows ignores case), or None."""
    try:
        for entry in os.listdir(folder):
            if entry.lower() == name.lower():
                return os.path.join(folder, entry)
    except OSError:
        pass
    return None


def path_in(folder, *parts):
    """Follow parts down from folder, any case. None when one is missing."""
    for part in parts:
        folder = child(folder, part) if folder else None
    return folder


def state_dir():
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    return STATE_DIR

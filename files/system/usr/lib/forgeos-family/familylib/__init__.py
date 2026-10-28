"""ForgeOS Family Mode (Job 13): shared paths, the saved-settings file and small helpers.

Family Mode = one switch: big text, every safety guard on, and "Call for help" (RustDesk, locked down).
Everything it changes is written down in saved.json FIRST, so turning it off always puts it all back.
"""
import json
import os
import re
import subprocess

HOME = os.path.expanduser("~")
CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
STATE = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
STATE_DIR = os.path.join(STATE, "forgeos", "family")
SAVED = os.path.join(STATE_DIR, "saved.json")
CONF = os.path.join(CONFIG, "forgeos", "family.conf")
RUSTDESK = "com.rustdesk.RustDesk"
RUSTDESK_DIR = os.environ.get("FORGEOS_FAMILY_RUSTDESK_DIR") or os.path.join(
    HOME, ".var", "app", RUSTDESK, "config", "rustdesk")
APPS = os.environ.get("FORGEOS_FAMILY_APPS") or "/usr/share/applications"
SELF = os.environ.get("FORGEOS_FAMILY_SELF") or "/usr/bin/forgeos-family"

# Big / Bigger: how much bigger the words get, the mouse pointer size, the taskbar height.
SIZES = {"big": (1.4, 48, 56), "bigger": (1.8, 64, 68)}


def run(cmd, timeout=20):
    """Run a program; return (exit code, output). A missing program or a hang = (127, "")."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           stdin=subprocess.DEVNULL, timeout=timeout, text=True)
        return p.returncode, p.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def clean(text, most=60):
    """Text a person typed: one line, no < >, no control characters, at most `most` characters."""
    text = re.sub(r"[<>\x00-\x1f\x7f]", " ", str(text))
    return re.sub(r"\s+", " ", text).strip()[:most]


def write_private(path, text):
    """Write a file only this user can read (folder 0700, file 0600), all at once."""
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def load_saved():
    try:
        with open(SAVED) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def store_saved(data):
    write_private(SAVED, json.dumps(data, indent=1, sort_keys=True) + "\n")


def forget_saved():
    try:
        os.remove(SAVED)
    except OSError:
        pass

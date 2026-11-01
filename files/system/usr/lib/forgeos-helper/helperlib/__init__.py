"""ForgeOS Forge Helper (Job 13c): one private AI helper for the whole PC.

Shared paths and small helpers. Nothing here leaves the computer.
"""
import json
import os
import subprocess

HOME = os.path.expanduser("~")
SHARE = os.environ.get("FORGEOS_HELPER_SHARE") or "/usr/share/forgeos/helper"


def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
    return os.path.join(base, "forgeos")


def data_dir():
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
    return os.path.join(base, "forgeos", "helper")


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
    return os.path.join(base, "forgeos")


def private_dir(path):
    """Make a folder only this user can open."""
    os.makedirs(path, mode=0o700, exist_ok=True)
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass
    return path


def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, value):
    """Write a file only this user can read (a new file, then renamed, so it is never half written)."""
    private_dir(os.path.dirname(path))
    tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(value, f, indent=1)
    os.replace(tmp, path)


def append_line(path, text):
    private_dir(os.path.dirname(path))
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, "a", encoding="utf-8") as f:
        f.write(text.rstrip("\n") + "\n")


def read_lines(path):
    try:
        with open(path, encoding="utf-8") as f:
            return [x.strip() for x in f if x.strip()]
    except OSError:
        return []


def run(cmd, timeout, stdin=None):
    """Run a ForgeOS tool (a list of words, never a shell). Returns (exit code, output)."""
    try:
        p = subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=timeout,
                           errors="replace")
    except (OSError, subprocess.TimeoutExpired):
        return 127, ""
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def clean(text, limit=2000):
    """Printable text only, at most LIMIT characters."""
    text = "".join(c if c.isprintable() or c in "\n\t" else " " for c in str(text))
    return text[:limit].strip()

"""ForgeOS GhostFinder (Job 12): see who's watching. Finds hidden cameras and trackers.

Everything stays on this PC: no internet, no account, no root.
"""
import os
import subprocess
import time


def env(name, default=""):
    return os.environ.get(name) or default


def now():
    """Seconds since 1970 (tests can set FORGEOS_GHOST_NOW)."""
    return float(env("FORGEOS_GHOST_NOW") or time.time())


def home(*parts):
    return os.path.join(os.path.expanduser("~"), *parts)


def data_dir():
    """~/.local/share/forgeos/ghost (only this user can read it)."""
    base = env("XDG_DATA_HOME", home(".local", "share"))
    path = os.path.join(base, "forgeos", "ghost")
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def safe_file():
    base = env("XDG_CONFIG_HOME", home(".config"))
    os.makedirs(os.path.join(base, "forgeos"), exist_ok=True)
    return os.path.join(base, "forgeos", "ghost-safe.txt")


def report_file():
    return env("FORGEOS_GHOST_REPORT", home("Documents", "GhostFinder", "GhostFinder report.txt"))


def run(cmd, timeout=15):
    """Run a command; return what it printed ("" if it is missing or fails)."""
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, errors="replace")
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout if out.returncode == 0 else ""

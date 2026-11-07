"""Which programs are remote-control apps (the list in /usr/share/forgeos/techguard/remote-apps.txt).

A name is made simple first: lower case, spaces become "_", and only the last part of a path counts
(Linux "/" or Windows "\\"), so "C:\\Program Files\\AnyDesk\\AnyDesk.exe" and "com.anydesk.Anydesk"
are both found.
"""
import os
import re

from . import SHARE

ENDINGS = (".exe", ".msi", ".appimage", ".deb", ".rpm", ".flatpakref", ".tar.gz", ".tar.xz", ".tar.bz2", ".tgz",
           ".zip", ".run", ".sh", ".bin", ".dmg", ".pkg", ".7z")
_CACHE = {}


def load():
    """[(id, name, compiled pattern)] from the list (bad lines are skipped)."""
    path = os.path.join(SHARE, "remote-apps.txt")
    if path in _CACHE:
        return _CACHE[path]
    found = []
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        lines = []
    for line in lines:
        parts = [p.strip() for p in line.split("~")]
        if line.startswith("#") or len(parts) != 3 or not all(parts):
            continue
        try:
            found.append((parts[0], parts[1], re.compile(parts[2])))
        except re.error:
            continue
    _CACHE[path] = found
    return found


def simple(name):
    name = re.split(r"[/\\]", str(name).strip().strip("\"'"))[-1]
    return re.sub(r"\s+", "_", name.lower())


def which(names):
    """(id, name) of the first remote-control app any of these names belongs to, else None."""
    names = [simple(n) for n in names if n]
    for app_id, title, rx in load():
        if any(n and rx.search(n) for n in names):
            return app_id, title
    return None


def installer(filename):
    """(id, name) when a downloaded file is a remote-control app's installer or program, else None."""
    low = filename.lower()
    if not low.endswith(ENDINGS) or low.endswith((".crdownload", ".part")):
        return None
    return which([filename])

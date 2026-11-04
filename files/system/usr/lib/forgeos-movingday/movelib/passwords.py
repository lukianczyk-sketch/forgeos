"""Saved passwords. Windows locks the browsers' saved passwords to the Windows account, so they come over
the safe way: exported in Windows (the Moving Box does it with you), imported into Brave, then erased.

The export files are never copied with your other files. Moving Day puts them in one private folder
(~/Moving Day passwords, only you can open it) and erases them when you are done, or after 24 hours.
"""
import csv
import os
import re
import time

from . import PASS_DIR, run, state_dir

NAME = re.compile(r"(password|passwords|logins)[^/]*\.csv$", re.I)
BRAVE_PAGE = "brave://password-manager/settings"
ERASE_UNIT = "forgeos-movingday-erase"


def is_password_file(path, look=True, box=False):
    """A browser's password export: a .csv named like one (any .csv in the Moving Box) with a password column."""
    name = os.path.basename(path)
    if not name.lower().endswith(".csv") or not (box or NAME.search(name)):
        return False
    if not look:
        return True
    try:
        with open(path, encoding="utf-8-sig", errors="replace") as f:
            head = f.readline().lower()
    except OSError:
        return False
    return "password" in head and any(w in head for w in ("url", "origin", "website", "hostname"))


def count(path):
    try:
        with open(path, encoding="utf-8-sig", errors="replace", newline="") as f:
            return max(0, sum(1 for row in csv.reader(f) if row) - 1)
    except (OSError, csv.Error):
        return 0


def staged():
    try:
        return sorted(os.path.join(PASS_DIR, f) for f in os.listdir(PASS_DIR) if f.lower().endswith(".csv"))
    except OSError:
        return []


def stage(paths):
    """Copy the export files into the private folder. Returns (files, passwords)."""
    os.makedirs(PASS_DIR, mode=0o700, exist_ok=True)
    os.chmod(PASS_DIR, 0o700)
    n = rows = 0
    seen = set()
    for src in paths:
        dest = os.path.join(PASS_DIR, "%d %s" % (n + 1, os.path.basename(src)))
        try:
            with open(src, "rb") as a:
                data = a.read()
            if data in seen:
                continue  # the same export twice (in the Moving Box and in Downloads)
            seen.add(data)
            fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as b:
                b.write(data)
            os.chmod(dest, 0o600)
        except OSError:
            continue
        n, rows = n + 1, rows + count(dest)
    if n:
        with open(os.path.join(state_dir(), "passwords-staged"), "w", encoding="utf-8") as f:
            f.write("%d\n" % time.time())
        run(["systemd-run", "--user", "--on-active=24h", "--unit=" + ERASE_UNIT, "--collect",
             "forgeos-movingday", "passwords-done"], 20)
    return n, rows


def shred(path):
    """Write zeros over the file, then delete it."""
    try:
        size = os.path.getsize(path)
        with open(path, "r+b") as f:
            f.write(b"\0" * size)
            f.flush()
            os.fsync(f.fileno())
        os.unlink(path)
        return True
    except OSError:
        return False


def erase():
    """Erase the private copies. Returns how many files were erased."""
    gone = sum(1 for p in staged() if shred(p))
    try:
        os.rmdir(PASS_DIR)
    except OSError:
        pass
    try:
        os.unlink(os.path.join(state_dir(), "passwords-staged"))
    except OSError:
        pass
    run(["systemctl", "--user", "stop", ERASE_UNIT + ".timer"], 20)
    return gone


def erase_source(paths):
    """Also erase the export files where they came from (works on a Moving Box stick, never on Windows)."""
    return sum(1 for p in paths if shred(p))


def how_to(rows):
    return ("%d saved passwords are ready to go into Brave.\n\n"
            "1. Open Brave.\n"
            "2. Click the address bar at the top, press Ctrl+V (the address is copied for you) and press Enter.\n"
            "3. Next to \"Import passwords\" click \"Select file\".\n"
            "4. Open the folder \"Moving Day passwords\" in your Home folder and pick the file.\n"
            "5. Come back here and click \"Done\" so Moving Day erases the file.\n\n"
            "If you forget, Moving Day erases it by itself after 24 hours." % rows)

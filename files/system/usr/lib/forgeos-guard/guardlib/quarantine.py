"""Locked-away files: a file with a virus is moved here and locked (chmod 000). Never deleted silently.

quarantine.log lines (tab-separated): date, original path, sha256, virus name, locked-away path.
ID = the locked-away path without the quarantine folder in front.
"""
import hashlib
import os
import shutil
import time

from . import QUAR_DIR, clean, private_dir

LOG = os.path.join(QUAR_DIR, "quarantine.log")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def lock_away(path, virus):
    """Move the file into quarantine and lock it. Returns the ID, or '' if it could not be moved."""
    try:
        digest = sha256(path)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        n = 0
        while os.path.exists(os.path.join(QUAR_DIR, "%s-%d" % (stamp, n))):
            n += 1
        folder = private_dir(os.path.join(private_dir(QUAR_DIR), "%s-%d" % (stamp, n)))
        name = os.path.basename(path).replace("\t", " ").replace("\n", " ") or "file"
        moved = os.path.join(folder, name)
        shutil.move(path, moved)
        os.chmod(moved, 0)
    except OSError:
        return ""
    with open(LOG, "a") as f:
        f.write("\t".join([time.strftime("%Y-%m-%d %H:%M:%S"), path.replace("\t", " ").replace("\n", " "),
                           digest, clean(virus, 100), moved]) + "\n")
    return os.path.relpath(moved, QUAR_DIR)


def entries():
    """[(id, date, original, virus)] for files still locked away."""
    found = []
    try:
        with open(LOG) as f:
            lines = f.read().splitlines()
    except OSError:
        return found
    for line in lines:
        part = line.split("\t")
        if len(part) == 5 and os.path.lexists(part[4]):
            found.append((os.path.relpath(part[4], QUAR_DIR), part[0], part[1], part[3]))
    return found


def find(qid):
    for item in entries():
        if item[0] == qid:
            return item
    return None


def restore(qid):
    """Put a locked-away file back (unlocked). Returns where it went, or '' if not found."""
    item = find(qid)
    if not item:
        return ""
    moved = os.path.join(QUAR_DIR, qid)
    target = item[2]
    base, dot, end = target.rpartition(".")
    if not dot or "/" in end:
        base, end = target, ""
    n = 1
    while os.path.lexists(target):
        target = "%s (restored %d)%s" % (base, n, "." + end if end else "")
        n += 1
    try:
        os.chmod(moved, 0o600)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.move(moved, target)
    except OSError:
        return ""
    try:
        os.rmdir(os.path.dirname(moved))
    except OSError:
        pass
    return target


def delete(qid):
    """Delete a locked-away file for good. True if it is gone."""
    if not find(qid):
        return False
    moved = os.path.join(QUAR_DIR, qid)
    try:
        os.chmod(moved, 0o600)
        os.remove(moved)
        os.rmdir(os.path.dirname(moved))
    except OSError:
        pass
    return not os.path.lexists(moved)

"""Put my files back. Runs as YOU (never as root), while the program stays frozen.

Every file the program touched comes back from the newest Undo Button snapshot taken BEFORE the
attack started (and only a copy that does not look scrambled itself). Files it deleted after making a
scrambled copy come back too. The scrambled copies go to Always-On Guard's locked folder, not deleted.
Files on USB drives or the Windows drive can't come back: there are no snapshots there.
"""
import calendar
import filecmp
import os
import re
import shutil
import sys
import time

from . import GUARD_LIB, HOMES, SNAPS, bait, scramble

KNOWN = set(scramble.MAGIC) | {".txt", ".csv", ".md", ".rtf", ".odg", ".xml", ".json", ".html", ".htm"}


def snapshots(before):
    """[(number, time)] of Undo Button snapshots taken before `before`, newest first."""
    found = []
    try:
        names = os.listdir(SNAPS)
    except OSError:
        return found
    for n in names:
        try:
            with open(os.path.join(SNAPS, n, "info.xml")) as f:
                m = re.search(r"<date>(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)</date>", f.read())
        except OSError:
            continue
        if n.isdigit() and m and os.path.isdir(os.path.join(SNAPS, n, "snapshot")):
            t = calendar.timegm(time.strptime(m.group(1), "%Y-%m-%d %H:%M:%S"))  # snapper writes UTC
            if t < before:
                found.append((int(n), t))
    return sorted(found, reverse=True)


def good_copy(rel, snaps):
    """The newest snapshot copy of this file that is not scrambled: (path, time) or ('', 0)."""
    for n, t in snaps:
        c = os.path.join(SNAPS, str(n), "snapshot", rel)
        if os.path.isfile(c) and not os.path.islink(c) and scramble.judge(c, scramble.read_head(c)) != "scrambled":
            return c, t
    return "", 0


def lock_away(path, program):
    """Into Always-On Guard's locked folder (it lists them; you can still delete or put them back)."""
    sys.path.insert(0, GUARD_LIB)
    try:
        from guardlib import quarantine
        return bool(quarantine.lock_away(path, "Scrambled by %s (Ransomware Tripwire)" % program))
    except (ImportError, OSError):
        return False
    finally:
        sys.path.remove(GUARD_LIB)


def copy_back(src, dst):
    try:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.lexists(dst):
            base, end = os.path.splitext(dst)
            dst = base + " (put back)" + end
        shutil.copy2(src, dst, follow_symlinks=False)
        return dst
    except OSError:
        return ""


def put_back(inc):
    """{'back': [...], 'locked': [...], 'lost': [...], 'usb': [...], 'snapshot': (n, time) or None}."""
    snaps = snapshots(inc.get("start") or inc.get("time") or 0)
    res = {"back": [], "locked": [], "lost": [], "usb": [], "snapshot": snaps[0] if snaps else None}
    if not snaps:
        return res  # nothing to put back from: leave every file where it is
    home = inc.get("home") or os.path.expanduser("~")
    new_in = set()
    for p in inc.get("files", []):
        rel = os.path.relpath(p, HOMES)
        if not (p + "/").startswith(home.rstrip("/") + "/"):
            res["usb"].append(p)
            continue
        if bait.is_bait(p):
            continue  # the tripwire puts its safety files back by itself
        old, _t = good_copy(rel, snaps)
        if os.path.lexists(p):
            if old and os.path.isfile(p) and filecmp.cmp(old, p, shallow=False):
                continue
            if lock_away(p, inc.get("program", "?")):
                res["locked"].append(p)
            else:
                continue  # never write over a file we could not move away
        if old:
            res["back"].append(copy_back(old, p))
        else:
            new_in.add(os.path.dirname(rel))
    for d in sorted(new_in):  # it made scrambled copies here: bring back the originals it deleted
        old_dir = good_copy_dir(d, snaps)
        for name in sorted(os.listdir(old_dir)) if old_dir else []:
            src, dst = os.path.join(old_dir, name), os.path.join(HOMES, d, name)
            if name.startswith(".") or bait.is_bait(dst) or not os.path.isfile(src) or os.path.lexists(dst):
                continue
            if scramble.judge(src, scramble.read_head(src)) != "scrambled" and copy_back(src, dst):
                res["back"].append(dst)
    back = [b for b in res["back"] if b]
    res["back"] = back
    # Lost = one of YOUR files (a normal ending like .docx) scrambled where it was, made after the last
    # snapshot. Copies with odd endings (.locked) or ransom notes are the program's own leftovers.
    res["lost"] = [x for x in res["locked"] if x not in back and not any(x.startswith(b) for b in back)
                   and scramble.ending(os.path.basename(x)) in KNOWN and not scramble.is_note(os.path.basename(x))]
    return res


def good_copy_dir(rel, snaps):
    for n, _t in snaps:
        d = os.path.join(SNAPS, str(n), "snapshot", rel)
        if os.path.isdir(d) and not os.path.islink(d):
            return d
    return ""

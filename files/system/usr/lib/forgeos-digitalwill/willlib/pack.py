"""Make the Emergency Envelope: one locked 7-Zip file (AES-256, even the file names are hidden).

The unlocked pages are put together in memory (tmpfs) and 7-Zip reads your folders and password safe
straight from where they are, so nothing unlocked is ever written to the drive (or to Undo's copies).
The envelope goes to Documents/ForgeOS Emergency Envelope and, when picked, a USB stick; older
envelopes there are removed (they hold old passwords). Returns (envelope path or None, message).
"""
import os
import shutil

from . import (DOCS, FOLDER, NAME_RX, SCRATCH, SEVEN, day, draft, now, read_state, run, write_private,
               write_state)
from . import pages


def size_of(folders):
    total = 0
    for top in folders:
        for root, _dirs, files in os.walk(top):
            for f in files:
                try:
                    total += os.lstat(os.path.join(root, f)).st_size
                except OSError:
                    pass
    return total


def free(path):
    try:
        s = os.statvfs(path)
    except OSError:
        return 0
    return s.f_bavail * s.f_frsize


def stage(d, sec, unlock, made, work):
    """The envelope's inside, in memory: pages and letters; links to the password safe and folders."""
    os.makedirs(work, mode=0o700)
    write_private(os.path.join(work, "Open me first.html"), pages.inside(d, sec, unlock, made))
    if d["letters"]:
        os.mkdir(os.path.join(work, "Letters"), 0o700)
        for name, text in d["letters"].items():
            safe = "".join(c if c.isalnum() or c in " -" else "_" for c in name).strip() or "letter"
            write_private(os.path.join(work, "Letters", "For %s.txt" % safe), text + "\n")
    if d["safe"] and os.path.isfile(d["safe"]):
        os.mkdir(os.path.join(work, "Password safe"), 0o700)
        os.symlink(d["safe"], os.path.join(work, "Password safe", os.path.basename(d["safe"])))
    if d["folders"]:
        os.mkdir(os.path.join(work, "Kept folders"), 0o700)
        used = set()
        for folder in d["folders"]:
            name, n = os.path.basename(folder), 2
            while name in used:
                name, n = "%s (%d)" % (os.path.basename(folder), n), n + 1
            used.add(name)
            os.symlink(folder, os.path.join(work, "Kept folders", name))


def test(path, code):
    """True when the envelope opens with this code and every file in it is whole."""
    rc, _out = run([SEVEN, "t", "-y", "--", path], 4 * 3600, stdin=code + "\n")
    return rc == 0


def new_name(dest, made):
    base = "Emergency-Envelope-%s" % day(made)
    name, n = base + ".7z", 2
    while os.path.exists(os.path.join(dest, name)):
        name, n = "%s-%d.7z" % (base, n), n + 1
    return name


def tidy_old(dest, keep):
    for f in os.listdir(dest):
        if NAME_RX.match(f) and f != keep:
            try:
                os.unlink(os.path.join(dest, f))
            except OSError:
                pass


def make(code, sec, holders, usb="", unlock=""):
    d, made = draft.load(), now()
    dests = [os.path.join(DOCS, FOLDER)] + ([os.path.join(usb, FOLDER)] if usb else [])
    need = size_of(d["folders"]) + (os.path.getsize(d["safe"]) if os.path.isfile(d["safe"]) else 0) + 20 * 2 ** 20
    for dest in dests:
        os.makedirs(dest, mode=0o700, exist_ok=True)
        if free(dest) < need:
            return None, "Not enough room in %s: the envelope needs about %d MB." % (dest, need // 2 ** 20 + 1)
    work = os.path.join(SCRATCH, "pack-%d" % os.getpid())
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(SCRATCH, mode=0o700, exist_ok=True)
    first = os.path.join(dests[0], ".making-envelope.7z")
    rc, out = 1, "could not put the pages together"
    try:
        stage(d, sec, unlock, made, work)
        if os.path.exists(first):
            os.unlink(first)
        rc, out = run([SEVEN, "a", "-t7z", "-mhe=on", "-mx=5", "-p", "-y", "--", first, "."], 6 * 3600,
                      stdin=code + "\n", cwd=work)
    except OSError:
        pass
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if rc != 0 or not test(first, code):
        if os.path.exists(first):
            os.unlink(first)
        last = [x for x in out.splitlines() if x.strip()][-1:] if rc != 127 else ["7-Zip is missing"]
        return None, "The envelope could not be made (%s)." % (last[0] if last else "7-Zip failed")
    name, paths = new_name(dests[0], made), []
    for i, dest in enumerate(dests):
        target = os.path.join(dest, name)
        if i == 0:
            os.replace(first, target)
        else:
            shutil.copyfile(os.path.join(dests[0], name), target + ".part")
            os.replace(target + ".part", target)
        tidy_old(dest, name)
        letter = pages.outside(d, made, name, holders)
        with open(os.path.join(dest, "Letter to my family.html"), "w", encoding="utf-8") as f:
            f.write(letter)
        paths.append(target)
    st = read_state()
    st.update({"made": made, "name": name, "paths": paths, "holders": [list(h) for h in holders],
               "two": len(holders) == 2, "safe": d["safe"], "safe_mtime": mtime(d["safe"]),
               "unlock": bool(unlock), "told_old": 0})
    write_state(st)
    return paths, "Your Emergency Envelope is made and tested."


def mtime(path):
    try:
        return os.path.getmtime(path) if path else 0
    except OSError:
        return 0

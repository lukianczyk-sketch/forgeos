"""Copying your files. Never overwrites: a name that is taken gets " (from Windows)". Can stop and go on.

The log of copied files (~/.local/state/forgeos/movingday/copied-ID.log) lets a second run pick up
where the first one stopped. Windows shortcuts, thumbnails and other Windows junk are left behind.
"""
import errno
import hashlib
import os
import time

from . import HOME, MARGIN, state_dir
from . import passwords

JUNK = {"desktop.ini", "thumbs.db", "ehthumbs.db", "iconcache.db", ".ds_store"}
JUNK_ENDS = (".lnk", ".url", ".tmp", ".crdownload", ".partial")
SKIP_DIRS = {"$recycle.bin", "system volume information"}


class Full(Exception):
    """The ForgeOS drive is full."""


def junk(name, path):
    low = name.lower()
    return (low in JUNK or low.endswith(JUNK_ENDS) or low.startswith(("~$", "$", ".~lock"))
            or passwords.is_password_file(path))


def walk(src):
    """(file, path inside src) for every file worth copying; links are never followed."""
    for top, dirs, names in os.walk(src):
        dirs[:] = sorted(d for d in dirs if d.lower() not in SKIP_DIRS and not os.path.islink(os.path.join(top, d)))
        for name in sorted(names):
            path = os.path.join(top, name)
            if not os.path.islink(path) and not junk(name, path) and os.path.isfile(path):
                yield path, os.path.relpath(path, src)


def measure(srcs):
    size = count = 0
    for src in srcs:
        for path, _rel in walk(src):
            try:
                size, count = size + os.path.getsize(path), count + 1
            except OSError:
                pass
    return size, count


def free_name(path):
    """path, or "name (from Windows).ext", "(from Windows 2)", ... the first one that is free."""
    if not os.path.lexists(path):
        return path
    stem, ext = os.path.splitext(path)
    if os.path.isdir(path):
        stem, ext = path, ""
    n = 1
    while True:
        cand = "%s (from Windows%s)%s" % (stem, "" if n == 1 else " %d" % n, ext)
        if not os.path.lexists(cand):
            return cand
        n += 1


def log_path(base, user):
    key = hashlib.sha1(("%s\0%s" % (os.path.realpath(base), user)).encode()).hexdigest()[:12]
    return os.path.join(state_dir(), "copied-%s.log" % key)


def read_log(path):
    done = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                p = line.rstrip("\n").split("\t")
                if len(p) == 3 and p[2].isdigit():
                    done[p[0]] = (p[1], int(p[2]))
    except OSError:
        pass
    return done


def is_done(done, key, size):
    if key in done:
        dest, was = done[key]
        return was == size and os.path.isfile(dest) and os.path.getsize(dest) == size
    return False


def copy_one(src, dest):
    tmp = os.path.join(os.path.dirname(dest), ".moving-%s.part" % os.path.basename(dest))
    try:
        with open(src, "rb") as a, open(tmp, "wb") as b:
            while True:
                chunk = a.read(1 << 20)
                if not chunk:
                    break
                b.write(chunk)
        st = os.stat(src)
        os.utime(tmp, (st.st_atime, st.st_mtime))
        os.replace(tmp, dest)
    except OSError as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        if e.errno in (errno.ENOSPC, errno.EDQUOT):
            raise Full() from e
        raise


def plan(udir, items, log):
    """[(key, source file, size, ForgeOS folder, path inside)] still to copy, and the bytes they need."""
    done = read_log(log)
    todo, need = [], 0
    for name, srcs in items:
        for src in srcs:
            for path, rel in walk(src):
                key = os.path.relpath(path, udir)
                try:
                    size = os.path.getsize(path)
                except OSError:
                    continue
                if not is_done(done, key, size):
                    todo.append((key, path, size, os.path.join(HOME, name), rel))
                    need += size
    return todo, need


def copy_all(todo, log, progress=None):
    """Copy the plan. Returns a result dict; raises nothing (a full drive stops cleanly)."""
    res = {"copied": [], "same": 0, "skipped": [], "bytes": 0, "full": False}
    total = sum(t[2] for t in todo) or 1
    last = 0.0
    with open(log, "a", encoding="utf-8") as lf:
        for key, src, size, folder, rel in todo:
            want = os.path.join(folder, rel)
            try:
                os.makedirs(os.path.dirname(want), exist_ok=True)
                if os.path.isfile(want) and os.path.getsize(want) == size and \
                        abs(os.path.getmtime(want) - os.path.getmtime(src)) < 2:
                    res["same"] += 1
                    lf.write("%s\t%s\t%d\n" % (key, want, size))
                    continue
                dest = free_name(want)
                copy_one(src, dest)
            except Full:
                res["full"] = True
                break
            except OSError as e:
                res["skipped"].append((key, e.strerror or "could not be read"))
                continue
            res["copied"].append(dest)
            res["bytes"] += size
            lf.write("%s\t%s\t%d\n" % (key, dest, size))
            lf.flush()
            if progress and time.monotonic() - last > 1:
                last = time.monotonic()
                progress(res["bytes"], total, rel)
    if progress:
        progress(res["bytes"], total, "")
    return res


def enough_space(need, free):
    return need + MARGIN <= free

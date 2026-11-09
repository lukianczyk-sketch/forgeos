"""Free up space: the Trash, picture previews, unused app parts and big old downloads.

Nothing is deleted without the person picking it. Downloads only go to the Trash (they can come back).
"""
import os
import shutil

from . import DOWNLOADS, ENV, HOME, log, now, run

TRASH = os.path.join(HOME, ".local", "share", "Trash")
THUMBS = os.path.join(HOME, ".cache", "thumbnails")
BIG = int(ENV("FORGEOS_SLOW_BIG") or 100 * 1024 ** 2)
OLD_DAYS = 60


def folder_size(path):
    total = 0
    for d, _ds, fs in os.walk(path):
        for f in fs:
            try:
                total += os.lstat(os.path.join(d, f)).st_size
            except OSError:
                pass
    return total


def big_downloads():
    """[(path, bytes, days old)] of files in Downloads of 100 MB or more, not changed for 60 days, biggest first."""
    out = []
    for d, _ds, fs in os.walk(DOWNLOADS):
        for f in fs:
            p = os.path.join(d, f)
            try:
                st = os.lstat(p)
            except OSError:
                continue
            days = int((now() - st.st_mtime) // 86400)
            odd = any(c in p for c in "\t\n\r")  # names the window can't show safely are left alone
            if not odd and os.path.isfile(p) and not os.path.islink(p) and st.st_size >= BIG and days >= OLD_DAYS:
                out.append((p, st.st_size, days))
    return sorted(out, key=lambda x: -x[1])[:15]


def listing():
    """TAB lines for the window: TRASH bytes, THUMBS bytes, BIG path bytes days."""
    lines = ["TRASH\t%d" % folder_size(os.path.join(TRASH, "files")), "THUMBS\t%d" % folder_size(THUMBS)]
    lines += ["BIG\t%s\t%d\t%d" % (p, n, days) for p, n, days in big_downloads()]
    return lines


def empty_trash():
    code, _ = run(["gio", "trash", "--empty"], 300)
    if code != 0:
        for sub in ("files", "info"):
            shutil.rmtree(os.path.join(TRASH, sub), ignore_errors=True)
    log("emptied the Trash")
    return "The Trash is empty."


def clear_thumbs():
    shutil.rmtree(THUMBS, ignore_errors=True)
    log("cleared picture previews")
    return "Picture previews cleared (they come back by themselves when needed)."


def unused_apps():
    code, _ = run(["flatpak", "uninstall", "--unused", "-y", "--noninteractive"], 900)
    log("removed unused app parts (%d)" % code)
    return "Unused app parts removed." if code == 0 else "Unused app parts could not be removed right now."


def to_trash(path):
    real = os.path.realpath(path)
    if not real.startswith(os.path.realpath(DOWNLOADS) + os.sep) or not os.path.isfile(real):
        return "Only files in your Downloads folder can be moved to the Trash here."
    code, _ = run(["gio", "trash", real], 120)
    if code != 0:
        return "%s could not be moved to the Trash." % os.path.basename(real)
    log("moved to the Trash: " + real)
    return "%s is in the Trash (you can still get it back)." % os.path.basename(real)

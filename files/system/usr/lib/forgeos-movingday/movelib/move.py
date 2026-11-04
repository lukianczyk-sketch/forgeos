"""The move itself: space check, Undo snapshot, copy, virus check, bookmarks, then the plain report."""
import os

from . import FOLDERS, HOME, MARGIN, gb, run, state_dir
from . import bookmarks, brave, files, scan, sources

BATCH = 100


def progress(done, total, name):
    with open(os.path.join(state_dir(), "progress"), "w", encoding="utf-8") as f:
        f.write("%d\t%d\t%s\n" % (done, total, name[-80:]))


def virus_check(paths):
    """Always-On Guard checks every copied file; a bad one is locked away. (checked, [(file, virus)]) or None."""
    bad = []
    for i in range(0, len(paths), BATCH):
        code, out = run(["forgeos-guard", "scan"] + paths[i:i + BATCH], 1800)
        if code == 127:
            return None
        bad += [tuple(x.split("\t")[1:3]) for x in out.splitlines() if x.startswith("VIRUS\t")]
    return len(paths), bad


def move(base, user, picks):
    """picks: set of folder names plus "bookmarks". Returns (exit code, report lines)."""
    udir = scan.user_dir(base, user)
    if not udir:
        return 3, ["There is no Windows user called %s on that drive." % user]
    items = [(k, s) for k, s in scan.folders(udir) if k in picks]
    log = files.log_path(base, user)
    todo, need = files.plan(udir, items, log)
    free = sources.free_space(HOME)
    if need and not files.enough_space(need, free):
        return 4, ["Not enough room: this needs %s and ForgeOS has %s free (1 GB is always kept free)."
                   % (gb(need), gb(max(0, free - MARGIN))),
                   "Pick fewer folders, or free up room first (Clean Sweep or Filelight show what is big)."]
    lines = []
    if todo:
        code, _out = run(["forgeos-undo", "snapshot-now", "Before Moving Day"], 300)
        lines.append("NOTE\tUndo Button saved a snapshot first." if code == 0 else
                     "NOTE\tUndo Button is off, so no snapshot was taken first.")
    res = files.copy_all(todo, log, progress)
    lines.append("DONE\t%d\t%d\t%d\t%d" % (len(res["copied"]), res["same"], len(res["skipped"]), res["bytes"]))
    code = 0
    if res["full"]:
        lines.append("FULL\tThe ForgeOS drive got full, so Moving Day stopped. Free up room and run it again: it goes on where it stopped.")
        code = 4
    for key, why in res["skipped"][:20]:
        lines.append("SKIPPED\t%s\t%s" % (key, why))
        code = code or 1
    checked = virus_check(res["copied"]) if res["copied"] else (0, [])
    if checked is None:
        lines.append("NOTE\tAlways-On Guard is not on this PC, so the files were not virus-checked.")
    else:
        for path, virus in checked[1]:
            lines.append("VIRUS\t%s\t%s" % (path, virus))
            code = code or 1
    if "bookmarks" in picks:
        lines += bookmark_step(udir)
    return code, lines


def bookmark_step(udir):
    found = scan.bookmark_files(udir)
    if not found:
        return ["BOOKMARKS\tnone\t0\t-"]
    root, n, bad = bookmarks.collect(found)
    out = ["BOOKMARKS\tunreadable\t0\t%s" % b for b in bad]
    if not n:
        return out + ["BOOKMARKS\tnone\t0\t-"]
    page = bookmarks.write_html(root)
    try:
        added = brave.add_to_brave(root)
    except (OSError, ValueError, KeyError):
        added = False
    out.append("BOOKMARKS\t%s\t%d\t%s" % ("added" if added else ("brave-open" if brave.brave_open() else "html"), n, page))
    return out


def plain(lines):
    """The report in plain words."""
    out = []
    for line in lines:
        f = line.split("\t")
        if f[0] == "DONE" and f[1:4] == ["0", "0", "0"]:
            out.append("Nothing new to copy: those files were all copied before.")
        elif f[0] == "DONE":
            out.append("Copied %s files (%s)." % (f[1], gb(int(f[4]))))
            if f[2] != "0":
                out.append("%s files were already here, so they were not copied again." % f[2])
            if f[3] != "0":
                out.append("%s files could not be read (they may be only in OneDrive's cloud) and were left." % f[3])
        elif f[0] in ("NOTE", "FULL"):
            out.append(f[1])
        elif f[0] == "VIRUS":
            out.append("A virus was found and locked away: %s (%s)." % (os.path.basename(f[1]), f[2]))
        elif f[0] == "BOOKMARKS" and f[1] == "added":
            out.append("%s bookmarks are in Brave, in the \"From Windows\" folder on the bookmarks bar." % f[2])
        elif f[0] == "BOOKMARKS" and f[1] in ("html", "brave-open"):
            out.append("%s bookmarks were saved in Documents as \"%s\". %s" % (
                f[2], bookmarks.HTML_NAME, "Close Brave and run Moving Day again to add them, or import that file in Brave."
                if f[1] == "brave-open" else "Import that file in Brave."))
        elif f[0] == "BOOKMARKS" and f[1] == "unreadable":
            out.append("The %s bookmarks could not be read." % f[3])
        elif len(f) == 1:
            out.append(line)
    out.append("Your old Windows is untouched: nothing on it was changed or deleted.")
    return out


def picks_from(words):
    picks = set()
    for w in words.split(","):
        w = w.strip()
        hit = [f for f in FOLDERS if f.lower() == w.lower()]
        if hit:
            picks.add(hit[0])
        elif w.lower() == "bookmarks":
            picks.add("bookmarks")
        elif w:
            return None
    return picks

"""Bait files: two harmless files in each watched folder that nobody should ever touch.

Ransomware goes through folders from the top or the bottom, so the names sort first and last.
Each folder's .hidden file lists them, so Dolphin does not show them. If a program writes to one,
deletes it or renames it, the tripwire goes off at once. Root writes them without following
symlinks and gives them to the folder's owner.
"""
import io
import os
import stat
import zipfile

from . import FOLDERS, HOMES

NAMES = ("000 Bank statements.pdf", "zzz Tax return 2026.docx")
OLD = 1705334400  # 2024-01-15: they look like old papers, not something new
NOTE = "This is a ForgeOS Ransomware Tripwire safety file. Please leave it alone - it guards your files."
PDF = ("%%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Kids [3 0 R]"
       " /Count 1 >> endobj\n3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >> endobj\n"
       "%% %s\ntrailer << /Root 1 0 R >>\n%%%%EOF\n" % NOTE).encode()


def docx():
    """A tiny Word file (stored, not compressed, so it is the same bytes every time)."""
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:
        for name, text in (("[Content_Types].xml", "<Types/>"), ("word/document.xml", NOTE)):
            z.writestr(zipfile.ZipInfo(name, (2024, 1, 15, 9, 0, 0)), text)
    return out.getvalue()


CONTENT = {NAMES[0]: PDF, NAMES[1]: docx()}


def homes():
    """[(home folder, uid, gid)] for every person with a home folder in /var/home."""
    found = []
    try:
        names = sorted(os.listdir(HOMES))
    except OSError:
        return found
    for name in names:
        path = os.path.join(HOMES, name)
        try:
            st = os.lstat(path)
        except OSError:
            continue
        if not name.startswith(".") and stat.S_ISDIR(st.st_mode) and st.st_uid >= 1000:
            found.append((path, st.st_uid, st.st_gid))
    return found


def folders(home):
    """The watched folders that exist in this home (real folders, not symlinks)."""
    return [os.path.join(home, f) for f in FOLDERS
            if os.path.isdir(os.path.join(home, f)) and not os.path.islink(os.path.join(home, f))]


def is_bait(path):
    return os.path.basename(path) in NAMES and os.path.basename(os.path.dirname(path)) in FOLDERS


def state(path):
    """'ok', 'missing' or 'changed'."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return "missing"
    with os.fdopen(fd, "rb") as f:
        return "ok" if f.read(65536) == CONTENT[os.path.basename(path)] else "changed"


def _write(dfd, name, data, uid, gid, mode, when=None):
    """Write a new copy, then rename it over the old one (a rename never looks like a deleted bait file)."""
    tmp = ".forgeos-tripwire.tmp"
    try:
        os.unlink(tmp, dir_fd=dfd)
    except OSError:
        pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode, dir_fd=dfd)
    try:
        os.write(fd, data)
        if os.geteuid() == 0:
            os.fchown(fd, uid, gid)
        if when:
            os.utime(fd, (when, when))
    finally:
        os.close(fd)
    os.replace(tmp, name, src_dir_fd=dfd, dst_dir_fd=dfd)


def place(folder, uid, gid):
    """Put back missing or changed bait files and list them in .hidden. Returns how many were written."""
    try:
        dfd = os.open(folder, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError:
        return 0
    wrote = 0
    try:
        for name in NAMES:
            path = os.path.join(folder, name)
            if state(path) == "ok":
                continue
            try:
                _write(dfd, name, CONTENT[name], uid, gid, 0o644, OLD)
                wrote += 1
            except OSError:
                continue
        try:
            with os.fdopen(os.open(".hidden", os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dfd)) as f:
                hidden = f.read().splitlines()
        except OSError:
            hidden = []
        if any(n not in hidden for n in NAMES):
            keep = [x for x in hidden if x and x not in NAMES] + list(NAMES)
            try:
                _write(dfd, ".hidden", ("\n".join(keep) + "\n").encode(), uid, gid, 0o644)
            except OSError:
                pass
    finally:
        os.close(dfd)
    return wrote


def place_all():
    """Every home: bait in every watched folder. Returns {home: 'ok' | 'missing N'}."""
    found = {}
    for home, uid, gid in homes():
        for folder in folders(home):
            place(folder, uid, gid)
        bad = [p for f in folders(home) for p in (os.path.join(f, n) for n in NAMES) if state(p) != "ok"]
        found[home] = "ok %d" % (2 * len(folders(home))) if not bad else "missing %d" % len(bad)
    return found

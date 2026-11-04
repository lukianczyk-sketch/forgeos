"""What is on the old drive: the Windows users, their folders and sizes, bookmarks, passwords, programs."""
import glob
import os

from . import FOLDERS, NOT_USERS, child, path_in
from . import files, passwords, programs

CHROMIUM = (("Chrome", ("Google", "Chrome", "User Data")),
            ("Edge", ("Microsoft", "Edge", "User Data")),
            ("Brave", ("BraveSoftware", "Brave-Browser", "User Data")))


def users(base):
    """Windows user folders (Public, Default and the hidden system ones are left out)."""
    top = path_in(base, "Users")
    found = []
    for name in sorted(os.listdir(top)) if top else []:
        d = os.path.join(top, name)
        if name.lower() in NOT_USERS or name.startswith((".", "$")) or not os.path.isdir(d) or os.path.islink(d):
            continue
        if any(child(d, f) for f in FOLDERS + ("AppData", "NTUSER.DAT", "OneDrive")):
            found.append(name)
    return found


def user_dir(base, name):
    return path_in(base, "Users", name)


def folders(udir):
    """[(Documents, [source folders]), ...]: the normal folder plus the OneDrive copy if there is one."""
    one = [os.path.join(udir, d) for d in sorted(os.listdir(udir)) if d.lower().startswith("onedrive")
           and os.path.isdir(os.path.join(udir, d)) and not os.path.islink(os.path.join(udir, d))]
    out = []
    for name in FOLDERS:
        srcs = [p for p in [child(udir, name)] + [child(o, name) for o in one]
                if p and os.path.isdir(p) and not os.path.islink(p)]
        if srcs:
            out.append((name, srcs))
    return out


def bookmark_files(udir):
    """[(label, chromium|firefox, file)] for every browser profile that has bookmarks."""
    found = []
    for label, parts in CHROMIUM:
        data = path_in(udir, "AppData", "Local", *parts)
        for prof in sorted(os.listdir(data)) if data else []:
            f = path_in(data, prof, "Bookmarks")
            if f and os.path.isfile(f) and (prof == "Default" or prof.startswith("Profile ")):
                found.append((label if prof == "Default" else "%s (%s)" % (label, prof), "chromium", f))
    ff = path_in(udir, "AppData", "Roaming", "Mozilla", "Firefox", "Profiles")
    profs = [p for p in sorted(os.listdir(ff)) if path_in(ff, p, "places.sqlite")] if ff else []
    for p in profs:
        label = "Firefox" if len(profs) == 1 else "Firefox (%s)" % p.split(".", 1)[-1]
        found.append((label, "firefox", path_in(ff, p, "places.sqlite")))
    return found


def password_files(base, udir):
    """Password files exported from the browsers: in the Moving Box, or saved in Downloads/Desktop/Documents."""
    cands = []
    box_pw = path_in(base, "passwords")
    if box_pw:
        cands += glob.glob(os.path.join(glob.escape(box_pw), "*"))
    for name in ("Downloads", "Desktop", "Documents"):
        d = child(udir, name) if udir else None
        if d:
            cands += glob.glob(os.path.join(glob.escape(d), "*"))
    return sorted(p for p in cands if os.path.isfile(p) and passwords.is_password_file(p, box=p.startswith(box_pw or "\0")))


def scan(base, who=None):
    """Everything Moving Day can bring over, as tab lines for the window."""
    lines = []
    names = users(base)
    for name in names if who is None else [n for n in names if n == who]:
        udir = user_dir(base, name)
        total = count = 0
        items = []
        for key, srcs in folders(udir):
            size, n = files.measure(srcs)
            total, count = total + size, count + n
            items.append("ITEM\t%s\tfiles:%s\t%d\t%d" % (name, key, size, n))
        marks = bookmark_files(udir)
        if marks:
            items.append("ITEM\t%s\tbookmarks\t0\t%d\t%s" % (name, len(marks), ", ".join(m[0] for m in marks)))
        pw = password_files(base, udir)
        if pw:
            items.append("ITEM\t%s\tpasswords\t0\t%d\t%d" % (name, len(pw), sum(passwords.count(p) for p in pw)))
        progs = programs.names(base, udir)
        if progs:
            items.append("ITEM\t%s\tprograms\t0\t%d" % (name, len(progs)))
        lines.append("USER\t%s\t%d\t%d" % (name, total, count))
        lines += items
    return lines

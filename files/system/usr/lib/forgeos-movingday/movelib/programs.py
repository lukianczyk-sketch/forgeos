"""The programs you used on Windows, and the free ForgeOS way to do the same job (from Will It Run?'s lists).

Names come from the Start menu shortcuts on the drive, and from programs.txt in a Moving Box (the Pack tool
writes Windows' own list of installed programs). Windows' own tools, uninstallers and runtimes are left out.
"""
import glob
import os
import re

from . import WIR_LISTS, clean, norm, path_in

WINDOWS_FOLDERS = {"accessibility", "accessories", "administrative tools", "maintenance", "startup", "system tools",
                   "windows accessories", "windows administrative tools", "windows ease of access",
                   "windows powershell", "windows system", "windows tools"}
NOISE = re.compile(r"\b(uninstall|uninstaller|readme|read me|help|manual|documentation|website|web site|release notes|"
                   r"license|redistributable|runtime|sdk|driver|drivers|update for|hotfix|security update|"
                   r"service pack|visual c|net framework|net desktop|webview|kb\d+|language pack|"
                   r"what s new|support center|on the web|faq)\b")
MOST = 200


def start_menu(root):
    """Shortcut names in a Start menu Programs folder, without Windows' own tool folders."""
    out = []
    for top, dirs, names in os.walk(root) if root else []:
        dirs[:] = [d for d in dirs if d.lower() not in WINDOWS_FOLDERS]
        out += [n[:-4] for n in names if n.lower().endswith(".lnk")]
    return out


def names(base, udir):
    """Program names, cleaned, without duplicates or noise."""
    raw = []
    lst = path_in(base, "programs.txt")
    if lst:
        try:
            with open(lst, encoding="utf-8-sig", errors="replace") as f:
                raw += [x.strip() for x in f]
        except OSError:
            pass
    raw += start_menu(path_in(base, "ProgramData", "Microsoft", "Windows", "Start Menu", "Programs"))
    if udir:
        raw += start_menu(path_in(udir, "AppData", "Roaming", "Microsoft", "Windows", "Start Menu", "Programs"))
    seen, out = set(), []
    for name in raw:
        name = clean(name, 80)
        key = norm(name)
        if len(key) < 2 or key in seen or NOISE.search(key):
            continue
        seen.add(key)
        out.append(name)
    return sorted(out, key=str.lower)[:MOST]


def lists():
    """Will It Run?'s known programs: [(pattern, way, app id, answer)], in file order (first match wins)."""
    rows = []
    for path in sorted(glob.glob(os.path.join(glob.escape(WIR_LISTS), "*.txt"))):
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith("#"):
                    continue
                p = line.rstrip("\n").split(" ~ ")
                if len(p) >= 4:
                    try:
                        rows.append((re.compile(p[0]), p[1], p[2], p[3]))
                    except re.error:
                        pass
    return rows


def match(name, known):
    key = norm(name)
    for pat, way, app, answer in known:
        if pat.search(key):
            return way, app, answer
    return None


def report(base, udir):
    """PROGRAM / UNKNOWN tab lines: name, way, app id, plain-English answer."""
    known = lists()
    out = []
    for name in names(base, udir):
        hit = match(name, known)
        out.append("PROGRAM\t%s\t%s\t%s\t%s" % ((name,) + hit) if hit else "UNKNOWN\t%s" % name)
    return out

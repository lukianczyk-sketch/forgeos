"""The running programs: who uses the processor and the memory, by their friendly names.

Processor use is measured over WAIT seconds (two readings of /proc/PID/stat), so it is what is happening
NOW, not an average since the program started. A fake /proc for the tests can give the second reading in
stat.next. Programs are grouped by app (a browser is many processes, one app); Flatpak's wrapper
processes (bwrap) never name or decide an app. A program in a hidden place gets a group of its own.
"""
import os
import re

from . import APPDIRS, PROC, UID, WAIT, read
from .rules import WRAPPERS, is_game, is_keep, suspicious

HZ = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100
APP = re.compile(r"/app-(?:flatpak-|gnome-|kde-)?([A-Za-z0-9_.+-]+?)(?:@[^/]*)?(?:-[0-9a-f]{32}|-[0-9]+)?"
                 r"\.(?:scope|service)$")


def ticks(pid, name="stat"):
    """utime + stime of one process (clock ticks), or None."""
    s = read(os.path.join(PROC, pid, name))
    rest = s[s.rfind(")") + 2:].split() if ")" in s else []
    try:
        return int(rest[11]) + int(rest[12])
    except (IndexError, ValueError):
        return None


def memory(pid, st):
    """Bytes of memory a process really uses: its fair share (Pss), else VmRSS."""
    for line in read(os.path.join(PROC, pid, "smaps_rollup")).splitlines():
        if line.startswith("Pss:") and line.split()[1:2] and line.split()[1].isdigit():
            return int(line.split()[1]) * 1024
    v = st.get("VmRSS", "0 kB").split()
    return int(v[0]) * 1024 if v and v[0].isdigit() else 0


def script(comm, argv):
    """A Python program's name is its script's name (forgeos-find, ...)."""
    for i, a in enumerate(argv):
        if a == "-c" or not a:
            break
        if a == "-m" or not a.startswith("-"):
            return os.path.basename(argv[i + 1] if a == "-m" and i + 1 < len(argv) else a)[:40]
    return comm


def info(pid):
    """One process as a dict (pid comm uid rss exe app keep game bad wrap), or None when it is gone."""
    s = read(os.path.join(PROC, pid, "stat"))
    if ")" not in s:
        return None
    st = dict(x.split(":", 1) for x in read(os.path.join(PROC, pid, "status")).splitlines() if ":" in x)
    try:
        uid = int(st.get("Uid", "-1").split()[0])
    except (IndexError, ValueError):
        uid = -1
    try:
        exe = os.readlink(os.path.join(PROC, pid, "exe"))
    except OSError:
        exe = ""
    cg = read(os.path.join(PROC, pid, "cgroup"))
    m = None
    for line in cg.splitlines():
        m = APP.search(line.strip()) or m
    argv = read(os.path.join(PROC, pid, "cmdline")).split("\0")
    comm = s[s.find("(") + 1:s.rfind(")")]
    if comm.startswith("python"):
        comm = script(comm, argv[1:])
    bad = suspicious(exe)
    safe = re.sub(r"[^A-Za-z0-9_.+-]", "_", comm) or "_"
    return {"pid": int(pid), "comm": comm, "uid": uid, "rss": memory(pid, st), "exe": exe, "bad": bad,
            "app": safe + "-hidden" if bad else (m.group(1) if m else safe), "keep": is_keep(comm, exe, cg),
            "game": is_game(comm, exe, argv[0], cg), "wrap": comm in WRAPPERS}


def table():
    """Every process with 'cpu' = percent of ONE processor core used during the last WAIT seconds."""
    pids = sorted((p for p in os.listdir(PROC) if p.isdigit()), key=int)
    first = {p: ticks(p) for p in pids}
    if WAIT > 0:
        import time
        time.sleep(WAIT)
    rows = []
    for p in pids:
        i = info(p)
        b = ticks(p, "stat.next") if os.path.exists(os.path.join(PROC, p, "stat.next")) else ticks(p)
        if not i or first[p] is None or b is None:
            continue
        i["cpu"] = max(0.0, (b - first[p]) * 100.0 / HZ / (WAIT or 1))
        rows.append(i)
    return rows


def friendly(app):
    """'com.brave.Browser' -> 'Brave' (the Name= of its menu entry), else the program name."""
    for d in APPDIRS:
        for f in (app + ".desktop", app.lower() + ".desktop"):
            for line in read(os.path.join(d, f)).splitlines():
                if line.startswith("Name="):
                    return line[5:].strip()[:40]
    return app[:1].upper() + app[1:40]


def apps(rows):
    """Programs grouped by app, busiest first. 'main' is the app's first real (not wrapper) process: the
    one that is asked to close. A group is a desktop part only when all its real processes are."""
    g = {}
    for r in rows:
        g.setdefault(r["app"], []).append(r)
    out = []
    for key, rs in g.items():
        real = [r for r in rs if not r["wrap"]] or rs
        m = real[0]
        out.append({"app": key, "name": friendly(key[:-7] if m["bad"] else key), "main": m["pid"], "uid": m["uid"],
                    "cpu": sum(r["cpu"] for r in rs), "rss": sum(r["rss"] for r in rs), "exe": m["exe"],
                    "comm": m["comm"], "bad": m["bad"], "keep": all(r["keep"] for r in real),
                    "game": any(r["game"] for r in rs)})
    return sorted(out, key=lambda a: -a["cpu"])


def mine(a):
    return a["uid"] == UID and not a["keep"]


def close(pid, app):
    """Close one app (a polite TERM to its main process) only if it is still that app, ours and not a
    desktop part. Returns a sentence."""
    i = info(str(pid))
    if not i or i["app"] != app:
        return "That program is not running any more, so nothing was closed."
    if i["uid"] != UID or i["keep"] or i["wrap"]:
        return "That program is part of the system, so it was not closed."
    try:
        os.kill(int(pid), 15)
    except OSError:
        return "It could not be closed."
    return "%s was asked to close." % friendly(app)

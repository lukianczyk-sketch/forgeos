"""Your running programs: which ones are remote-control apps, and pause / let go / end them.

An app from the KDE menu, Dolphin, Bottles or Flatpak runs in its own "scope" (a cgroup): the whole app is
paused at once (frozen, not killed). One started from a terminal is paused with SIGSTOP (with what it
started). Only YOUR programs are looked at: a remote app needs your session to see your screen.
"""
import hashlib
import os
import re
import signal

from . import CGROUP, PROC, TEST_DIR, my_uid
from . import apps

SCOPE = re.compile(r"^(app|flatpak|snap|run|dbus)-[^/]+\.(scope|service)$")
FLATPAK = re.compile(r"app-flatpak-(.+)-[0-9]+\.scope$")


def _read(path, most=65536):
    try:
        with open(path, "rb") as f:
            return f.read(most).decode("utf-8", "replace")
    except OSError:
        return ""


def info(pid):
    """{'pid', 'uid', 'ppid', 'name', 'exe', 'argv', 'cmd', 'cgroup', 'flatpak'} ({} if it is gone)."""
    base = os.path.join(PROC, str(pid))
    status = _read(os.path.join(base, "status"))
    if not status:
        return {}
    uid = re.search(r"^Uid:\s+(\d+)", status, re.M)
    ppid = re.search(r"^PPid:\s+(\d+)", status, re.M)
    cg = [x[3:] for x in _read(os.path.join(base, "cgroup")).splitlines() if x.startswith("0::")]
    cg = cg[0] if cg else ""
    try:
        exe = os.readlink(os.path.join(base, "exe")).replace(" (deleted)", "")
    except OSError:
        exe = ""
    argv = [a for a in _read(os.path.join(base, "cmdline")).split("\0") if a]
    fp = FLATPAK.search(cg.rstrip("/").rsplit("/", 1)[-1])
    return {"pid": int(pid), "uid": int(uid.group(1)) if uid else -1, "ppid": int(ppid.group(1)) if ppid else 0,
            "name": _read(os.path.join(base, "comm")).strip(), "exe": exe, "argv": argv, "cmd": " ".join(argv),
            "cgroup": cg, "flatpak": fp.group(1).replace("\\x2d", "-") if fp else ""}


def mine():
    """Every program of yours that is running now."""
    uid = my_uid()
    found = []
    for name in os.listdir(PROC):
        if name.isdigit():
            i = info(name)
            if i and i["uid"] == uid:
                found.append(i)
    return found


def freezable(cg):
    """True when the cgroup holds one app only (never the whole desktop session or a system part)."""
    leaf = cg.rstrip("/").rsplit("/", 1)[-1]
    return bool(SCOPE.match(leaf)) and "/app.slice/" in cg + "/" and ".." not in cg


def key(i):
    """Which programs belong to the same app: its scope, or the program itself."""
    return "cg:" + i["cgroup"] if freezable(i.get("cgroup", "")) else "pid:%d" % i.get("pid", 0)


def remote_apps(found=None):
    """{key: hit}: every remote-control app running now (its first program + 'app', 'title', 'pids',
    'test' = the pretend app of "Test the guard")."""
    hits = {}
    for i in mine() if found is None else found:
        what = apps.which([i["name"], os.path.basename(i["exe"]), i["argv"][0] if i["argv"] else "", i["flatpak"]])
        if not what:
            continue
        k = key(i)
        if k in hits:
            hits[k]["pids"].append(i["pid"])
            continue
        hit = dict(i, app=what[0], title=what[1], key=k, pids=[i["pid"]])
        hit["test"] = bool(i["argv"]) and ("/%s/" % TEST_DIR) in i["argv"][0]
        hits[k] = hit
    return hits


def sha256(pid):
    """The fingerprint of the program file a program runs (read through /proc, also inside a Flatpak)."""
    h = hashlib.sha256()
    try:
        with open(os.path.join(PROC, str(pid), "exe"), "rb") as f:
            for block in iter(lambda: f.read(1 << 20), b""):
                h.update(block)
    except OSError:
        return ""
    return h.hexdigest()


def children(pids):
    """These programs and every program they started."""
    parent = {}
    for name in os.listdir(PROC):
        if name.isdigit():
            m = re.search(r"^PPid:\s+(\d+)", _read(os.path.join(PROC, name, "status")), re.M)
            if m:
                parent.setdefault(int(m.group(1)), []).append(int(name))
    found, todo = [], list(pids)
    while todo:
        p = todo.pop()
        if p not in found:
            found.append(p)
            todo += parent.get(p, [])
    return found


def _cg(cg, name, value=None):
    path = os.path.join(CGROUP, cg.lstrip("/"), name)
    if value is None:
        return _read(path)
    with open(path, "w") as f:
        f.write(value)
    return value


def _signal(pids, sig):
    done = False
    for p in pids:
        try:
            os.kill(p, sig)
            done = True
        except OSError:
            pass
    return done


def pause(hit):
    """Freeze the app. Returns ('app', pids) / ('program', pids) / ('failed', [])."""
    cg, pids = hit.get("cgroup", ""), children(hit["pids"])
    if freezable(cg):
        inside = [int(x) for x in _cg(cg, "cgroup.procs").split() if x.isdigit()]
        if all(p in pids for p in inside):  # the scope holds this app only (not a whole terminal window)
            try:
                _cg(cg, "cgroup.freeze", "1")
                return "app", pids
            except OSError:
                pass
    return ("program", pids) if _signal(pids, signal.SIGSTOP) else ("failed", [])


def let_go(how, cg, pids):
    if how == "app":
        try:
            _cg(cg, "cgroup.freeze", "0")
            return True
        except OSError:
            return False
    return _signal(pids, signal.SIGCONT)


def end(how, cg, pids):
    """End the app for good (a paused app can still be ended). When it could not even be paused, its scope
    is ended as a whole if it holds this app only."""
    inside = [int(x) for x in _cg(cg, "cgroup.procs").split() if x.isdigit()] if freezable(cg) else []
    if how == "app" or (how == "failed" and inside and all(p in children(pids) for p in inside)):
        try:
            _cg(cg, "cgroup.kill", "1")
            return True
        except OSError:
            pids = pids + inside
    return _signal(pids, signal.SIGKILL)

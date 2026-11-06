"""Programs: who is it, is it trusted, and freeze / unfreeze / end it.

Every app started from the KDE menu, Dolphin or Bottles runs in its own "scope" (a cgroup), so the
whole app (with every helper process it started) is frozen at once: frozen, not killed, so nothing is
lost if it was a mistake. A program outside an app scope (e.g. in the desktop's own session) is
stopped with SIGSTOP instead, together with the programs it started.
"""
import hashlib
import os
import re
import signal

from . import CGROUP, PROC, TRUSTED

SCOPE = re.compile(r"^(app|flatpak|snap|run|dbus)-[^/]+\.(scope|service)$")
# Programs that run OTHER programs (Wine runs every Windows program, python every script...): for these,
# "It's mine" trusts only that exact command line, never every Windows program or script.
RUNNERS = re.compile(r"^(wine.*|python[0-9.]*|java|bash|sh|dash|zsh|perl|node|mono|ruby|php.*|pwsh|bwrap)$")


def _read(path):
    try:
        with open(path, "rb") as f:
            return f.read(65536).decode("utf-8", "replace")
    except OSError:
        return ""


def info(pid):
    """{'pid', 'exe', 'name', 'uid', 'cgroup', 'cmd'} of a running program ({} if it is gone)."""
    base = os.path.join(PROC, str(pid))
    status = _read(os.path.join(base, "status"))
    if not status:
        return {}
    uid = re.search(r"^Uid:\s+(\d+)", status, re.M)
    cg = [x[3:] for x in _read(os.path.join(base, "cgroup")).splitlines() if x.startswith("0::")]
    try:
        exe = os.readlink(os.path.join(base, "exe"))
    except OSError:
        exe = ""
    cmd = _read(os.path.join(base, "cmdline")).split("\0")
    return {"pid": int(pid), "exe": exe.replace(" (deleted)", ""), "name": _read(os.path.join(base, "comm")).strip(),
            "uid": int(uid.group(1)) if uid else -1, "cgroup": cg[0] if cg else "", "cmd": " ".join(cmd).strip()}


def freezable(cg):
    """True when the cgroup holds one app only (never the whole desktop session or a system part)."""
    leaf = cg.rstrip("/").rsplit("/", 1)[-1]
    return bool(SCOPE.match(leaf)) and "/app.slice/" in cg + "/" and ".." not in cg


def key(i):
    """Which events belong to the same app: its scope, or the program itself."""
    return "cg:" + i["cgroup"] if freezable(i.get("cgroup", "")) else "pid:%d" % i.get("pid", 0)


def sha256(path):
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for block in iter(lambda: f.read(1 << 20), b""):
                h.update(block)
    except OSError:
        return ""
    return h.hexdigest()


def trusted_list():
    try:
        with open(TRUSTED) as f:
            return {x.split("#", 1)[0].strip() for x in f if x.split("#", 1)[0].strip()}
    except OSError:
        return set()


def runner(exe):
    return bool(RUNNERS.match(os.path.basename(exe)))


def trusted(i, allowed, listed):
    """Backups, updates, games and the programs you said are yours never set it off."""
    exe = i.get("exe", "")
    if exe in listed:
        return True
    return any(a.get("exe") == exe and a.get("sha256") == sha256(exe)
               and (not runner(exe) or a.get("cmd") == i.get("cmd")) for a in allowed if exe)


def children(pid):
    """pid and every program it started (and they started)."""
    parent = {}
    for name in os.listdir(PROC):
        if name.isdigit():
            m = re.search(r"^PPid:\s+(\d+)", _read(os.path.join(PROC, name, "status")), re.M)
            if m:
                parent.setdefault(int(m.group(1)), []).append(int(name))
    found, todo = [], [pid]
    while todo:
        p = todo.pop()
        if p not in found:
            found.append(p)
            todo += parent.get(p, [])
    return found


def _cg_write(cg, name, value):
    with open(os.path.join(CGROUP, cg.lstrip("/"), name), "w") as f:
        f.write(value)


def _signal(pids, sig):
    done = False
    for p in pids:
        try:
            os.kill(p, sig)
            done = True
        except OSError:
            pass
    return done


def freeze(i):
    """Freeze the app. Returns ('app', pids) / ('program', pids) / ('failed', [])."""
    cg = i.get("cgroup", "")
    if freezable(cg):
        try:
            _cg_write(cg, "cgroup.freeze", "1")
            return "app", []
        except OSError:
            pass
    pids = children(i["pid"]) if i.get("pid") else []
    return ("program", pids) if pids and _signal(pids, signal.SIGSTOP) else ("failed", [])


def unfreeze(how, cg, pids):
    if how == "app":
        try:
            _cg_write(cg, "cgroup.freeze", "0")
            return True
        except OSError:
            return False
    return _signal(pids, signal.SIGCONT)


def end(how, cg, pids):
    """End the app for good (a frozen app can still be ended)."""
    if how == "app":
        try:
            _cg_write(cg, "cgroup.kill", "1")
            return True
        except OSError:
            pids = [int(x) for x in _read(os.path.join(CGROUP, cg.lstrip("/"), "cgroup.procs")).split() if x.isdigit()]
    return _signal(pids, signal.SIGKILL)

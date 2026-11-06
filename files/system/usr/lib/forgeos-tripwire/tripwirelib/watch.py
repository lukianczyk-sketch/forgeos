"""The root watcher (forgeos-tripwire.service): sees every finished file write on the home drive and
on USB drives, and sets the tripwire off. Hidden folders, caches and game folders are not watched.

--feed FILE replays pretend events (JSON lines: t, pid, path, kind) instead of the kernel's: the tests use it.
"""
import json
import os
import select
import time

from . import ALLOWED, FOLDERS, HOMES, MEDIA, STATUS, load_json, now, save_json, say
from . import bait, incident, procs, scramble
from .detect import Detector

SKIP = ("/steamapps/", "/Games/", "/node_modules/", "/__pycache__/")


def watched(path):
    """In one of your 6 folders (or on a USB drive), and not in a hidden or game folder."""
    if any(s in path for s in SKIP):
        return False
    for root in (HOMES, MEDIA):
        rel = os.path.relpath(path, root)
        if rel.startswith(".."):
            continue
        parts = rel.split("/")
        if any(p.startswith(".") for p in parts[:-1]) or len(parts) < 3:
            return False
        return root == MEDIA or parts[1] in FOLDERS
    return False


class Watcher:
    def __init__(self):
        self.det = Detector(load_json(ALLOWED, []), procs.trusted_list())
        self.allowed_at = self._mtime()
        self.me = os.getpid()

    def _mtime(self):
        try:
            return os.stat(ALLOWED).st_mtime
        except OSError:
            return 0

    def reload(self):
        """You pressed "It's mine": that program is trusted from now on."""
        if self._mtime() != self.allowed_at:
            self.allowed_at = self._mtime()
            self.det = Detector(load_json(ALLOWED, []), procs.trusted_list())

    def write(self, t, pid, path, head):
        if pid == self.me or not watched(path):
            return None
        info = procs.info(pid)
        verdict = "bait" if bait.is_bait(path) else scramble.judge(os.path.basename(path), head)
        hit = self.det.event(t, info, path, verdict)
        return incident.trigger(hit[0], hit[1], t) if hit else None

    def gone(self, t, path):
        if not bait.is_bait(path):
            return None
        hit = self.det.gone(t, path)
        inc = incident.trigger(hit[0], hit[1], t) if hit else incident.bait_note(path, t)
        self.tend()
        return inc

    def tend(self):
        """Bait files back in place, the status file up to date."""
        homes = bait.place_all()
        save_json(STATUS, {"state": "on", "time": now(), "homes": homes, "pid": self.me}, 0o644)
        return homes


def feed(path):
    w = Watcher()
    w.tend()
    found = []
    base = now()
    with open(path) as f:
        for line in f:
            if not line.strip():
                continue
            e = json.loads(line)
            t = base + float(e.get("t", 0))
            if e.get("kind") == "gone":
                inc = w.gone(t, e["path"])
            else:
                inc = w.write(t, int(e["pid"]), e["path"], scramble.read_head(e["path"]))
            if inc:
                found.append(inc["id"])
    for iid in found:
        print("INCIDENT\t%s" % iid)
    return 0


def main(seconds=0):
    """Watch for real (root). seconds > 0 = stop after that long (used by the kernel test)."""
    from .kernel import Fanotify, Inotify
    w = Watcher()
    try:
        fan, ino = Fanotify(), Inotify()
    except OSError as e:
        say("Ransomware Tripwire can't watch: %s" % e)
        save_json(STATUS, {"state": "off", "time": now(), "why": str(e)}, 0o644)
        return 3
    if not fan.mark(HOMES):
        say("Ransomware Tripwire can't watch %s (fanotify mark failed)" % HOMES)
        save_json(STATUS, {"state": "off", "time": now(), "why": "mark failed"}, 0o644)
        return 3
    say("Ransomware Tripwire is watching %s" % HOMES)
    end = time.monotonic() + seconds if seconds else 0
    last = 0.0
    while not end or time.monotonic() < end:
        if time.monotonic() - last > 30:
            last = time.monotonic()
            for home, _u, _g in bait.homes():
                for folder in bait.folders(home):
                    ino.watch(folder)
            for usb in usb_drives():
                fan.mark(usb)
            w.reload()
            w.det.tidy(now())
            w.tend()
        ready, _, _ = select.select([fan.fd, ino.fd], [], [], 1.0)
        if fan.fd in ready:
            for pid, path, head in fan.read(watched):
                if pid:
                    w.write(now(), pid, path, head)
        if ino.fd in ready:
            for path in ino.read():
                if path:
                    w.gone(now(), path)
    return 0


def usb_drives():
    """Mounted USB drives (/run/media/USER/NAME): watched too, but nothing on them can be put back."""
    found = []
    try:
        for user in os.listdir(MEDIA):
            for name in os.listdir(os.path.join(MEDIA, user)):
                found.append(os.path.join(MEDIA, user, name))
    except OSError:
        pass
    return [p for p in found if os.path.ismount(p)]

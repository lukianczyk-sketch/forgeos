"""The guard that never sleeps: watches Downloads, the Desktop and Thunderbird's mail folders.

A file is checked once it stops growing (downloads finish, emails are fully written).
"""
import os
import select
import time

from . import ENV, settings
from . import inbox, inotify, mail
from .downloads import download_dirs, handle_downloads

SETTLE = float(ENV("FORGEOS_GUARD_SETTLE") or 2)
PART = (".crdownload", ".part", ".partial", ".download", ".tmp", ".opdownload")
FILES = inotify.CLOSE_WRITE | inotify.MOVED_TO | inotify.CREATE
MAIL = FILES | inotify.MODIFY


class Watcher:
    def __init__(self):
        self.ino = inotify.Inotify()
        self.inbox = inbox.Inbox()
        self.pending = {}  # path -> [size, when it last changed, "download" or "mail"]
        self.mail_roots = []
        self.look_around()

    def tree(self, top, mask, depth):
        for folder, subs, _files in os.walk(top):
            if folder[len(top):].count(os.sep) >= depth:
                subs[:] = []
            subs[:] = [s for s in subs if not s.startswith(".")]
            if not self.ino.watching(folder):
                self.ino.watch(folder, mask)

    def look_around(self):
        """(Again) find the folders to watch: new Thunderbird accounts, a Downloads folder made later."""
        for d in download_dirs():
            if os.path.isdir(d):
                self.tree(d, FILES, 3)
        self.mail_roots = inbox.roots()
        for root in self.mail_roots:
            self.tree(root, MAIL, 8)
            for folder, _subs, files in os.walk(root):
                for f in files:
                    self.inbox.remember_end(os.path.join(folder, f))
        self.inbox.save()

    def root_of(self, path):
        """The Thunderbird mail folder this path is in, or '' (then it is a download)."""
        return next((r for r in self.mail_roots if path.startswith(r + os.sep)), "")

    def note(self, folder, name, mask):
        path = os.path.join(folder, name)
        root = self.root_of(path)
        kind = "mail" if root else "download"
        if mask & inotify.ISDIR:
            if mask & (inotify.CREATE | inotify.MOVED_TO):
                self.tree(path, MAIL if kind == "mail" else FILES, 3 if kind == "download" else 8)
                for sub, _dirs, files in os.walk(path):
                    for f in files:
                        self.note(sub, f, inotify.CLOSE_WRITE)
            return
        if kind == "download" and (name.startswith(".") or name.lower().endswith(PART)):
            return
        if root and mail.skip_folder(os.path.relpath(path, root)):
            return
        self.pending[path] = [-1, time.monotonic(), kind]

    def settle(self):
        """Paths that stopped changing, by kind."""
        ready, now = {"download": [], "mail": []}, time.monotonic()
        for path, item in list(self.pending.items()):
            try:
                size = os.path.getsize(path)
            except OSError:
                del self.pending[path]
                continue
            if size != item[0]:
                item[0], item[1] = size, now
            elif now - item[1] >= SETTLE:
                ready[item[2]].append(path)
                del self.pending[path]
        return ready

    def mail_ready(self, paths, check):
        for path in paths:
            for data in self.inbox.new_mail(path):
                if check:
                    mail.check(mail.parse(data), os.path.basename(os.path.dirname(path)))
        self.inbox.save()

    def loop(self, run_for=0):
        end = time.monotonic() + run_for if run_for else 0
        looked = time.monotonic()
        while not end or time.monotonic() < end:
            select.select([self.ino.fd], [], [], 0.5)
            for folder, name, mask in self.ino.read():
                if mask & inotify.OVERFLOW:
                    for path in self.inbox.state["files"]:
                        self.pending[path] = [-1, time.monotonic(), "mail"]
                else:
                    self.note(folder, name, mask)
            ready = self.settle()
            if ready["download"] or ready["mail"]:
                on = settings()
                if ready["download"] and on["downloads"]:
                    handle_downloads(ready["download"])
                if ready["mail"]:
                    self.mail_ready(ready["mail"], on["email"])
            if time.monotonic() - looked > 60:
                looked = time.monotonic()
                self.look_around()
        return 0


def main(run_for=0):
    try:
        w = Watcher()
    except OSError as err:
        print("Always-On Guard could not start: %s" % err)
        return 1
    print("Always-On Guard is watching %d folders." % len(w.ino.paths), flush=True)
    return w.loop(run_for)

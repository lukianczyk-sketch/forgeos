"""The judge: is this program scrambling your files?

Only programs that are not trusted are counted. Each app remembers the files it wrote, so "Put my
files back" knows exactly which files to bring back.
Sets it off: a bait file written, 20 scrambled files in 10 seconds, 150 in 10 minutes, or a
ransom note plus 5 scrambled files.
"""
import os

from . import FAST, NOTE_WITH, SLOW, procs

KEEP = 20000  # files remembered per app (enough to put back a big attack)


class App:
    def __init__(self, info):
        self.info = info
        self.writes = []  # [(time, path, verdict)], oldest first
        self.files = {}  # every file it wrote while watched, in order (path -> time)
        self.fired = False
        self.first = 0.0  # when its first scrambled (or bait) write happened: the attack started then
        self.began = 0.0  # its first write we saw

    def count(self, t, secs, verdict="scrambled"):
        return sum(1 for w in self.writes if w[2] == verdict and w[0] > t - secs)


class Detector:
    def __init__(self, allowed=(), listed=()):
        self.apps = {}
        self.allowed, self.listed = list(allowed), set(listed)
        self._trust = {}

    def trusted(self, info):
        k = (info.get("exe", ""), info.get("pid", 0))
        if k not in self._trust:
            self._trust[k] = procs.trusted(info, self.allowed, self.listed)
        return self._trust[k]

    def event(self, t, info, path, verdict):
        """One finished write. Returns (app, reason) when the tripwire goes off, else None."""
        if not info or self.trusted(info):
            return None
        k = procs.key(info)
        app = self.apps.setdefault(k, App(info))
        app.writes = [w for w in app.writes if w[0] > t - SLOW[1]] + [(t, path, verdict)]
        app.began = app.began or t
        if verdict in ("scrambled", "bait", "note") and not app.first:
            app.first = t
        if len(app.files) < KEEP:
            app.files.setdefault(path, t)
        if app.fired:
            return None
        reason = ""
        fast, slow, notes = app.count(t, FAST[1]), app.count(t, SLOW[1]), app.count(t, SLOW[1], "note")
        if verdict == "bait":
            reason = "It changed one of ForgeOS's safety files (a file nobody should ever touch)."
        elif fast >= FAST[0]:
            reason = "It scrambled %d files in %d seconds." % (fast, FAST[1])
        elif slow >= SLOW[0]:
            reason = "It scrambled %d files in the last 10 minutes." % slow
        elif notes and slow >= NOTE_WITH:
            note = next(w[1] for w in reversed(app.writes) if w[2] == "note")
            reason = "It left a ransom note (%s) and scrambled %d files." % (os.path.basename(note), slow)
        if not reason:
            return None
        app.fired = True
        return app, reason

    def gone(self, t, path, within=60, least=3):
        """A bait file was deleted or renamed. The untrusted app that scrambled the most files in the last
        minute did it (None = nobody was scrambling: probably you, by hand, e.g. deleting a whole folder)."""
        best, most = None, least - 1
        for app in self.apps.values():
            n = app.count(t, within) + app.count(t, within, "note")
            if n > most and not app.fired:
                best, most = app, n
        if best is None:
            return None
        best.fired = True
        best.files.setdefault(path, t)
        return best, "It deleted or renamed one of ForgeOS's safety files (%s)." % os.path.basename(path)

    def tidy(self, t):
        """Forget quiet apps (nothing written for 10 minutes) so memory stays small."""
        for k, a in list(self.apps.items()):
            if not a.fired and (not a.writes or a.writes[-1][0] < t - SLOW[1]):
                del self.apps[k]
        if len(self._trust) > 5000:
            self._trust.clear()

    def forget(self, app):
        """After it was handled (released by you): start counting from zero."""
        for k, a in list(self.apps.items()):
            if a is app:
                del self.apps[k]
        self._trust.clear()

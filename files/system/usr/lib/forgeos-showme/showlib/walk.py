"""The step-by-step walk: which step we are on, where to point, and when to move on.

Every 2 seconds it is given what is on the screen. It moves on BY ITSELF when the next step's words show up
in a NEW place (not where they already were when this step began), or when this step's words are gone
because the person clicked them. Back / Next always work too. Our own words (the panel) never count.
It never points with confidence at something it cannot see.
"""
from . import STUCK, clean, norm
from .guides import PLACES, WHERE
from .screen import find_all

WAIT = 10  # seconds to wait for a window to open before saying "I can't see it"


def near(a, b):
    return abs(a[0] - b[0]) < 0.02 and abs(a[1] - b[1]) < 0.02


class Walk:
    def __init__(self, steps, t, more=None):
        """steps: the guide's steps; more(screen, steps) gives the next step from the AI (or None, or "done")."""
        self.steps, self.more, self.i = list(steps), more, 0
        self.end = ""   # "done", "stuck", "unsure" or "stopped" once the walk is over
        self.begin(t)

    def begin(self, t):
        self.seen, self.missing, self.box, self.old, self.gone, self.hint = False, 0, None, None, 0, None
        self.progress = self.started = t

    def ours(self):
        """Everything Show Me How itself shows (step panel, label), in compare form."""
        return norm(" ".join(s["say"] + " " + s["arg"] for s in self.steps) + " step of i can t see on your screen"
                    " the steps in writing you do the clicking show me how only points")

    def step(self):
        return self.steps[self.i] if 0 <= self.i < len(self.steps) else None

    def go(self, d, t):
        """Next (+1) or Back (-1). Next on the last step = done (unless the AI has more)."""
        self.i = max(0, self.i + d)
        if self.i >= len(self.steps) and not self.more:
            self.end = "done"
        self.begin(t)

    def again(self, t):
        """Try again (the thing could not be seen)."""
        self.begin(t)

    def tick(self, screen, avoid, t):
        """What to show now, as a dict for the overlay and the step panel."""
        if not self.end and t - self.progress > STUCK:
            self.end = "stuck"
        s = self.step()
        if not self.end and s is None and self.more and screen:
            s = self.more(screen, self.steps)
            if s == "done":
                self.end = "done"
            elif not s:
                self.end = "unsure"
            else:
                self.steps.append(s)
        if self.end:
            return self.view("end")
        if s is None:
            return self.view("look")
        last = self.i == len(self.steps) - 1
        nxt = self.steps[self.i + 1] if not last and self.steps[self.i + 1]["kind"] == "word" else None
        if screen is not None:
            ours = self.ours()
            boxes = find_all(screen, s["arg"], avoid, ours) if s["kind"] == "word" else []
            box = next((b for b in boxes if self.hint and near(b, self.hint)), boxes[0] if boxes else None)
            nboxes = find_all(screen, nxt["arg"], avoid, ours) if nxt else []
            self.gone = 0 if nboxes else self.gone + 1
            if self.old is None or self.gone >= 2:
                self.old = nboxes  # where the next words already were (or they went away for 2 looks)
            if box:
                if not self.seen:
                    self.progress = t
                self.seen, self.missing, self.box = True, 0, box
            elif s["kind"] == "word":
                self.missing += 1
            new = [b for b in nboxes if not any(near(b, o) for o in self.old)]
            if new or (nboxes and self.seen and self.missing >= 1):
                self.go(1, t)
                self.hint = (new or nboxes)[0]  # point at the one that just showed up
                return self.tick(screen, avoid, t)
            if s["kind"] == "word" and self.seen and self.missing >= (3 if last else 2) and (last or self.more):
                self.go(1, t)
                if not self.end:
                    return self.tick(screen, avoid, t)
                return self.view("end")
        if s["kind"] == "place":
            x, y = PLACES[s["arg"]]
            self.box = (x - 0.025, y - 0.025, 0.05, 0.05)
            return self.view("point", "%s (%s)" % (s["say"], WHERE[s["arg"]]))
        if s["kind"] != "word":
            return self.view("say")
        if self.box and self.missing < 2:
            return self.view("point")
        if (self.seen and self.missing >= 3) or (screen is not None and self.missing >= 2 and t - self.started >= WAIT):
            return self.view("lost", "I can't see \"%s\" on your screen." % clean(s["arg"], 40))
        return self.view("look")

    def view(self, mode, say=None):
        s = self.step() or {"say": "", "kind": "say", "arg": ""}
        v = {"mode": mode, "show": mode == "point", "step": min(self.i + 1, max(1, len(self.steps))),
             "say": clean(say or s["say"], 120), "total": len(self.steps) if not self.more else 0,
             "end": self.end, "kind": s["kind"], "target": clean(s["arg"], 40)}
        if mode == "point" and self.box:
            v.update(x=round(self.box[0], 4), y=round(self.box[1], 4), w=round(self.box[2], 4), h=round(self.box[3], 4))
            v["corner"] = ("r" if v["x"] + v["w"] / 2 < 0.5 else "l") + ("b" if v["y"] + v["h"] / 2 < 0.5 else "t")
        else:
            v["corner"] = "rb"
        return v

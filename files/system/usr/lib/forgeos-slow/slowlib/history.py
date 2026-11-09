"""The slow history: a tiny sample every 5 minutes (user timer), kept on this PC for 7 days.

So when the slowness is already gone, it can still say what happened ("At 2:10 pm Brave used all the
memory"). Each sample is one short line; 7 days is about 2,000 lines.
"""
import json
import os
import time

from . import HISTORY, meminfo, now, pressure, size_words
from . import hot, procs

KEEP_DAYS = 7


def sample():
    apps = [a for a in procs.apps(procs.table()) if not a["keep"]]
    total, avail = meminfo()
    top = apps[0] if apps else None
    big = max(apps, key=lambda a: a["rss"], default=None)
    s = {"t": int(now()), "cpu": pressure("cpu").get("some60", 0), "mem": pressure("memory").get("some60", 0),
         "io": pressure("io").get("some60", 0), "free": round(avail * 100.0 / total, 1) if total else 100,
         "top": [top["name"], round(top["cpu"])] if top else ["", 0],
         "big": [big["name"], big["rss"]] if big else ["", 0], "temp": hot.temperature() or 0}
    old = load(KEEP_DAYS * 86400)
    os.makedirs(os.path.dirname(HISTORY), exist_ok=True)
    with open(HISTORY + ".new", "w", encoding="utf-8") as f:
        for x in old + [s]:
            f.write(json.dumps(x, sort_keys=True) + "\n")
    os.replace(HISTORY + ".new", HISTORY)
    return s


def load(secs):
    """Samples from the last `secs` seconds, oldest first."""
    out = []
    try:
        with open(HISTORY, encoding="utf-8") as f:
            for line in f:
                try:
                    x = json.loads(line)
                except ValueError:
                    continue
                ok = isinstance(x, dict) and isinstance(x.get("t"), int) and all(
                    isinstance(x.get(k), list) and len(x[k]) == 2 for k in ("top", "big"))
                if ok and x["t"] >= now() - secs:
                    out.append(x)
    except OSError:
        pass
    return out


def cause(s):
    """The plain-English reason one sample was slow, or "" when it was not."""
    if s.get("mem", 0) >= 10 or s.get("free", 100) < 5:
        return "the memory was nearly full (%s was using %s)" % (s["big"][0], size_words(s["big"][1]))
    if s.get("temp", 0) >= 90:
        return "the PC was too hot (%d degrees C) and slowed itself down" % s["temp"]
    if s.get("cpu", 0) >= 40 or s.get("top", ["", 0])[1] >= 200:
        return "%s was using most of the computer's power" % s["top"][0]
    if s.get("io", 0) >= 30:
        return "the PC kept waiting for the drive"
    return ""


def clock(t):
    return time.strftime("%I:%M %p", time.localtime(t)).lstrip("0").lower()


def then(minutes=30):
    """What slowed the PC in the last `minutes`, as one or two sentences."""
    slow = [(s, cause(s)) for s in load(minutes * 60)]
    slow = [(s, c) for s, c in slow if c]
    if not slow:
        return "Nothing was slowing the PC in the last %d minutes." % minutes
    s, c = slow[-1]
    more = " It happened %d times in the last %d minutes." % (len(slow), minutes) if len(slow) > 1 else ""
    return "At %s %s.%s" % (clock(s["t"]), c, more)


def quick():
    """(True, sentence) when the PC has been slow for the last 15 minutes for the same reason."""
    last = load(16 * 60)[-3:]
    causes = [cause(s) for s in last]
    if len(last) < 3 or not causes[-1] or any(c.split(" ")[:3] != causes[-1].split(" ")[:3] for c in causes):
        return False, ""
    return True, "Your PC has been slow for 15 minutes because %s." % causes[-1]

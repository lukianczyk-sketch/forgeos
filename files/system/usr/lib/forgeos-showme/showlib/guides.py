"""Show Me How guides: one small text file each in /usr/share/forgeos/showme/guides/NAME.txt (NAME = the
Forge Helper help card it shows). Format:

  # Title
  words: other words people use for it
  open: settings MODULE | app DESKTOP-ID | window FORGEOS-WINDOW | none
  step: word WORDS ON THE SCREEN | What to say.
  step: place tray|menu|desktop|top-right | What to say.
  step: key Ctrl+P | What to say.
  step: say | What to say.

"word" points at those words when they are really on the screen. "place" points at a part of the screen
with no words (the taskbar icons). "key" and "say" only show the sentence.
"""
import os
import re

from . import GUIDES, norm

PLACES = {"tray": (0.93, 0.975), "menu": (0.02, 0.975), "desktop": (0.5, 0.45), "top-right": (0.97, 0.03)}
WHERE = {"tray": "bottom right", "menu": "bottom left", "desktop": "middle of the screen", "top-right": "top right"}
SETTINGS = set("""kcm_printer_manager kcm_networkmanagement kcm_bluetooth kcm_kscreen kcm_lookandfeel kcm_colors
kcm_nightlight kcm_pulseaudio kcm_clock kcm_users kcm_screenlocker kcm_wallpaper""".split())
WINDOWS = set("forgeos-switch-gui forgeos-autopilot-gui forgeos-family-gui".split())
# the Show Me How menu lists the most-used guides first
ORDER = """print wifi sound bigger-text video-call email screenshot add-printer bluetooth microphone webcam
usb-stick install-app uninstall-app backup updates scan wallpaper dark-mode night-light date-time
user-password lock-screen windows-forgeos""".split()
STOP = set("""a an the my me i to do how can could you show where is it on in of for and or with this that
please want need help make get set up use using way computer pc forgeos change turn open new start go""".split())


def stem(w):
    for end in ("ing", "ers", "ies", "ed", "es", "er", "s"):
        if len(w) > len(end) + 2 and w.endswith(end):
            return w[:-len(end)] + ("y" if end == "ies" else "")
    return w


def words(text):
    return set(stem(w) for w in norm(text).split() if w not in STOP)


def parse(name, text):
    """A guide as a dict; ValueError(reason) when a line is wrong."""
    lines = [x.rstrip() for x in text.splitlines() if x.strip()]
    if not lines or not lines[0].startswith("# "):
        raise ValueError("line 1 must be '# Title'")
    g = {"name": name, "title": lines[0][2:].strip(), "words": "", "open": ("none", ""), "steps": []}
    for line in lines[1:]:
        key, _, rest = line.partition(":")
        rest = rest.strip()
        if key == "words":
            g["words"] = rest
        elif key == "open":
            kind, _, arg = rest.partition(" ")
            g["open"] = (kind, arg.strip())
        elif key == "step":
            what, bar, say = rest.partition("|")
            kind, _, arg = what.strip().partition(" ")
            if not bar or not say.strip():
                raise ValueError("a step needs '| what to say': " + line)
            g["steps"].append({"kind": kind, "arg": arg.strip(), "say": say.strip()})
        else:
            raise ValueError("unknown line: " + line)
    return g


def load(name):
    """The guide called NAME, or None (no such guide, or it is broken)."""
    if not re.fullmatch(r"[a-z0-9-]{1,40}", name or ""):
        return None
    try:
        with open(os.path.join(GUIDES, name + ".txt"), encoding="utf-8") as f:
            return parse(name, f.read())
    except (OSError, ValueError):
        return None


def names():
    try:
        found = [n[:-4] for n in os.listdir(GUIDES) if n.endswith(".txt")]
    except OSError:
        return []
    return sorted(found, key=lambda n: (ORDER.index(n) if n in ORDER else len(ORDER), n))


def problems(name):
    """What is wrong with a guide ([] = good). Used by 'forgeos-showme check'."""
    try:
        with open(os.path.join(GUIDES, name + ".txt"), encoding="utf-8") as f:
            g = parse(name, f.read())
    except OSError:
        return ["there is no guide called %s" % name]
    except ValueError as e:
        return [str(e)]
    bad = []
    kind, arg = g["open"]
    if kind == "settings" and arg not in SETTINGS:
        bad.append("unknown settings page: " + arg)
    elif kind == "window" and arg not in WINDOWS:
        bad.append("unknown ForgeOS window: " + arg)
    elif kind == "app" and not re.fullmatch(r"[A-Za-z0-9._-]+", arg):
        bad.append("bad app name: " + arg)
    elif kind not in ("settings", "window", "app", "none"):
        bad.append("open must be settings, app, window or none")
    if not 1 <= len(g["steps"]) <= 8:
        bad.append("a guide needs 1 to 8 steps")
    for s in g["steps"]:
        if s["kind"] not in ("word", "place", "key", "say"):
            bad.append("unknown step kind: " + s["kind"])
        elif s["kind"] == "word" and len(norm(s["arg"])) < 2:
            bad.append("a word step needs the words to look for")
        elif s["kind"] == "place" and s["arg"] not in PLACES:
            bad.append("unknown place: " + s["arg"])
        if len(s["say"]) > 90:
            bad.append("say it shorter (90 letters at most): " + s["say"])
    if not g["words"]:
        bad.append("the words: line is missing")
    return bad


def best(question):
    """The guide that fits QUESTION best, or None. Title words count 3, the words: line 2."""
    q = words(question)
    top, pick = 0, None
    for n in names():
        g = load(n)
        if not g:
            continue
        title, extra = words(g["title"]), words(g["words"]) | words(n.replace("-", " "))
        score = 3 * len(q & title) + 2 * len(q & (extra - title))
        if score > top:
            top, pick = score, g
    return pick if top >= 3 else None

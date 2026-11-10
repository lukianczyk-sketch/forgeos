"""forgeos-showme commands. Exit: 0 done / found, 1 could not find or finish, 3 wrong use.

  list                         every guide: GUIDE<TAB>name<TAB>title (most used first)
  find WORDS                   the guide that fits: GUIDE<TAB>name<TAB>title
  guide NAME [--no-draw]       walk through a guide (--no-draw: no arrow, one VIEW line per look)
  ask QUESTION [--no-draw]     the best guide, or the private AI pointing only at words really on the screen
  check NAME|all               test guide files without drawing
  written NAME                 the steps in writing
"""
import shutil
import sys

from . import clean, now, start
from . import ai, guides, session
from .walk import Walk


def usage():
    print(__doc__.split("\n\n", 1)[1].rstrip(), file=sys.stderr)
    return 3


NO = ("scam_check", "tech_support", "ransomware", "panic", "cleansweep_scan", "find_my_pc", "family_call")
NO_TEXT = ("This sounds like a scam, a stranger in your PC or an emergency, so Show Me How won't walk you through"
           " it. Ask Forge Helper (Meta+H): it has the right tool for this. Never let a caller tell you what to click.")


def walk(w, guide, card, draw):
    if not (shutil.which("spectacle") and shutil.which("tesseract")):
        print("Show Me How can't read the screen on this PC. Here are the steps:\n" + session.written(guide, card))
        return 1
    if not draw:
        return session.plain(w, guide, card)
    try:
        from . import show
        return show.draw(w, guide, card)
    except Exception:  # noqa: BLE001 - no D-Bus / no desktop: still give the steps in writing
        print("Show Me How needs the desktop (D-Bus). Here are the steps:\n" + session.written(guide, card))
        return 1


def danger(question):
    """True when Forge Helper's rules say this is a scam, a stranger or an emergency (its tools handle those)."""
    h = ai.helper()
    try:
        from helperlib import rules
        hit = rules.match(question) if h else None
    except ImportError:
        hit = None
    return bool(hit) and hit[0] in NO


def ask(question, draw):
    if danger(question):
        print(NO_TEXT)
        if draw:
            start(["kdialog", "--title", "Show Me How", "--sorry", NO_TEXT])
        return 1
    g = guides.best(question)
    if g:
        return walk(Walk(g["steps"], now()), g, None, draw)
    card = ai.card(question)
    if ai.model():
        w = Walk([], now(), more=lambda screen, done: ai.next_step(question, screen, done))
        return walk(w, None, card, draw)
    text = "I don't have a guide for that yet, and the private AI is not set up.\n\n" + session.written(None, card)
    print(text)
    if draw:
        start(["kdialog", "--title", "Show Me How", "--msgbox", text])
    return 1


def check(names):
    bad = 0
    for n in names:
        found = guides.problems(n)
        print("OK %s" % n if not found else "BAD %s: %s" % (n, "; ".join(found)))
        bad += bool(found)
    return 1 if bad or not names else 0


def main(args):
    draw = "--no-draw" not in args
    args = [a for a in args if a != "--no-draw"]
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    if cmd == "list" and not rest:
        for n in guides.names():
            g = guides.load(n)
            if g:
                print("GUIDE\t%s\t%s" % (n, g["title"]))
        return 0
    if cmd == "find" and rest:
        g = guides.best(" ".join(rest))
        if g:
            print("GUIDE\t%s\t%s" % (g["name"], g["title"]))
        return 0 if g else 1
    if cmd == "check" and len(rest) == 1:
        return check(guides.names() if rest[0] == "all" else rest)
    if cmd in ("guide", "written") and len(rest) == 1:
        g = guides.load(rest[0])
        if not g:
            print("There is no guide called \"%s\". See: forgeos-showme list" % clean(rest[0], 40), file=sys.stderr)
            return 1
        if cmd == "written":
            print("%s\n%s" % (g["title"], session.written(g)))
            return 0
        return walk(Walk(g["steps"], now()), g, None, draw)
    if cmd == "ask" and rest:
        q = clean(" ".join(rest), 300)
        return ask(q, draw) if q else usage()
    return usage()

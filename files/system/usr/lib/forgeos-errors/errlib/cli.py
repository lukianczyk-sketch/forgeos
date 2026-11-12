"""forgeos-errors: the commands (the window, the watcher and Forge Helper use them)."""
import os
import sys
import time

from . import APP, ENV, LEVELS, clean, data_dir, load_json, now, run, save_json, start
from . import explain, fixes, history, library, watch

USAGE = ("usage: forgeos-errors explain TEXT|- | this | screen | copied | card KEY | recent [DAYS] |\n"
         "       fix FIX --yes | fixed KEY | check | watch | tick | pop KEY | notice APP TITLE TEXT")
NOT_UNDERSTOOD = ("I could not read an error there. Copy the error's words (select them, Ctrl+C) and press"
                  " Meta+Shift+E again, or ask Forge Helper.")


def show(card, src, text):
    """Write the card down and print it. Exit 0."""
    e, _ = history.record(card, src, text)
    print("\n".join(explain.lines(card, e["key"])))
    return 0


def explain_text(text, src):
    card = explain.explain(text)
    if not card:
        print(NOT_UNDERSTOOD)
        return 1
    return show(card, src, text)


def screen_text():
    """The words on the screen right now (Show Me How's quiet screenshot + Tesseract), or ""."""
    sys.path.insert(0, ENV("FORGEOS_SHOWME_LIB") or "/usr/lib/forgeos-showme")
    try:
        from showlib import screen
    except ImportError:
        return ""
    got = screen.look()
    return "\n".join(line["text"] for line in got[2]) if got else ""


def copied_text():
    """What you copied, or "" (a password copied from a password manager is never read)."""
    code, types = run(["wl-paste", "--list-types"], 10)
    if code != 0 or "x-kde-passwordManagerHint" in types:
        return ""
    code, out = run(["wl-paste", "--no-newline", "--type", "text"], 10)
    return out if code == 0 else ""


def this():
    """Meta+Shift+E: an error or scam you just copied (a known one, new since last time), else the screen."""
    clip, state_file = clean(copied_text(), 4000), os.path.join(data_dir(), "copied.json")
    state = load_json(state_file, {})
    if len(clip) >= 3 and clip != state.get("last") and explain.explain(clip, False):
        state["last"] = clip
        save_json(state_file, state)
        return explain_text(clip, "copied")
    text = screen_text()
    if not text:
        print("I could not read the screen. " + NOT_UNDERSTOOD)
        return 1
    return explain_text(text, "screen")


def card(key):
    e = history.find(key)
    if not e:
        print("That error is no longer in the history.")
        return 1
    print("\n".join(explain.lines(e, key)))
    return 0


def recent(days):
    items = [e for e in history.load() if e["last"] >= now() - days * 86400]
    if not items:
        print("Nothing went wrong in the last %d days." % days)
    for e in reversed(items):
        when = time.strftime("%a %b %d %I:%M %p", time.localtime(e["last"]))
        times = " (%d times)" % e["count"] if e["count"] > 1 else ""
        print("ITEM\t%s\t%s\t%s\t%s\t%s" % (e["key"], when, e.get("level", "yellow"), clean(e.get("title", "?"), 80)
                                          + times, "fixed" if e.get("fixed") else "-"))
    return 0


def pop(key):
    """The pop-up for one history entry; a click on "What does this mean?" opens its card."""
    e = history.find(key)
    if not e:
        return 1
    words = e.get("say") or "Want to know what it means and what to do?"
    code, out = run(["notify-send", "-a", APP, "-i", "dialog-information" if e["level"] != "red" else "dialog-warning",
                     "-u", "critical" if e["level"] == "red" else "normal", "--action=open=What does this mean?",
                     "--wait", e.get("title", "An error"), "%s %s" % (words, LEVELS.get(e["level"], ""))], 3600)
    if code == 0 and out.strip() == "open":
        start(["forgeos-errors-gui", "--card", key])
    return 0


def check():
    try:
        entries = library.load()
    except (ValueError, OSError) as err:
        print("The error library has a bad file: %s" % err)
        return 1
    bad = library.problems(entries)
    for b in bad:
        print("PROBLEM\t" + b)
    print("%d errors in the library, %d examples, %s." % (len(entries), sum(len(e["example"]) for e in entries),
                                                       "all good" if not bad else "%d problems" % len(bad)))
    return 1 if bad or not entries else 0


def main(argv):
    cmd, rest = (argv[0], argv[1:]) if argv else ("", [])
    if cmd == "explain" and len(rest) == 1:
        return explain_text(sys.stdin.read() if rest[0] == "-" else rest[0], "asked")
    if cmd in ("this", "screen", "copied", "check", "watch", "tick") and not rest:
        if cmd == "screen":
            return explain_text(screen_text(), "screen")
        if cmd == "copied":
            return explain_text(copied_text(), "copied")
        if cmd == "tick":
            watch.tick()
            return 0
        return {"this": this, "check": check, "watch": watch.watch}[cmd]()
    if cmd in ("card", "fixed", "pop") and len(rest) == 1:
        if cmd == "fixed":
            return 0 if history.mark_fixed(rest[0]) else 1
        return card(rest[0]) if cmd == "card" else pop(rest[0])
    if cmd == "recent" and len(rest) <= 1 and (not rest or rest[0].isdigit()):
        return recent(int(rest[0]) if rest else 30)
    if cmd == "fix" and len(rest) == 2 and rest[1] == "--yes":
        code, msg = fixes.do(rest[0])
        print(msg)
        return code
    if cmd == "notice" and len(rest) == 3:
        return 0 if watch.notice(*rest) else 1
    print(USAGE, file=sys.stderr)
    return 3

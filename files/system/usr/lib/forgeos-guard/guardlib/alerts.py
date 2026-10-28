"""Warnings on screen: a big window for a virus, a pop-up for risky files and scam emails.

Nothing here waits: windows open on their own, so the guard keeps watching.
Email pop-ups: at most one a minute; the rest are counted into the next one.
"""
import subprocess
import time

from . import ENV, GUI

QUIET = int(ENV("FORGEOS_GUARD_QUIET") or 60)
_last = {"email": 0.0}
_held = {"email": 0}


def start(cmd):
    try:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def popup(title, text, urgent=False, eid=""):
    """notify-send pop-up; with an event id it gets a "Show why" button that opens the guard window."""
    cmd = ["notify-send", "--app-name=Always-On Guard", "--icon=security-high",
           "--urgency=" + ("critical" if urgent else "normal"), title, text]
    if not eid:
        return start(cmd)
    show = " ".join("'%s'" % x.replace("'", "'\\''") for x in [GUI, "--why", eid])
    line = " ".join("'%s'" % x.replace("'", "'\\''") for x in cmd)
    return start(["sh", "-c", 'a=$(%s --action=why="Show why" --wait) && [ "$a" = why ] && exec %s' % (line, show)])


def big_window(title, text):
    return start(["kdialog", "--title", title, "--sorry", text])


def virus(where, name, virus_name):
    big_window("Always-On Guard - virus stopped",
               "STOP - this %s had a virus.\n\nForgeOS locked it away so it can't hurt your computer.\n\n"
               "File: %s\nVirus: %s\n\nYou don't need to do anything. Never open it again from where it came from."
               % (where, name, virus_name))
    popup("Virus stopped", "%s was locked away (%s)." % (name, virus_name), urgent=True)


def risky(name, why, eid=""):
    popup("Be careful with this file", "%s is %s. Programs from emails and websites are the #1 way scammers "
          "get in. Check it with Will It Run? before you open it." % (name, why), eid=eid)


def email(level, sender, subject, eid=""):
    """level 2 = looks like a scam, 1 = be careful. Returns False if it was held back (too many at once)."""
    now = time.monotonic()
    if _last["email"] and now - _last["email"] < QUIET:
        _held["email"] += 1
        return False
    more = _held["email"]
    _last["email"], _held["email"] = now, 0
    head = "Scam warning" if level >= 2 else "Be careful with this email"
    text = ('The email from %s about "%s" %s. Don\'t click its links or open its files.'
            % (sender, subject, "looks like a scam" if level >= 2 else "has warning signs"))
    if more:
        text += " (+%d more warning%s - see Always-On Guard)" % (more, "s" if more > 1 else "")
    return popup(head, text, urgent=level >= 2, eid=eid)

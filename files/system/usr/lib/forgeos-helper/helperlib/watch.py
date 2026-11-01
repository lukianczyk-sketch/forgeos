"""Speaks up first: every 15 minutes (quiet, low priority) look for problems and offer ONE fix.

At most 3 notes a day, never while a game or video is playing, the same topic at most once a day,
"Not now" snoozes that topic for 3 days. Clicking the fix button is the user's Yes.
Every note is written to ~/.local/state/forgeos/helper-watch.log.
"""
import os
import time

from . import actions, append_line, read_json, run, state_dir, write_json
from .checks import check_backup, check_disk, check_guard, check_health, check_hog, check_update

PER_DAY = 3
SNOOZE = 3 * 86400
AGAIN = 86400


def state_file():
    return os.path.join(state_dir(), "helper-watch.json")


def log(text):
    append_line(os.path.join(state_dir(), "helper-watch.log"), time.strftime("%Y-%m-%d %H:%M ") + text)


def busy():
    """True while a game or a full-screen video is playing (they stop the screen saver)."""
    code, out = run(["busctl", "--user", "call", "org.freedesktop.PowerManagement.Inhibit",
                     "/org/freedesktop/PowerManagement/Inhibit", "org.freedesktop.PowerManagement.Inhibit",
                     "HasInhibit"], 10)
    if code == 0 and out.strip() == "b true":
        return True
    code, out = run(["gamemoded", "-s"], 10)
    if code == 0 and "is active" in out:
        return True
    return run(["pgrep", "-x", "gamescope"], 10)[0] == 0


def notify(text, label):
    """Show the note with two buttons. Returns 'fix', 'later' or '' (closed)."""
    code, out = run(["notify-send", "--app-name=Forge Helper", "--icon=help-browser", "--wait",
                     "--action=fix=" + label, "--action=later=Not now", "Forge Helper", text], 3600)
    return out.strip() if code == 0 else ""


def tick():
    st = read_json(state_file(), {})
    st = st if isinstance(st, dict) else {}
    today, now = time.strftime("%Y-%m-%d"), time.time()
    if st.get("day") != today:
        st.update(day=today, count=0)
    found = [check_disk(), check_update(), check_guard(st), check_health(), check_hog(), check_backup()]
    note = None
    for f in (x for x in found if x):
        topic = f[0]
        if st.get("snooze", {}).get(topic, 0) > now or st.get("seen", {}).get(topic, 0) > now - AGAIN:
            continue
        note = f
        break
    if not note or st["count"] >= PER_DAY or busy():
        write_json(state_file(), st)
        return 0
    topic, text, action, arg, label = note
    st["count"] += 1
    st.setdefault("seen", {})[topic] = now
    write_json(state_file(), st)
    log("shown %s: %s" % (topic, text))
    pick = notify(text, label)
    if pick == "fix":
        code, msg = actions.do(action, arg)
        log("fix %s: %s %s -> %d %s" % (topic, action, arg, code, msg.splitlines()[0] if msg else ""))
    elif pick == "later":
        st = read_json(state_file(), st)
        st.setdefault("snooze", {})[topic] = now + SNOOZE
        write_json(state_file(), st)
        log("snoozed %s for 3 days" % topic)
    return 0

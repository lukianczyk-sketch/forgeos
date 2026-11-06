"""Your session's side (forgeos-tripwire-alert.service): when the root watcher stopped a program that
was scrambling YOUR files, show the big window within about a second, add it to Always-On Guard's
warnings, and pop up a critical note (critical notes show even over full-screen games and videos).
"""
import os
import sys
import time

from . import GUARD_LIB, GUI, RUN, STATE, load_json, my_uid, save_json, start, incident


def guard_log(inc):
    """Always-On Guard's warnings list shows it too (kind 'ransomware')."""
    sys.path.insert(0, GUARD_LIB)
    try:
        from guardlib import log_event
        why = "%s\nProgram: %s\nFiles it touched: %d\n" % (inc["reason"], inc.get("exe") or "-", len(inc["files"]))
        log_event("ransomware", "tripwire", inc.get("exe") or inc.get("program") or "-", inc["reason"], inc["id"], why)
    except (ImportError, OSError, KeyError):
        pass
    finally:
        sys.path.remove(GUARD_LIB)


def notify(title, text, urgent):
    return start(["notify-send", "--app-name=Ransomware Tripwire", "--icon=security-low",
                  "--urgency=" + ("critical" if urgent else "normal"), title, text])


def show(inc):
    """What to show for one incident (it is shown once)."""
    guard_log(inc)
    if inc["kind"] == "attack":
        notify("A program was scrambling your files", "ForgeOS stopped %s and cut the internet. Your files can come "
               "back - see the Ransomware Tripwire window." % (inc.get("program") or "a program"), True)
        start([GUI, "--incident", inc["id"]])
    elif inc["kind"] == "bait":
        notify("A safety file was removed", "One of Ransomware Tripwire's hidden safety files was removed. If you "
               "did it, that's fine: it was put back. No program was stopped.", False)


def tick(full=True):
    """Show anything new (full = also every program still frozen). Returns the ids shown."""
    uid = my_uid()
    st = load_json(STATE)
    seen = st.get("shown", [])
    latest = load_json(os.path.join(RUN, "alert-%d" % uid)).get("id", "")
    want = ([latest] if latest else []) + ([i["id"] for i in incident.open_ones(uid)] if full else [])
    shown = []
    for iid in want:
        if iid in seen or iid in shown:
            continue
        inc = incident.load(iid)
        if inc and inc.get("uid") == uid:
            show(inc)
            shown.append(iid)
    if shown:
        st["shown"] = (seen + shown)[-100:]
        save_json(STATE, st, 0o600)
    return shown


def main(once=False):
    n = 0
    while True:
        for iid in tick(n % 60 == 0):
            print("SHOWN\t%s" % iid, flush=True)
        if once:
            return 0
        n += 1
        time.sleep(1)

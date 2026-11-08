"""Gentle reminders (the forgeos-digitalwill-remind timer, once a day, in your session):
- the envelope is 6 months old (then at most once a month): "update it?"
- your password safe changed after the envelope was made (once per change)
- you started your Digital Will a week ago but made no envelope yet (at most every 2 weeks)
A note with a button opens the Digital Will window. Never more than one note a day."""
import os

from . import DAY, GUI, OLD_AFTER, draft, now, read_state, run, start, write_state


def due():
    """(kind, text) of the reminder that is due, or None."""
    st, d, t = read_state(), draft.load(), now()
    if t - st.get("told", 0) < DAY - 600:
        return None
    if st.get("made"):
        if t - st["made"] >= OLD_AFTER and t - st.get("told_old", 0) >= 30 * DAY:
            months = int((t - st["made"]) // (30.4 * DAY))
            return "old", ("Your Digital Will is %d months old. Make a new Emergency Envelope so your family "
                           "has your newest passwords and wishes." % months)
        safe = st.get("safe") or ""
        try:
            changed = os.path.getmtime(safe) if safe else 0
        except OSError:
            changed = 0
        if changed > st.get("safe_mtime", 0) + 60 and st.get("told_safe") != changed:
            return "safe", ("Your password safe changed after your Emergency Envelope was made. Make a new "
                            "envelope so it has the newest copy.")
    elif d.get("started") and t - d["started"] >= 7 * DAY and t - st.get("told_unfinished", 0) >= 14 * DAY:
        return "unfinished", ("You started your Digital Will but have not made your Emergency Envelope yet. "
                              "It only takes a few minutes.")
    return None


def notify(text):
    code, out = run(["notify-send", "--app-name=Digital Will", "--icon=document-encrypt", "--wait",
                     "--action=go=Open Digital Will", "--action=later=Not now", "Digital Will", text], 3600)
    return code == 0 and out.strip() == "go"


def tick():
    """Show the reminder that is due (if any). Prints what it did. Exit 0 always."""
    hit = due()
    if not hit:
        print("Nothing to remind.")
        return 0
    kind, text = hit
    st, t = read_state(), now()
    st["told"] = t
    if kind == "old":
        st["told_old"] = t
    elif kind == "safe":
        st["told_safe"] = os.path.getmtime(st["safe"])
    else:
        st["told_unfinished"] = t
    write_state(st)
    print("Reminded: " + kind)
    if notify(text):
        start([GUI])
    return 0

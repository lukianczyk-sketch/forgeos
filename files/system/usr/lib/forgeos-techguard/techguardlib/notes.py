"""Notes for you: KDE notifications (critical ones show even over full-screen games and videos) and the
warnings list of Always-On Guard (kind 'techsupport').
"""
import sys

from . import GUARD_LIB, run


def guard_log(what, who, why):
    """Always-On Guard's warnings list (kind 'techsupport')."""
    sys.path.insert(0, GUARD_LIB)
    try:
        from guardlib import log_event
        log_event("techsupport", "techguard", who, what, "", why)
    except (ImportError, OSError):
        pass
    finally:
        sys.path.remove(GUARD_LIB)


def notify(title, text, urgent=True):
    code, out = run(["notify-send", "--app-name=Fake Tech Support Guard", "--icon=security-low", "--print-id",
                     "--urgency=" + ("critical" if urgent else "normal"), title, text], 10)
    return out.strip() if code == 0 and out.strip().isdigit() else ""


def close_note(nid):
    if nid and nid != "-":
        run(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path",
             "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.CloseNotification", nid], 10)

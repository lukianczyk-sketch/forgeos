"""What your phone can ask (root side). A command only counts when it opens with the key, is for this
direction, is less than 13 hours old, and is newer than the last one (an old one can never be played back).
  lost / found / ring / message / lock / shutdown / ping (the phone page's test button)
"""
import os
import time

from . import (ALERT, HOSTS, KEYFILE, MONEY, STATE, STATUS, TRAIL, clean, load_json, now, remove, run,
               save_json, settings)

COMMANDS = ("lost", "found", "ring", "message", "lock", "shutdown", "ping")
WIFI_NAME = "ForgeOS-FindMyPC"
OLDEST = 13 * 3600   # the relay keeps messages 12 hours
AHEAD = 300          # a phone clock may be up to 5 minutes ahead
MONEY_MARK = "# >>> ForgeOS Fake Tech Support Guard: money websites locked"


def key_info():
    """{"key", "made", "photo"} or {} when Find My PC is not set up."""
    from .seal import good_key
    k = load_json(KEYFILE)
    return k if good_key(k.get("key")) else {}


def state():
    return load_json(STATE)


def save_state(st):
    save_json(STATE, st, 0o600)


def trail():
    return load_json(TRAIL, [])


def write_status(st=None):
    """The no-secrets status the window and Forge Helper read (644)."""
    st = state() if st is None else st
    k, tr = key_info(), trail()
    save_json(STATUS, {"setup": bool(k), "made": k.get("made", 0), "photo": bool(k.get("photo")),
                       "lost": st.get("lost", 0) if k else 0, "heard": st.get("heard", 0),
                       "last_cmd": st.get("last_cmd", ""), "reports": len(tr),
                       "last_report": tr[-1]["t"] if tr else 0, "relay": settings()["relay"],
                       "checked": st.get("checked", 0)}, 0o644)


def clear_alerts():
    """Lost mode is over: an old "lost" or "message" must not show to the next person who signs in."""
    keep = [a for a in load_json(ALERT).get("list", []) if isinstance(a, dict) and a.get("kind") not in ("lost", "message")]
    save_json(ALERT, {"list": keep}, 0o644)


def alert(kind, text=""):
    """Tell every signed-in session (forgeos-locate alert-watch shows it)."""
    a = {"id": "%d-%s" % (int(now() * 1000), os.urandom(3).hex()), "kind": kind, "text": clean(text, 200),
         "t": now()}
    save_json(ALERT, {"list": load_json(ALERT).get("list", [])[-4:] + [a]}, 0o644)


def check(st, obj):
    """None when the command may run, else why not."""
    c, t = obj.get("c"), obj.get("t")
    if c not in COMMANDS or not isinstance(t, int) or isinstance(t, bool):
        return "not a command"
    sent = t / 1000.0
    if sent < now() - OLDEST:
        return "too old"
    if sent > now() + AHEAD:
        return "clock"
    if t <= st.get("last_t", 0):
        return "already done"
    return None


def money_locked():
    try:
        with open(HOSTS, encoding="utf-8", errors="replace") as f:
            return MONEY_MARK in f.read()
    except OSError:
        return False


def money(lock):
    """Money websites locked for the whole PC while lost (the Fake Tech Support Guard's lock)."""
    return run([MONEY, "root-money", "lock" if lock else "unlock"], 60)[0] == 0


def end_lost(st):
    """Lost mode over (Found it, set up again, off): money websites open again - only if Find My PC locked
    them - old alerts cleared, the joined Wi-Fi forgotten."""
    if st.get("lost") and not st.get("money_was"):
        money(False)
    for k in ("lost", "money_was", "next_report", "next_photo", "next_bell"):
        st.pop(k, None)
    clear_alerts()
    forget_wifi(st)


def forget_wifi(st):
    if st.pop("joined", False):
        run(["nmcli", "connection", "delete", WIFI_NAME], 30)


def do(st, obj):
    """Run one checked command. Returns (answer for the phone, power off after the answer)."""
    c, t = obj["c"], now()
    st["last_t"], st["heard"], st["last_cmd"], st["fast_until"] = obj["t"], t, c, t + 15 * 60
    if c == "lost":
        if not st.get("lost"):
            st["money_was"] = money_locked()
            st["lost"], st["next_report"], st["next_photo"], st["next_bell"] = t, 0, 0, 0
            alert("lost")
        locked = money(True)
        return "Lost mode is ON. Money websites are %s." % ("locked" if locked else "NOT locked"), False
    if c == "found":
        was = st.get("lost", 0)
        end_lost(st)
        remove(TRAIL)
        if was:
            alert("found")
        return "Lost mode is OFF. The reports were wiped from the PC.", False
    if c == "ring":
        alert("ring")
        return "Ringing for 2 minutes.", False
    if c == "message":
        text = clean(obj.get("text") or "This PC is lost. Please call the owner.", 200)
        alert("message", text)
        return "Message shown: " + text, False
    if c == "lock":
        code = run(["loginctl", "lock-sessions"], 30)[0]
        return "Screen locked." if code == 0 else "Could not lock the screen.", False
    if c == "shutdown":
        run(["loginctl", "lock-sessions"], 30)
        return "Locked and shutting down. The disk lock now keeps every file safe.", True
    return "Your PC heard you%s." % (" (lost mode is ON)" if st.get("lost") else ""), False


def power_off():
    time.sleep(0 if os.environ.get("FORGEOS_LOC_NOW") else 3)
    run(["systemctl", "poweroff"], 60)

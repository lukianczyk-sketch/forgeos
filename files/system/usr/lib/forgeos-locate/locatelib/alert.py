"""Your session's side (forgeos-locate-alert.service, every signed-in person): within 2 seconds of your phone
asking - Ring (sound up, unmuted, a loud sound for 2 minutes, even at the lock screen), the "please return"
message (big window + a critical note), and when lost: your password safe (KeePassXC) is locked.
"""
import os
import threading
import time

from . import ALERT, ENV, MY_STATE, RING_FOR, load_json, now, run, save_json, start

SOUNDS = ("/usr/share/sounds/ocean/stereo/alarm-clock-elapsed.oga",
          "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
          "/usr/share/sounds/freedesktop/stereo/phone-incoming-call.oga")
KEEP = 12 * 3600   # a message still shows to someone who signs in up to 12 hours later


def note(title, text, urgent=True):
    return start(["notify-send", "--app-name=Find My PC", "--icon=find-location",
                  "--urgency=" + ("critical" if urgent else "normal"), "--", title, text])


def sound():
    for s in ([ENV("FORGEOS_LOC_SOUND")] if ENV("FORGEOS_LOC_SOUND") else []) + list(SOUNDS):
        if os.path.exists(s):
            return s
    return ""


def ring(secs=RING_FOR):
    """Sound on, all the way up, a loud sound again and again for `secs` seconds."""
    run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "0"], 10)
    run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", "100%"], 10)
    note("Find My PC", "The owner is ringing this PC from their phone.")
    s, end = sound(), time.monotonic() + secs
    while s and time.monotonic() < end:
        code = run(["paplay", s], 30)[0]
        if code != 0:
            time.sleep(2)


def message(text):
    note("This PC is lost", text)
    start(["kdialog", "--title", "This PC is lost", "--msgbox",
           "<h1>This PC is lost</h1><h2>%s</h2>" % text.replace("&", "and").replace("<", " ").replace(">", " ")])


def lost():
    """Lock the password safe (KeePassXC Flatpak or the normal app) - nothing else shows, on purpose."""
    run(["flatpak", "run", "--command=keepassxc", "org.keepassxc.KeePassXC", "--lock"], 20)
    run(["keepassxc", "--lock"], 20)


def show(a, wait=False):
    kind, age = a.get("kind"), now() - float(a.get("t", 0))
    if kind == "ring" and age < RING_FOR:
        th = threading.Thread(target=ring, args=(RING_FOR - age,), daemon=True)
        th.start()
        if wait:
            th.join()
    elif kind == "message" and age < KEEP:
        message(a.get("text") or "Please call the owner.")
    elif kind == "lost" and age < KEEP:
        lost()
    elif kind == "found" and age < 600:
        note("Find My PC", "Lost mode is off. Welcome back!", False)
    else:
        return False
    return True


def tick(wait=False):
    """Show each new alert once (oldest first). Returns the kinds shown."""
    mine = load_json(MY_STATE)
    seen = mine.get("seen", [])
    new = [a for a in load_json(ALERT).get("list", []) if isinstance(a, dict) and a.get("id") not in seen]
    if not new:
        return []
    mine["seen"] = (seen + [a.get("id") for a in new])[-20:]
    save_json(MY_STATE, mine, 0o600)
    return [a.get("kind", "") for a in new if show(a, wait)]


def main(once=False):
    while True:
        for kind in tick(once):
            print("SHOWN\t" + kind, flush=True)
        if once:
            return 0
        time.sleep(2)

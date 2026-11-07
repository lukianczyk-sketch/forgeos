"""The watcher in your session (forgeos-techguard.service), every 2 seconds:
- a remote-control app starts: paused at once, the big window asks you first (Family Mode: closed);
  your helper's Call for help and apps you trusted run on;
- anyone can see the screen: money websites locked and a red note, until it stops;
- a remote-control app was downloaded: a warning with "Lock it away".
"""
import os
import time

from . import GUI, HOME, QUIET_AFTER, Locked, clean, now, run, start
from . import alarm, apps, money, procs, screen
from .notes import close_note, guard_log, notify

FOLDERS = ("Downloads", "Desktop")


def new_app(st, hit, call):
    """A remote-control app that was not seen before. Returns the alarm (or None when it may run)."""
    if hit["test"]:
        how, pids = procs.pause(hit)
        return alarm.new(st, hit, how, pids, "paused")
    if hit["app"] == "rustdesk" and call:
        return alarm.new(st, hit, "", hit["pids"], "helper")
    if alarm.family_on():
        how, pids = procs.pause(hit)
        procs.end(how, hit.get("cgroup", ""), pids)
        a = alarm.new(st, hit, how, pids, "ended-family")
        notify("A remote-control app was closed", "Family Mode closed %s. Only Call for help may connect to this "
               "PC. Never let a caller into your computer." % hit["title"])
    elif alarm.is_trusted(hit):
        return alarm.new(st, hit, "", hit["pids"], "allowed")
    else:
        how, pids = procs.pause(hit)
        a = alarm.new(st, hit, how, pids, "paused" if how != "failed" else "running")
        notify("STOP - is someone on the phone with you?", "%s wants to let someone control this PC. ForgeOS "
               "paused it. Microsoft, Apple and your bank NEVER call you to get into your computer." % hit["title"])
    guard_log("%s (a remote-control app) was %s" % (hit["title"], "closed" if a["state"] == "ended-family" else "paused"),
              a["program"], "Fake tech support callers ask people to install %s to take over the PC.\n" % hit["title"])
    start([GUI, "--alarm", a["id"]])
    return a


def apps_tick(st):
    hits = procs.remote_apps()
    call = alarm.helper_call() if any(h["app"] == "rustdesk" for h in hits.values()) else ""
    shown = []
    for k, hit in hits.items():
        if alarm.by_key(st, k) is None:
            shown.append(new_app(st, hit, call))
    for a in st.get("alarms", {}).values():  # the app is gone
        if a["state"] in ("paused", "allowed", "helper", "running") and a["key"] not in hits:
            a["state"] = "gone"
    return [a for a in shown if a]


def lock_passwords():
    """Easy Passwords (KeePassXC) locks itself while someone can see the screen."""
    if any(i["name"] == "keepassxc" or i["flatpak"] == "org.keepassxc.KeePassXC" for i in procs.mine()):
        run(["flatpak", "run", "--command=keepassxc", "org.keepassxc.KeePassXC", "--lock"], 20)


def share_tick(st):
    """Anyone watching the screen: money websites locked and a red note, until 10 s after it stops."""
    who = screen.watchers()
    t = now()
    if who:
        names = ", ".join(w["name"] for w in who)
        st["last_share"], st["sharing"] = t, [w["key"] for w in who]
        if not st.get("money_ok") and st.get("money") not in ("locked", "failed"):
            st["money"] = "locked" if money.set_lock(True) else "failed"  # one try: never a pop-up every 2 s
        if not st.get("note"):
            lock_passwords()
            st["note"] = notify("Someone can see this screen", "%s can see your screen. Bank, payment and "
                                "gift-card websites and your passwords are locked until it stops. If a "
                                "stranger is in, press Ctrl+Alt+K (Kick them out)." % clean(names, 80)) or "-"
        return who
    if st.get("sharing") and t - st.get("last_share", 0) >= QUIET_AFTER:
        st["sharing"], st["money_ok"] = [], False
        close_note(st.pop("note", ""))
        if st.get("money") == "locked":
            st["money"] = "open" if money.set_lock(False) else "stuck"
        elif st.get("money") == "failed":
            st["money"] = "open"
    return who


def download_tick(st):
    """Remote-control app files that just landed in Downloads or on the Desktop."""
    found = []
    for folder in FOLDERS:
        try:
            names = os.listdir(os.path.join(HOME, folder))
        except OSError:
            continue
        for n in names:
            what = apps.installer(n)
            if what:
                found.append((os.path.join(HOME, folder, n), what))
    first = "seen" not in st
    seen = st.setdefault("seen", [])
    new = [(p, w) for p, w in found if p not in seen]
    st["seen"] = [p for p, _w in found]  # a file deleted and downloaded again is warned about again
    if first:
        return []
    for path, what in new:
        guard_log("%s (a remote-control app) was downloaded" % what[1], path,
                  "Fake tech support callers ask people to download %s.\n" % what[1])
        start([GUI, "--download", path])
    return [p for p, _w in new]


def tick(st):
    return {"apps": apps_tick(st), "share": share_tick(st), "downloads": download_tick(st)}


def main(once=False):
    while True:
        try:
            with Locked() as st:
                found = tick(st)
            for a in found["apps"]:
                print("ALARM\t%s\t%s\t%s" % (a["id"], a["title"], a["state"]), flush=True)
        except Exception as e:  # noqa: BLE001 - the watcher must never stop
            print("problem: %s" % clean(e, 200), flush=True)
        if once:
            return 0
        time.sleep(2)

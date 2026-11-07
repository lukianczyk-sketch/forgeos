"""Kick them out (Ctrl+Alt+K): end every remote-control app and every screen sharing, cut the internet,
close a browser stuck on a fake virus page, then a calm checklist of what a stranger may have left behind.
"""
import os
import sys
import time

from . import GUARD_LIB, HOME, clean, run
from . import alarm, apps, procs, screen

BROWSERS = ("brave", "brave-browser", "chrome", "google-chrome", "chromium", "chromium-browser", "firefox",
            "firefox-bin", "librewolf", "vivaldi-bin", "opera", "msedge", "microsoft-edge")
BROWSER_APPS = ("com.brave.Browser", "org.mozilla.firefox", "com.google.Chrome", "org.chromium.Chromium",
                "io.gitlab.librewolf-community", "com.microsoft.Edge", "com.vivaldi.Vivaldi", "com.opera.Opera")
DAY = 24 * 3600


def _end_program(i):
    """End one app (its whole scope when the scope is this app only), else the program and what it started."""
    hit = dict(i, pids=[i["pid"]])
    how, pids = procs.pause(hit)
    return procs.end(how, i.get("cgroup", ""), pids or [i["pid"]])


def kick(st):
    """Lines for the window: KICKED name / SCREEN name / INTERNET cut|failed."""
    lines = []
    hits = procs.remote_apps()
    if any(h["app"] == "rustdesk" for h in hits.values()) and alarm.helper_call():
        run(["forgeos-family", "call-end"], 30)
    for k, hit in hits.items():
        a = alarm.by_key(st, k)
        how, pids = (a["how"], a["pids"]) if a and a.get("state") == "paused" and a.get("how") else procs.pause(hit)
        procs.end(how, hit.get("cgroup", ""), pids or hit["pids"])
        if a:
            a["state"] = "kicked"
        lines.append("KICKED\t" + hit["title"])
    for a in alarm.paused(st):
        a["state"] = "kicked"
    for w in screen.watchers():
        i = procs.info(w["pid"]) if w["pid"] else {}
        if i and _end_program(i):
            lines.append("SCREEN\t" + w["name"])
    code = run(["nmcli", "networking", "off"], 30)[0]
    if code == 0:
        st["net"] = "cut"
    lines.append("INTERNET\t" + ("cut" if code == 0 else "failed"))
    return lines


def escape():
    """Close every web browser at once (a fake virus page can't stop that). Returns how many."""
    n = 0
    for i in procs.mine():
        if i["name"] in BROWSERS or os.path.basename(i["exe"]) in BROWSERS or i["flatpak"] in BROWSER_APPS:
            n += 1 if _end_program(i) else 0
    return n


def net_on(st):
    code = run(["nmcli", "networking", "on"], 30)[0]
    if code == 0:
        st["net"] = "on"
    return code == 0


def _new_files(folder, endings, since):
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return []
    found = []
    for n in names:
        p = os.path.join(folder, n)
        try:
            if n.endswith(endings) and os.lstat(p).st_mtime >= since:
                found.append(p)
        except OSError:
            continue
    return found


def flatpak_remote_apps():
    code, out = run(["flatpak", "list", "--app", "--columns=application"], 60)
    return [a.strip() for a in out.splitlines() if code == 0 and a.strip() and apps.which([a.strip()])]


def recent(t=None):
    """What a stranger may have left: ITEM kind value label (kind: flatpak, file)."""
    since = (t or time.time()) - DAY
    items = [("flatpak", a, "Remote-control app: %s" % a) for a in flatpak_remote_apps()]
    for folder in ("Downloads", "Desktop", ""):
        for p in _new_files(os.path.join(HOME, folder), tuple(apps.ENDINGS), 0):
            what = apps.installer(os.path.basename(p))
            if what:
                items.append(("file", p, "Remote-control app file (%s): %s" % (what[1], p)))
    cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
    for p in _new_files(os.path.join(cfg, "autostart"), (".desktop", ".sh"), since):
        items.append(("file", p, "New: starts by itself when you log in: %s" % os.path.basename(p)))
    for p in _new_files(os.path.join(cfg, "systemd", "user"), (".service", ".timer"), since):
        items.append(("file", p, "New: runs by itself in the background: %s" % os.path.basename(p)))
    for p in _new_files(os.path.join(data, "applications"), (".desktop",), since):
        items.append(("file", p, "New program in the last day: %s" % os.path.basename(p)))
    return [(k, v, clean(label, 200)) for k, v, label in items]


def lock_away(path, why):
    """Into Always-On Guard's locked folder (it lists them; you can still delete or put them back)."""
    sys.path.insert(0, GUARD_LIB)
    try:
        from guardlib import quarantine
        return bool(quarantine.lock_away(path, why))
    except (ImportError, OSError):
        return False
    finally:
        sys.path.remove(GUARD_LIB)


def remove_item(kind, value):
    """Remove one checklist item (only items on the list right now). True when it is gone."""
    if (kind, value) not in [(k, v) for k, v, _l in recent()]:
        return False
    if kind == "flatpak":
        for where in ("--user", "--system"):
            if run(["flatpak", "uninstall", where, "-y", "--noninteractive", value], 300)[0] == 0:
                return True
        return False
    return lock_away(value, "Left behind after a remote-control session (Fake Tech Support Guard)")

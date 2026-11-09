"""The problems Forge Helper watches for. Each check returns None or
(topic, message, action, argument, button label); the action runs only when the user clicks the button.
"""
import os
import time

from . import run

UPDATE_UNITS = ("rpm-ostreed-automatic.service", "uupd.service")
PIKA = "~/.var/app/org.gnome.World.PikaBackup/config/pika-backup"
KEEP = ("plasmashell", "kwin_wayland", "kwin_x11", "Xwayland", "pipewire", "wireplumber", "ollama",
        "systemd", "baloo_file", "forgeos-", "kded6", "krunner")
OLD_BACKUP = 14 * 86400


def size_gb(path):
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
    return total / 1e9


def check_disk():
    try:
        st = os.statvfs(os.path.expanduser("~"))
    except OSError:
        return None
    used = 100 - int(100 * st.f_bavail / max(st.f_blocks, 1))
    if used < 90:
        return None
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    trash = size_gb(os.path.join(data, "Trash"))
    msg = "Your drive is almost full (%d%% used)." % used
    if trash >= 0.5:
        return ("disk", msg + " Emptying the trash frees %.1f GB (those files are deleted for good)." % trash,
                "pc_fix", "empty-trash", "Empty the trash")
    return ("disk", msg + " Ask Your PC can help you find what takes the space.", "open", "askpc", "Ask Your PC")


def check_update():
    for unit in UPDATE_UNITS:
        if run(["systemctl", "is-failed", "--quiet", unit], 10)[0] == 0:
            return ("update", "The last automatic system update did not finish. It tries again by itself."
                    " If you see this again, Undo Button can go back to the last good version.",
                    "open", "undo", "Open Undo Button")
    return None


def check_guard(st):
    code, out = run(["forgeos-guard", "events", "20"], 30)
    rows = [x.split("\t") for x in out.splitlines() if x.count("\t") >= 6] if code == 0 else []
    new = [r for r in rows if r[6] > st.get("guard_last", "") and r[1] in ("virus", "scam", "risky")]
    if rows:
        st["guard_last"] = max(r[6] for r in rows)
    if not new:
        return None
    return ("guard", "Always-On Guard stopped %d dangerous thing(s) since I last looked. You are safe;"
            " here is what it caught." % len(new), "open", "guard", "Show me")


def check_health():
    code, out = run(["forgeos-askpc", "health"], 60)
    bad = [x[2:] for x in out.splitlines() if x.startswith("! ")] if code == 1 else []
    if not bad:
        return None
    return ("health", "Ask Your PC found a problem: %s" % bad[0], "open", "askpc", "Ask Your PC")


def check_hog():
    code, out = run(["ps", "-u", str(os.getuid()), "-o", "comm=,etimes=,%cpu=", "--sort=-%cpu"], 10)
    for line in out.splitlines()[:5] if code == 0 else []:
        p = line.split()
        if len(p) != 3 or p[0].startswith(KEEP):
            continue
        try:
            secs, cpu = int(p[1]), float(p[2])
        except ValueError:
            continue
        if secs >= 600 and cpu >= 80:
            return ("hog", "%s has been using most of the computer's power for over 10 minutes. Closing it"
                    " makes the PC fast again (unsaved work in it may be lost)." % p[0],
                    "pc_fix", "close-busy-app " + p[0], "Close " + p[0])
        return None
    return None


def check_slow():
    code, out = run(["forgeos-slow", "quick"], 60)
    if code != 1 or not out.strip():
        return None
    return ("slow", out.strip().splitlines()[0] + " Want to see why and fix it?", "open", "slow", "Show me")


def check_drive():
    code, out = run(["forgeos-drivehealth", "status"], 30)
    if code != 1:
        return None
    rows = [x.split("\t") for x in out.splitlines()]
    drive = next((r for r in rows if r[0] == "DRIVE" and len(r) > 3 and r[2] == "watch"), None)
    why = next((r[2] for r in rows if drive and r[0] == "REASON" and len(r) > 2 and r[1] == drive[1]), "")
    name = drive[3] if drive else "a drive"
    return ("drive", "Drive Health noticed early warning signs on %s: %s Your files are fine for now;"
            " a fresh backup keeps them safe." % (name, why), "open", "drivehealth", "Show me")


def check_backup():
    folder = os.path.expanduser(PIKA)
    if not os.path.isfile(os.path.join(folder, "backup.json")):
        return None
    try:
        age = time.time() - os.path.getmtime(os.path.join(folder, "histories.json"))
    except OSError:
        age = OLD_BACKUP + 1
    if age < OLD_BACKUP:
        return None
    return ("backup", "Your last backup is more than 2 weeks old. A fresh backup keeps your photos and"
            " papers safe.", "pc_fix", "open-backup", "Back up now")

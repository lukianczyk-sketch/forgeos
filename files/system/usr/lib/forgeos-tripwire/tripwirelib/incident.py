"""What happens when the tripwire goes off (root), and the saved story of each time it did.

1. Freeze the program (the whole app). 2. Cut the internet (it can't send your files away or get
more orders). 3. Take a snapshot right away. 4. Save what happened (incidents/ID.json, readable only
by the person whose files it was, changed only by root) and tell their session (RUN/alert-UID), which
shows the window. The internet comes back only when that person presses "Turn the internet back on".
"""
import os
import time

from . import FOLDERS, HOMES, ID_RX, INCIDENTS, RUN, TEST_DIR, load_json, now, run, save_json, say, procs


def path_of(iid):
    return os.path.join(INCIDENTS, iid + ".json") if ID_RX.match(iid or "") else ""


def load(iid):
    p = path_of(iid)
    return load_json(p) if p else {}


def owner(files, info):
    """(uid, gid, home) of the person whose files these are."""
    for p in files:
        rel = os.path.relpath(p, HOMES)
        if not rel.startswith(".."):
            home = os.path.join(HOMES, rel.split("/", 1)[0])
            try:
                st = os.stat(home)
                return st.st_uid, st.st_gid, home
            except OSError:
                pass
    return info.get("uid", 0), info.get("uid", 0), ""


def store(inc):
    """Owned by root (only root can change it), readable by the person's own group."""
    save_json(path_of(inc["id"]), inc, 0o640, (0, inc["gid"]))


def internet_off():
    """'cut', 'already' (still cut from an earlier time) or 'failed'."""
    os.makedirs(RUN, exist_ok=True)
    mark = os.path.join(RUN, "net-cut")
    if os.path.exists(mark):
        run(["nmcli", "networking", "off"], 20)
        return "already"
    code, out = run(["nmcli", "networking"], 20)
    if run(["nmcli", "networking", "off"], 20)[0] != 0:
        return "failed"
    with open(mark, "w") as f:
        f.write(out.strip() if code == 0 else "enabled")
    return "cut"


def internet_on():
    mark = os.path.join(RUN, "net-cut")
    try:
        with open(mark) as f:
            before = f.read().strip()
    except OSError:
        before = "enabled"
    if before != "disabled" and run(["nmcli", "networking", "on"], 20)[0] != 0:
        return False
    try:
        os.remove(mark)
    except OSError:
        pass
    return True


def snapshot(start):
    """A snapshot right now, and the last one from BEFORE the attack is kept until you delete it
    (the hourly clean-up would otherwise remove it in a day or two)."""
    from .restore import snapshots
    before = snapshots(start)
    if before:
        run(["snapper", "-c", "root", "modify", "-c", "", "-d",
             "Kept by Ransomware Tripwire: your files from before the attack", str(before[0][0])], 60)
    code, out = run(["snapper", "-c", "root", "create", "-c", "number", "-p", "-d",
                     "Ransomware Tripwire: right after a program was stopped"], 120)
    return out.strip() if code == 0 and out.strip().isdigit() else ""


def is_test(info, files):
    """'Test the tripwire': the pretend attacker, only inside its own test folder."""
    folder = "/%s/%s/" % (FOLDERS[0], TEST_DIR)
    return "pretend-attacker" in info.get("cmd", "") and bool(files) and all(folder in p for p in files)


def trigger(app, reason, t):
    info = app.info
    files = [p for p, w in app.files.items() if w >= (app.first or app.began) - 60]
    test = is_test(info, files)
    how, pids = procs.freeze(info)
    uid, gid, home = owner(files, info)
    iid = time.strftime("%Y%m%d-%H%M%S", time.localtime(t)) + "-%d" % info.get("pid", 0)
    inc = {"id": iid, "kind": "test" if test else "attack", "time": t, "start": app.first or app.began,
           "reason": reason, "program": info.get("name", "") or "unknown", "exe": info.get("exe", ""),
           "cmd": info.get("cmd", ""),
           "pid": info.get("pid", 0), "cgroup": info.get("cgroup", ""), "frozen": how, "pids": pids,
           "uid": uid, "gid": gid, "home": home, "files": files, "state": "frozen",
           "internet": "left on (test)" if test else internet_off(),
           "snapshot": "" if test else snapshot(app.first or app.began)}
    if test:
        procs.end(how, inc["cgroup"], pids)
        inc["state"] = "removed"
    store(inc)
    tell(uid, iid)
    say("TRIPWIRE %s: %s (%s) %s frozen=%s internet=%s snapshot=%s files=%d" % (
        inc["kind"], inc["program"], inc["exe"], reason, how, inc["internet"], inc["snapshot"] or "-", len(files)))
    return inc


def bait_note(path, t):
    """A bait file was removed while no program was writing: probably done by hand. A quiet note."""
    uid, gid, home = owner([path], {})
    iid = time.strftime("%Y%m%d-%H%M%S", time.localtime(t)) + "-0"
    inc = {"id": iid, "kind": "bait", "time": t, "start": t, "reason": "A safety file was removed: %s" % path,
           "program": "", "exe": "", "pid": 0, "cgroup": "", "frozen": "", "pids": [], "uid": uid, "gid": gid,
           "home": home, "files": [path], "state": "done", "internet": "left on", "snapshot": ""}
    store(inc)
    tell(uid, iid)
    return inc


def tell(uid, iid):
    """The person's own session watches RUN/alert-UID and shows the window."""
    os.makedirs(RUN, mode=0o755, exist_ok=True)
    save_json(os.path.join(RUN, "alert-%d" % uid), {"id": iid, "time": now()}, 0o644)


def mine(uid):
    """This person's incidents, newest first."""
    try:
        names = sorted(os.listdir(INCIDENTS), reverse=True)
    except OSError:
        return []
    found = []
    for n in names:
        inc = load(n[:-5]) if n.endswith(".json") else {}
        if inc and (inc.get("uid") == uid or uid == 0):
            found.append(inc)
    return found


def open_ones(uid):
    return [i for i in mine(uid) if i.get("state") == "frozen"]

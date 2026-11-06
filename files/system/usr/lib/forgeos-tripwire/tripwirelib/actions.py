"""The buttons: put my files back, remove the program, it's mine, turn the internet back on, test.

Root parts run through pkexec: forgeos-tripwire-helper (remove, net-on: no password for the person at
the PC) and forgeos-tripwire-release ("It's mine": asks for the PC password). Root only acts on the
caller's own incidents (PKEXEC_UID).
"""
import os
import shutil
import subprocess
import time

from . import (ALLOWED, ENGINE, ENV, FOLDERS, HELPER, HOME, RELEASE, STATE, TEST_DIR, is_root, load_json,
               my_uid, now, run, save_json, incident, procs, restore)


def caller():
    return int(ENV("PKEXEC_UID") or 0)


def root_do(what, iid=""):
    """The root half (called by the two helper programs). Exit 0 done, 1 nothing to do, 3 refused."""
    if what == "net-on":
        return 0 if incident.internet_on() else 1
    inc = incident.load(iid)
    if not inc or (inc.get("uid") != caller() and caller() != 0):
        print("Not your incident.")
        return 3
    if inc.get("state") != "frozen":
        print("Already handled (%s)." % inc.get("state"))
        return 1
    if what == "remove":
        procs.end(inc["frozen"], inc["cgroup"], inc["pids"])
        inc["state"] = "removed"
    elif what == "release":
        procs.unfreeze(inc["frozen"], inc["cgroup"], inc["pids"])
        allowed = load_json(ALLOWED, [])
        if inc.get("exe") and inc["kind"] == "attack":
            allowed = [a for a in allowed if (a.get("exe"), a.get("cmd")) != (inc["exe"], inc.get("cmd"))]
            allowed.append({"exe": inc["exe"], "name": inc["program"], "sha256": procs.sha256(inc["exe"]),
                            "cmd": inc.get("cmd", ""), "time": now()})
            save_json(ALLOWED, allowed, 0o644)
        inc["state"] = "released"
    else:
        return 3
    incident.store(inc)
    print("Done: %s." % inc["state"])
    return 0


def via_root(prog, *args):
    """As yourself: ask root through pkexec. Exit codes as root_do (126/127 = refused or missing)."""
    if is_root():
        return root_do(*args)
    return run([ENV("FORGEOS_TW_PKEXEC") or "pkexec", prog] + list(args), 600)[0]


def remove(iid):
    """End the program; lock its program file away (Always-On Guard) if it is in your home."""
    code = via_root(HELPER, "remove", iid)
    inc = incident.load(iid)
    exe = inc.get("exe", "")
    if code == 0 and exe.startswith(HOME.rstrip("/") + "/") and os.path.isfile(exe):
        locked = restore.lock_away(exe, inc.get("program", "?"))
        print("Program removed and its file locked away: %s" % exe if locked else "Program ended: %s" % exe)
    elif code == 0:
        print("Program ended: %s" % (exe or inc.get("program", "?")))
    return code


def put_back(iid):
    inc = incident.load(iid)
    if not inc or inc.get("uid") != my_uid():
        print("No such incident for you.")
        return 3
    res = restore.put_back(inc)
    if res["snapshot"] is None:
        print("NO-SNAPSHOT\tThere is no Undo Button snapshot from before the attack, so files can't come back.")
        return 1
    st = load_json(STATE)
    n = {k: len(res[k]) for k in ("back", "locked", "lost", "usb")}
    st.setdefault("restored", {})[iid] = dict(n, time=now())
    save_json(STATE, st, 0o600)
    print("BACK\t%(back)d\nLOCKED\t%(locked)d\nLOST\t%(lost)d\nUSB\t%(usb)d" % n)
    for p in res["lost"][:20]:
        print("LOSTFILE\t%s" % p)
    for p in res["usb"][:20]:
        print("USBFILE\t%s" % p)
    print("SNAPSHOT\t%s" % time.strftime("%Y-%m-%d %H:%M", time.localtime(res["snapshot"][1])))
    return 0


def test(wait=30):
    """'Test the tripwire': a pretend attacker scrambles 30 test letters in its own folder."""
    folder = os.path.join(HOME, FOLDERS[0], TEST_DIR)
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    for n in range(1, 31):
        with open(os.path.join(folder, "Test letter %02d.txt" % n), "w") as f:
            f.write(("Dear friend, this is test letter %d for the Ransomware Tripwire.\n" % n) * 60)
    began = now()
    cmd = [ENGINE, "pretend-attacker", folder]
    if shutil.which("systemd-run") and os.path.exists(os.path.join(ENV("XDG_RUNTIME_DIR") or "-", "bus")):
        cmd = ["systemd-run", "--user", "--scope", "--quiet",  # its own app scope: it is frozen on its own
               "--unit=app-forgeos-tripwire-test-%d.scope" % int(began)] + cmd
    child = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    found = None
    for _ in range(wait * 4):
        found = next((i for i in incident.mine(my_uid()) if i["kind"] == "test" and i["time"] >= began - 1), None)
        if found:
            break
        time.sleep(0.25)
    if not found:
        child.kill()
    shutil.rmtree(folder, ignore_errors=True)
    if not found:
        print("FAIL\tThe pretend attacker was not caught. Is Ransomware Tripwire on?")
        return 1
    print("PASS\tCaught the pretend attacker after %d test files, %.1f seconds after it started."
          % (len(found["files"]), max(0.0, found["time"] - found["start"])))
    return 0


def pretend_attacker(folder):
    """The harmless pretend attacker: it only touches its own test letters."""
    if os.path.basename(folder.rstrip("/")) != TEST_DIR:
        return 3
    for name in sorted(os.listdir(folder)):
        if name.startswith("Test letter ") and name.endswith(".txt"):
            with open(os.path.join(folder, name + ".test-locked"), "wb") as f:
                f.write(os.urandom(4096))
            os.remove(os.path.join(folder, name))
            time.sleep(0.05)
    time.sleep(30)  # waits here to be caught
    return 0


def release(iid):
    return via_root(RELEASE, "release", iid)


def net_on():
    code = via_root(HELPER, "net-on")
    print("The internet is back on." if code == 0 else "The internet could not be turned back on.")
    return code

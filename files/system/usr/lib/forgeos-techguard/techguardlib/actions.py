"""The buttons of the big window: end it, I set this up myself (PC password), my helper asked me to,
I'm sharing my screen on purpose (PC password), lock a downloaded remote app away, and Test the guard.
"""
import os
import shutil
import subprocess
import time

from . import (ENV, HOME, TEST_DIR, TRUST_HELPER, Locked, is_root, now, run)
from . import alarm, kick, money, procs, watch


def _pkexec(*args):
    if is_root():
        return 0
    return run([ENV("FORGEOS_TG_PKEXEC") or "pkexec", TRUST_HELPER] + list(args), 600)[0]


def _alarm(st, aid, states):
    a = st.get("alarms", {}).get(aid)
    if not a or a.get("state") not in states or a.get("test"):
        print("That app was already handled (%s)." % (a or {}).get("state", "not found"))
        return None
    return a


def end(aid):
    """End the paused app; its program file (if in your home) goes to Always-On Guard's locked folder."""
    with Locked() as st:
        a = _alarm(st, aid, ("paused", "running", "allowed", "helper"))
        if not a:
            return 1
        hit = procs.remote_apps().get(a["key"])
        how, pids = (a["how"], a["pids"]) if a["state"] == "paused" else procs.pause(hit) if hit else ("", [])
        procs.end(how, a["cgroup"], pids)
        a["state"] = "ended"
    exe = a.get("program", "")
    if exe.startswith(HOME.rstrip("/") + "/") and os.path.isfile(exe):
        kick.lock_away(exe, "%s, a remote-control app (Fake Tech Support Guard)" % a["title"])
        print("%s was closed and its program file locked away." % a["title"])
    else:
        print("%s was closed." % a["title"])
    return 0


def allow(aid):
    """I set this up myself: needs the PC password, then it runs and is trusted from now on."""
    with Locked() as st:
        a = _alarm(st, aid, ("paused",))
        if not a:
            return 1
        if a.get("family") or alarm.family_on():
            print("Family Mode is on: only Call for help may connect to this PC.")
            return 3
        if _pkexec("add", str(a["pid"])) != 0:
            print("It stays paused (no password, or the wrong one).")
            return 1
        procs.let_go(a["how"], a["cgroup"], a["pids"])
        a["state"] = "allowed"
    print("%s runs again and is trusted from now on." % a["title"])
    return 0


def helper(aid):
    """My helper asked me to (only while Family Mode's Call for help is running)."""
    with Locked() as st:
        a = _alarm(st, aid, ("paused",))
        if not a:
            return 1
        name = alarm.helper_call()
        if not name:
            print("Call for help is not running, so this can't be your helper.")
            return 3
        procs.let_go(a["how"], a["cgroup"], a["pids"])
        a["state"] = "helper"
    print("%s runs again for %s. Kick them out (Ctrl+Alt+K) ends it any time." % (a["title"], name))
    return 0


def share_ok():
    """I'm sharing my screen on purpose: PC password, then money websites open until the sharing stops."""
    if _pkexec("share") != 0:
        print("Money websites stay locked (no password, or the wrong one).")
        return 1
    with Locked() as st:
        st["money_ok"] = bool(st.get("sharing"))  # only for this sharing; the next one locks them again
        if money.set_lock(False):
            st["money"] = "open"
    print("Money websites are open again%s." % (" until the screen sharing stops" if st["money_ok"] else ""))
    return 0


def lock_file(path):
    """Lock a downloaded remote-control app away (only one in Downloads or on the Desktop)."""
    real = os.path.realpath(path)
    ok_dirs = [os.path.realpath(os.path.join(HOME, d)) for d in watch.FOLDERS]
    from . import apps
    if os.path.dirname(real) not in ok_dirs or not apps.installer(os.path.basename(real)) or not os.path.isfile(real):
        print("Only a remote-control app in Downloads or on the Desktop can be locked away here.")
        return 3
    if not kick.lock_away(real, "A remote-control app (Fake Tech Support Guard)"):
        print("It could not be locked away.")
        return 1
    print("Locked away. Always-On Guard keeps it in its locked folder.")
    return 0


def _service_on():
    code, out = run(["systemctl", "--user", "is-active", "forgeos-techguard.service"], 10)
    return code == 0 and out.strip() == "active"


def test(wait=15):
    """Test the guard: a harmless pretend remote app ('AnyDesk', really the sleep program) starts."""
    folder = os.path.join(ENV("XDG_RUNTIME_DIR") or "/tmp", TEST_DIR)
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder, mode=0o700)
    fake = os.path.join(folder, "AnyDesk")
    os.symlink(shutil.which("sleep") or "/usr/bin/sleep", fake)
    began = now()
    child = subprocess.Popen([fake, "60"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    found = None
    for _ in range(wait * 4):
        with Locked() as st:
            watch.apps_tick(st)
            found = next((a for a in st.get("alarms", {}).values() if a.get("test") and a["state"] == "paused"
                          and a["time"] >= began - 1), None)
            if found:
                procs.end(found["how"], found["cgroup"], found["pids"])
                found["state"] = "test-caught"
                break
        time.sleep(0.25)
    child.kill()
    child.wait()
    shutil.rmtree(folder, ignore_errors=True)
    if not found:
        print("FAIL\tThe pretend remote app was not caught.")
        return 1
    off = "" if _service_on() else " But the guard's watcher is OFF right now - press \"Turn the guard on\"."
    print("PASS\tCaught the pretend remote app %.1f seconds after it started and paused it.%s"
          % (max(0.0, found["time"] - began), off))
    return 0

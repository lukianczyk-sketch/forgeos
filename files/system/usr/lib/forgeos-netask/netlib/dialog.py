"""Reach the person's own screen from the root service, so no other program can answer for them.

Each window (kdialog) is started by root straight into the person's desktop session as that person, with a
clean, fixed environment (setpriv + env -i): no user settings, no user services, nothing a program in their
account could swap in. The answer is the window's own exit code, read by root (askui.py).
"""
import glob
import os
import re
import shutil
import signal
import subprocess

from . import ENV, TEST, home_of, ids_of, run

RUN_USER = ENV("FORGEOS_NETASK_RUNUSER") or "/run/user"


def session_env(uid):
    """The fixed settings to reach this person's desktop, or None when they have no active local desktop."""
    code, out = run(["loginctl", "list-sessions", "--no-legend"], 10)
    if code != 0:
        return None
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 2 or parts[1] != str(int(uid)) or not re.match(r"^[A-Za-z0-9]+$", parts[0]):
            continue
        props = dict(x.split("=", 1) for x in run(["loginctl", "show-session", parts[0], "-p", "Type", "-p", "Active",
                                                    "-p", "Remote"], 10)[1].splitlines() if "=" in x)
        if props.get("Active") != "yes" or props.get("Remote") == "yes" or props.get("Type") not in ("wayland", "x11"):
            continue
        rundir = os.path.join(RUN_USER, str(int(uid)))
        env = {"HOME": "/nonexistent", "LANG": "C.UTF-8", "PATH": "/usr/bin:/bin", "XDG_RUNTIME_DIR": rundir,
               "DBUS_SESSION_BUS_ADDRESS": "unix:path=%s/bus" % rundir}
        socks = sorted(s for s in glob.glob(os.path.join(rundir, "wayland-[0-9]*")) if not s.endswith(".lock"))
        if props["Type"] == "wayland" and socks:
            env["WAYLAND_DISPLAY"] = os.path.basename(socks[0])
            env["QT_QPA_PLATFORM"] = "wayland"
        else:
            env["DISPLAY"] = ":0"
        env["HOME"] = home_of(uid) or "/nonexistent"
        return env
    return None


def command(uid, env, argv):
    """The exact command that runs argv (kdialog ...) as the person (the tests run it as themselves)."""
    vars_ = ["%s=%s" % (k, v) for k, v in sorted(env.items())]
    if TEST:
        return ["/usr/bin/env", "-i"] + vars_ + ["FORGEOS_NETASK_TEST=1", "PATH=" + ENV("PATH", "")] + argv
    who = ids_of(uid)
    if not who or not shutil.which("setpriv"):
        return None
    return ["setpriv", "--reuid=%d" % who[0], "--regid=%d" % who[1], "--init-groups", "--no-new-privs", "--",
            "/usr/bin/env", "-i"] + vars_ + argv


def window(uid, env, argv, seconds):
    """Run one window as the person and wait at most `seconds`. Returns (exit code, output), or (None, "")
    when it ran out of time, was killed (by anything) or could not start. The whole window is closed then."""
    cmd = command(uid, env, argv) if env and seconds >= 1 else None
    if not cmd:
        return None, ""
    try:
        p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             start_new_session=True, env=None if TEST else {"PATH": "/usr/bin:/bin"})
    except OSError:
        return None, ""
    try:
        out, _ = p.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.wait()
        return None, ""
    if p.returncode < 0:
        return None, ""
    return p.returncode, out.decode("utf-8", "replace")


def start(uid, env, argv):
    """Start a window or program as the person and do not wait (a note, Clean Sweep)."""
    cmd = command(uid, env, argv) if env else None
    if cmd:
        try:
            subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True, env=None if TEST else {"PATH": "/usr/bin:/bin"})
        except OSError:
            pass


def ask(uid, args, seconds):
    """Ask the person (askui.py). Returns its one-word answer, or "" (no answer, closed, no desktop)."""
    from . import askui
    env = session_env(uid)
    return askui.ask(uid, env, args, seconds) if env else ""


def note(uid, text):
    """A short note on the person's screen (does not wait)."""
    start(uid, session_env(uid), ["kdialog", "--title", "Ask Before Connecting", "--passivepopup", text, "10"])


def gaming(uid):
    """True while this person plays a game (Steam's gamescope or a Steam game): no questions then."""
    return run(["pgrep", "-u", str(int(uid)), "-f", "gamescope|SteamLaunch AppId="], 10)[0] == 0

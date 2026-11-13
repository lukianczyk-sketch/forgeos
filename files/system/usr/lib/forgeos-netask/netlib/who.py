"""Who is trying to use the internet: the program's real identity, its plain name, and where it came from.

Identity never trusts a name alone: a Flatpak app is known by its app id (from /proc/PID/root/.flatpak-info,
which the app cannot change), a program by its real file, a script by the script's file (not by "python3"),
a Windows program in Wine by its .exe. A program in Downloads, a temp folder or a hidden folder is "red".
"""
import os
import re

from . import HOST, PROC, clean, home_of
from .flatpak import flatpak_app
from .names import INTERP, TOOLS, WINE, args_red, desktop_name, flatpak_genuine, script_of, where, windows_exe
from .proc import cmdline, env_value, flatpak_id, same_file, tampered
from .trust import remote_app

FORGEOS_SCRIPT = re.compile(r"^/usr/(bin|libexec|lib)/forgeos-")
STEAM_CLIENT = "/ubuntu12_32/steam"


def identify(c):
    """c = one connection (dict: pid uid path args cwd md5 tree host). Returns what we know about the program:
    kind system|flatpak|steam|script|wine|tool|app, key, name, red (plain words or ""), remote, trusted,
    rule_ok (its answer may be kept as an OpenSnitch rule), gone (the program already ended)."""
    pid, uid, path = c.get("pid", 0), c.get("uid", 0), c.get("path", "")
    args, cwd = c.get("args") or [path], c.get("cwd", "")
    base = os.path.basename(path)
    me = {"uid": uid, "path": path, "md5": c.get("md5", ""), "red": "", "remote": None, "trusted": False,
          "rule_ok": bool(c.get("md5")), "gone": False}
    fid = flatpak_id(pid)
    if fid is None:
        me.update(kind="app", key="path:" + path, name=clean(base, 60) or "A program", gone=True, rule_ok=False)
        return me
    home = home_of(uid)
    folder = home + "/.local/share/Steam" if home else ""
    steam = os.path.realpath(folder) if folder and not os.path.islink(folder) else ""   # a symlinked Steam = no
    if steam and (path == steam + STEAM_CLIENT or path.startswith(steam + "/")
                  and steam + STEAM_CLIENT in c.get("tree", [])):
        me.update(kind="steam", key="steam:" + path, name="Steam" if path == steam + STEAM_CLIENT else "A Steam game",
                  trusted=True)
        return me
    real = flatpak_genuine(pid, fid, path, uid) if fid else ""
    if WINE.match(base) and (real or same_file(pid, HOST + path) or steam and path.startswith(steam + "/")):
        # a real Wine (in /usr, Bottles, Heroic or Steam): the Windows program is known by its .exe and Wine folder
        name, exe = windows_exe(args, pid)
        full = re.sub(r"/+", "/", re.sub(r"^[zZ]:", "", exe.replace("\\", "/"))).lower()
        me.update(kind="wine", key="exe:%s|%s" % (env_value(pid, "WINEPREFIX"), full or base), rule_ok=False,
                  name=(name or "A Windows program"), red=where(exe, uid), exe=exe)
        me["remote"] = remote_app([name])
        return me
    if real:
        return flatpak_app(me, c, fid, real)
    if INTERP.match(base) or TOOLS.match(base):
        kind, script = script_of(args, cwd) if INTERP.match(base) else ("", "")
        for ppid in c.get("tree_pids", []) if not script else []:
            pargs = cmdline(ppid)
            if pargs and INTERP.match(os.path.basename(pargs[0])):
                try:
                    pcwd = os.readlink(os.path.join(PROC, str(ppid), "cwd"))
                except OSError:
                    pcwd = "/"
                pk, ps = script_of(pargs, pcwd)
                if pk == "file":
                    kind, script = pk, ps
                    break
        me["rule_ok"] = False
        if kind == "file" and script:
            ours = bool(FORGEOS_SCRIPT.match(script)) and not fid and same_file(pid, HOST + path) and \
                not tampered(pid) and not args_red(args, cwd, uid)
            me.update(kind="script", key="script:" + script, name=clean(os.path.basename(script), 60),
                      red=where(script, uid) or args_red(args, cwd, uid), script=script, system=ours)
        else:
            label = re.sub(r"[0-9.]+$", "", base) or base
            me.update(kind="tool", key="cmd:" + base, red=args_red(args, cwd, uid),
                      name=clean(label, 40) + (" (typed commands)" if INTERP.match(base) else " (a terminal tool)"))
        me["remote"] = remote_app([script or base])
        return me
    on_usr = path.startswith("/usr/") and not fid and same_file(pid, HOST + path) and not tampered(pid)
    red = where(path, uid) or args_red(args, cwd, uid)
    name = (desktop_name(exe=path) if on_usr else "") or clean(base, 60) or "A program"
    me.update(kind="system" if on_usr and not red else "app", key="path:" + path, name=name, red=red,
              trusted=on_usr and not red)
    me["remote"] = remote_app([base])
    if me["remote"]:
        me["trusted"] = False
    return me

"""Small facts about a program for who.py: its menu name, whether its Flatpak app id is real, the script an
interpreter runs, the .exe Wine runs, and a risky place it lives in (or is told to run).
"""
import configparser
import glob
import os
import re

from . import HOST, clean, home_of
from .proc import comm, same_file

INTERP = re.compile(r"^(python[0-9.]*|pypy[0-9.]*|perl[0-9.]*|ruby[0-9.]*|node|nodejs|node-?[0-9]+|bun|deno|bash|sh|"
                    r"dash|zsh|fish|ksh|tcsh|csh|java|php[0-9.]*|lua[0-9.]*|tclsh[0-9.]*|mono|dotnet|pwsh|osascript|"
                    r"gjs|qml|qmlscene|g?awk|mawk|busybox|ld-linux[-\w.]*|ld[-\w.]*\.so[\w.]*)$")
WINE = re.compile(r"^(wine|wine64|wine-preloader|wine64-preloader|wineserver|wine-staging)$")
TOOLS = re.compile(r"^(curl|wget|wget2|aria2c|nc|ncat|netcat|socat|ssh|scp|sftp|rsync|ftp|telnet|openssl|git|"
                   r"git-remote-[\w-]+)$")
OK_HIDDEN = (".local/share/Steam/", ".steam/", ".var/app/", ".local/share/flatpak/")


def appdirs():
    """System menu entries only (a person's own menu folder could give any program a trusted name)."""
    if os.environ.get("FORGEOS_NETASK_APPDIRS"):
        return os.environ["FORGEOS_NETASK_APPDIRS"].split(":")
    return [HOST + "/var/lib/flatpak/exports/share/applications", HOST + "/usr/share/applications"]


def desktop_name(flatpak_id="", exe=""):
    """The menu name of a Flatpak app id, or of a program file whose Exec= is exactly that file, else ""."""
    for d in appdirs():
        for f in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            if flatpak_id and os.path.basename(f)[:-8] != flatpak_id:
                continue
            p = configparser.RawConfigParser(strict=False, interpolation=None)
            try:
                p.read(f, encoding="utf-8")
                entry = p["Desktop Entry"]
            except (configparser.Error, KeyError, UnicodeDecodeError, OSError):
                continue
            first = (entry.get("Exec", "").split() or [""])[0].strip("\"'")
            first = first if first.startswith("/") else "/usr/bin/" + first
            if exe and not flatpak_id and first != exe:
                continue
            if entry.get("Name"):
                return clean(entry.get("Name"), 60)
    return ""


def flatpak_genuine(pid, fid, path, uid):
    """"system" when the program's file is really inside that installed app (or its runtime) in the PC's own
    Flatpak folder, "user" for an app installed in the person's home, "" when the app id is a fake."""
    if not re.match(r"^[A-Za-z0-9_.-]{3,200}$", fid) or "/../" in path:
        return ""
    rest = path[5:] if path.startswith(("/app/", "/usr/")) else ""
    if not rest:
        return ""
    for kind, base in (("system", HOST + "/var/lib/flatpak"), ("user", home_of(uid) + "/.local/share/flatpak")):
        if path.startswith("/app/"):
            places = [base + "/app/" + fid + "/current/active/files/" + rest]
        else:
            places = glob.glob(base + "/runtime/*/*/*/active/files/" + glob.escape(rest))
        if any(same_file(pid, p) for p in places):
            return kind
    return ""


def script_of(args, cwd):
    """The script an interpreter runs (made absolute), ("-c", "") for typed commands, or ("", "")."""
    rest = list(args[1:])
    while rest:
        a = rest.pop(0)
        if a in ("-c", "-e", "--eval", "-Command", "-m"):
            return (a, rest[0] if rest else "")
        if a == "-jar" and rest:
            a = rest.pop(0)
        elif a.startswith("-"):
            continue
        return ("file", os.path.normpath(a if a.startswith("/") else os.path.join(cwd or "/", a)))
    return ("", "")


def windows_exe(args, pid):
    """The Windows program a Wine process runs: (shown name, its path as given), else ("", "")."""
    for a in args[1:] + [comm(pid)]:
        if re.search(r"\.exe$", a or "", re.I):
            return clean(re.split(r"[/\\]", a)[-1], 60), a
    return "", ""


def where(path, uid):
    """Plain words for a risky place ("in your Downloads folder"), or "" when the place is normal."""
    low = (path or "").replace("\\", "/")
    if re.match(r"^[Zz]:/", low):   # Wine's Z: drive is the whole PC
        low = low[2:]
    home = home_of(uid)
    if not home or not low.startswith(home + "/"):
        if re.match(r"^/(tmp|var/tmp|dev/shm|run/user)/", low) or "/appdata/local/temp/" in low.lower():
            return "in a temporary folder"
        if low.lower().startswith("c:/users/") and "/downloads/" in low.lower():
            return "in your Downloads folder"
        return ""
    inside = low[len(home) + 1:]
    if inside.startswith("Downloads/"):
        return "in your Downloads folder"
    if any(inside.startswith(ok) for ok in OK_HIDDEN):
        return ""
    if any(part.startswith(".") for part in inside.split("/")[:-1]):
        return "in a hidden folder"
    return ""


def args_red(args, cwd, uid):
    """Plain words when an argument names a file in a risky place (a /usr helper told to run or load it)."""
    for a in args[1:]:
        if "/" in a and not a.startswith("-"):
            red = where(os.path.normpath(a if a.startswith("/") else os.path.join(cwd or "/", a)), uid)
            if red:
                return red
    return ""

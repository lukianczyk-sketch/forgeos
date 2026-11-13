"""What /proc says about a running program: its Flatpak app id, command line, settings, and its real file."""
import configparser
import os
import re

from . import PROC


def flatpak_id(pid):
    """The Flatpak app id of a running process, "" when it is not a Flatpak app, None when it is gone."""
    root = os.path.join(PROC, str(pid))
    if not pid or not os.path.isdir(root):
        return None
    p = configparser.RawConfigParser(strict=False, interpolation=None)
    try:
        with open(os.path.join(root, "root", ".flatpak-info"), encoding="utf-8") as f:
            p.read_file(f)
        name = p.get("Application", "name", fallback="") or p.get("Runtime", "name", fallback="")
        return name if re.match(r"^[A-Za-z0-9_.-]{3,200}$", name) else "unknown.flatpak"
    except FileNotFoundError:
        return ""
    except (OSError, configparser.Error, UnicodeDecodeError):
        return None


def cmdline(pid):
    try:
        with open(os.path.join(PROC, str(pid), "cmdline"), "rb") as f:
            return [a.decode("utf-8", "replace") for a in f.read().split(b"\0") if a]
    except OSError:
        return []


def comm(pid):
    try:
        with open(os.path.join(PROC, str(pid), "comm"), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def tampered(pid):
    """True when a program was started with settings that change what its code does (LD_PRELOAD, PYTHONPATH,
    a ForgeOS test setting...): then it is never trusted just for living in /usr."""
    try:
        with open(os.path.join(PROC, str(pid), "environ"), "rb") as f:
            names = [v.split(b"=", 1)[0].decode("utf-8", "replace") for v in f.read().split(b"\0") if v]
    except OSError:
        return False
    return any(re.match(r"^(LD_|PYTHON|FORGEOS_|PERL5|RUBY|NODE_OPTIONS|BASH_ENV|ENV$|GCONV_PATH|GIO_EXTRA|GJS_|"
                    r"ELECTRON_RUN_AS_NODE|QT_PLUGIN_PATH|QML2?_IMPORT)", n)
               for n in names)


def same_file(pid, host_path):
    """host_path = a full path (HOST in front for the PC's own folders). True when the running program's file IS
    this file (same disk and inode), so a copy in a container, a chroot or a user's own mount that only looks
    like /usr/bin/x is not trusted."""
    try:
        a, b = os.stat(os.path.join(PROC, str(pid), "exe")), os.stat(host_path)
    except OSError:
        return False
    return (a.st_dev, a.st_ino) == (b.st_dev, b.st_ino)


def env_value(pid, name):
    try:
        with open(os.path.join(PROC, str(pid), "environ"), "rb") as f:
            for v in f.read().split(b"\0"):
                if v.startswith(name.encode() + b"="):
                    return v.split(b"=", 1)[1].decode("utf-8", "replace")
    except OSError:
        pass
    return ""

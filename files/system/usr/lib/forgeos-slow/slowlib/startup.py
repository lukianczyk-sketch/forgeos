"""Programs that start with the PC (the standard XDG autostart folders), and switching them off or on.

Switching off writes the person's own copy in ~/.config/autostart with Hidden=true (the standard way, so
nothing in the system is changed). Switching on undoes exactly that. Desktop parts are never listed.
"""
import os
import re
import shutil

from . import AUTOSTART, SYS_AUTOSTART, log, read

CORE = re.compile(r"^(org\.kde\.|kde|plasma|polkit|at-spi|xdg-|geoclue|pipewire|wireplumber|forgeos|ibus|fcitx|"
                  r"gnome-keyring|kaccess|baloo|powerdevil|xembed|spice|pam_kwallet|kwallet|gmenudbus|"
                  r"org\.freedesktop\.|ublue|bazzite)", re.I)
MARK = "X-ForgeOS-Slow=off"


def fields(text):
    out = {}
    for line in text.splitlines():
        if line.startswith("[") and out:
            break
        k, eq, v = line.partition("=")
        if eq and k.strip() not in out and not line.startswith("#"):
            out[k.strip()] = v.strip()
    return out


def entries():
    """[{'id','name','on','file'}] of programs that start with the PC, by name."""
    found = {}
    for d in (SYS_AUTOSTART, AUTOSTART):
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for n in names:
            if n.endswith(".desktop"):
                found[n] = os.path.join(d, n)
    out = []
    for n, path in found.items():
        f = fields(read(path))
        only, never, tryx = f.get("OnlyShowIn", ""), f.get("NotShowIn", ""), f.get("TryExec", "")
        if CORE.match(n) or f.get("X-KDE-autostart-phase") or not f.get("Name") or "KDE" in never \
                or (only and "KDE" not in only) or (tryx and not shutil.which(tryx)):
            continue  # desktop parts, and entries that never run on this KDE desktop
        on = f.get("Hidden", "false").lower() != "true" and f.get("X-GNOME-Autostart-enabled", "true").lower() != "false"
        out.append({"id": n[:-8], "name": f["Name"][:40], "on": on, "file": path})
    return sorted(out, key=lambda e: e["name"].lower())


def find(eid):
    return next((e for e in entries() if e["id"] == eid), None)


def switch_off(eid):
    e = find(eid)
    if not e:
        return "That program is not in the start-up list."
    mine = os.path.join(AUTOSTART, eid + ".desktop")
    text = read(e["file"])
    lines = [x for x in text.splitlines() if x.split("=")[0].strip() not in ("Hidden", MARK[:-4])]
    head = lines.index("[Desktop Entry]") + 1 if "[Desktop Entry]" in lines else 0
    extra = ["Hidden=true"] + ([MARK] if e["file"] != mine or MARK in text.splitlines() else [])
    os.makedirs(AUTOSTART, exist_ok=True)
    with open(mine + ".new", "w", encoding="utf-8") as f:
        f.write("\n".join(lines[:head] + extra + lines[head:]) + "\n")
    os.replace(mine + ".new", mine)
    log("start-up off: " + eid)
    return "%s will not start with the PC any more. You can switch it back on here." % e["name"]


def switch_on(eid):
    e = find(eid)
    mine = os.path.join(AUTOSTART, eid + ".desktop")
    if not e or e["on"]:
        return "That program already starts with the PC." if e else "That program is not in the start-up list."
    if e["file"] != mine:
        return "That program was switched off by the system, so it can't be switched on here."
    text = read(mine)
    if MARK in text.splitlines():
        os.remove(mine)
    else:
        off = ("Hidden", "X-GNOME-Autostart-enabled")
        lines = [x for x in text.splitlines() if x.split("=")[0].strip() not in off]
        with open(mine + ".new", "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(mine + ".new", mine)
    log("start-up on: " + eid)
    if not (find(eid) or {}).get("on"):
        return "%s could not be switched on." % e["name"]
    return "%s will start with the PC again." % e["name"]

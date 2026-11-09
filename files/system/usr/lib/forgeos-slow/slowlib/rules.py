"""Which programs are desktop parts (never closed), games (normal to be busy) or hiding (a virus trick).

The kernel cuts program names to 15 letters ("org_kde_powerde"), so desktop parts are also known by their
file (/usr/bin/...) and by the KDE session's own group (session.slice, plasma-*).
"""
import os
import re

from . import HOME

WRAPPERS = ("bwrap", "xdg-dbus-proxy", "flatpak-session-helper", "flatpak-portal")
KEEP = re.compile(r"^(plasma.*|kwin.*|Xwayland|systemd.*|pipewire.*|wireplumber|ollama|kded.*|ksmserver|dbus-.*|sddm.*|"
                  r"bash|sh|ps|kdialog|baloo.*|bwrap|kwallet.*|ksecretd|krunner|kglobalaccel.*|kactivity.*|org_kde_.*|"
                  r"xembed.*|kscreen.*|kaccess|polkit.*|xdg-.*|gvfs.*|at-spi.*|forgeos-.*|.*portal.*|DiscoverNotifie.*|"
                  r"NetworkManager|tuned.*|power-profiles.*|upower.*|udisks.*)$")
KEEP_GROUP = re.compile(r"/session\.slice/|/plasma-[^/]*\.service")
ALLOWED = (".local/share/Steam/", ".steam/", ".var/app/", ".local/share/flatpak/", ".wine/", ".local/share/lutris/",
           ".local/share/bottles/", ".local/share/umu/", ".local/share/applications/", ".local/bin/", ".local/lib/",
           ".cargo/", ".rustup/", ".nvm/", ".npm/", ".vscode/", ".vscode-oss/", ".local/share/JetBrains/", ".deno/",
           ".bun/", ".pyenv/", ".local/share/containers/", ".gradle/", ".m2/", ".local/share/ollama/")


def is_keep(comm, exe, cgroup):
    """True for desktop and system parts: never offered for closing."""
    base = os.path.basename(exe.replace(" (deleted)", ""))
    return bool(KEEP.match(comm) or (base and KEEP.match(base)) or KEEP_GROUP.search(cgroup))


def is_game(comm, exe, arg0, cgroup):
    """A Steam game or a Windows game (Proton / Wine): busy is normal while it runs."""
    cut = len(comm) == 15 and re.search(r"\.(e|ex|exe)$", comm.lower())  # "Cyberpunk2077.e"
    return bool("steam_app" in cgroup or cut or any(x.lower().endswith(".exe") for x in (comm, exe, arg0)))


def suspicious(exe):
    """A program running from a temp folder or a hidden folder in home (crypto-miner tricks). Apps that
    updated themselves ("(deleted)") and AppImages are fine."""
    exe = exe.replace(" (deleted)", "")
    if not exe or exe.startswith("/tmp/.mount_"):
        return False
    home = exe.startswith(HOME + "/")
    if exe.startswith(("/tmp/", "/var/tmp/", "/dev/shm/")) and not home:
        return True
    rel = exe[len(HOME) + 1:] if home else ""
    return bool(rel) and "/." in "/" + rel and not rel.startswith(ALLOWED)

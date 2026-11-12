"""The checked fix list: the ONLY things a Fix it button may do. The library and the AI can only name one
of these; anything else is refused. None of them deletes your files. Each one needs a Yes first (the window
asks), and the ones that change something say so in their label.
"""
import getpass
import os
import re

from . import ENV, run, start

LIBEXEC = ENV("FORGEOS_ERRORS_LIBEXEC") or "/usr/libexec"
# Ask Your PC's own safe fixes (forgeos-askpc fix ID) that need no extra word
ASKPC = {"restart-internet": "Turn the internet connection off and on again",
         "restart-sound": "Restart the sound system",
         "unmute-sound": "Turn the sound on and set the volume to half",
         "restart-taskbar": "Restart the taskbar (your open windows stay open)",
         "clear-thumbnails": "Delete saved picture previews (they are made again when needed)"}
# ForgeOS windows: NAME -> (program, label); the same names Forge Helper uses
WINDOWS = {"cleansweep": ("forgeos-cleansweep-gui", "Open Clean Sweep (virus check)"),
           "undo": ("forgeos-undo-gui", "Open Undo Button"),
           "scamshield": ("forgeos-scamshield-gui", "Open Scam Shield"),
           "willitrun": ("forgeos-willitrun-gui", "Open Will It Run?"),
           "guard": ("forgeos-guard-gui", "Open Always-On Guard"),
           "askpc": ("forgeos-askpc-gui", "Open Ask Your PC"),
           "aisetup": ("forgeos-ai-setup", "Open ForgeOS AI Setup"),
           "autopilot": ("forgeos-autopilot-gui", "Open Driver & BIOS Autopilot"),
           "drivehealth": ("forgeos-drivehealth-gui", "Open Drive Death Warning"),
           "techguard": ("forgeos-techguard-gui", "Open Fake Tech Support Guard"),
           "slow": ("forgeos-slow-gui", "Open Why Is It Slow? (it can free up space too)"),
           "privacy": ("forgeos-privacy-gui", "Open Privacy Report"),
           "helper": ("forgeos-helper-gui", "Ask Forge Helper")}
# System Settings pages a card may open
SETTINGS = {"kcm_printer_manager": "Open the printer settings",
            "kcm_networkmanagement": "Open the Wi-Fi and internet settings",
            "kcm_bluetooth": "Open the Bluetooth settings",
            "kcm_pulseaudio": "Open the sound settings",
            "kcm_kscreen": "Open the screen settings",
            "kcm_clock": "Open the date and time settings",
            "kcm_users": "Open the user and password settings"}
OTHER = {"print-queue": "Clear stuck print jobs (your waiting printouts are removed; print them again after)",
         "techguard:escape": "Close all web browsers now (the scary page too)",
         "family-call": "Call my helper so they can see the screen"}


def has_guide(name):
    share = ENV("FORGEOS_SHOWME_SHARE") or "/usr/share/forgeos/showme"
    return bool(re.fullmatch(r"[a-z0-9-]{1,40}", name)) and os.path.isfile(os.path.join(share, "guides", name + ".txt"))


def desktop(name):
    """The menu entry file for a program that crashed (reopen:NAME), or None."""
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,80}", name):
        return None
    home = ENV("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    for base in [home] + (ENV("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") + \
            ["/var/lib/flatpak/exports/share", os.path.join(home, "flatpak/exports/share")]:
        path = os.path.join(base, "applications", name + ".desktop")
        if os.path.isfile(path):
            return path
    return None


def label(fix):
    """The button's words, or "" when FIX is not on the checked list."""
    kind, _, arg = fix.partition(":")
    if kind == "askpc":
        return ASKPC.get(arg, "")
    if kind == "open":
        return WINDOWS[arg][1] if arg in WINDOWS else ""
    if kind == "settings":
        return SETTINGS.get(arg, "")
    if kind == "showme":
        return "Show me where to click" if has_guide(arg) else ""
    if kind == "reopen":
        return "Open it again" if desktop(arg) else ""
    return OTHER.get(fix, "")


def ok(fix):
    return bool(label(fix))


def allowed():
    """Every fix the AI may pick from (reopen and showme are added by the error itself)."""
    return (["askpc:" + k for k in ASKPC] + ["open:" + k for k in WINDOWS] +
            ["settings:" + k for k in SETTINGS] + list(OTHER))


def do(fix):
    """Run a checked fix. Returns (exit code, plain message). Not on the list = refused (3)."""
    if not ok(fix):
        return 3, "That fix is not on the checked list, so it was not done."
    kind, _, arg = fix.partition(":")
    if kind == "askpc":
        code, out = run(["forgeos-askpc", "fix", arg], 120)
        return (0 if code == 0 else 1), (out.strip() or "Done.") if code == 0 else "That fix did not work."
    if kind == "open":
        return (0, "Opening...") if start([WINDOWS[arg][0]]) else (1, "That window could not be opened.")
    if kind == "settings":
        return (0, "Opening...") if start(["systemsettings", arg]) else (1, "System Settings could not open.")
    if kind == "showme":
        return (0, "Look at the screen: a yellow arrow shows you where to click.") \
            if start(["forgeos-showme", "guide", arg]) else (1, "Show Me How could not start.")
    if kind == "reopen":
        return (0, "Opening it again...") if start(["kioclient", "exec", desktop(arg)]) else (1, "It could not be opened.")
    if fix == "print-queue":
        code, _ = run(["cancel", "-a", "-u", getpass.getuser()], 30)  # only your own print jobs
        return (0, "The stuck print jobs are cleared. Print again.") if code == 0 else (1, "The print jobs could not be cleared.")
    if fix == "techguard:escape":
        code, _ = run(["forgeos-techguard", "escape"], 30)
        return (0, "The web browsers are closed.") if code == 0 else (1, "Close it yourself: hold Alt and press F4.")
    ok_ = start([os.path.join(LIBEXEC, "forgeos-family-call")])
    return (0, "Calling your helper...") if ok_ else (1, "Call for help could not start.")

"""The ONLY changes Why Is It Slow? can make. The window runs each one after the person says Yes.

Every fix is logged (~/.local/state/forgeos/slow/fixes.log). The power mode and start-up programs can be
switched back; closed programs can be opened again; downloads go to the Trash.
"""
from . import SETTINGS, load_json, log, run, save_json, start
from . import procs, space, startup

MODES = ("balanced", "performance", "power-saver")


def power(mode):
    if mode == "undo":
        mode = load_json(SETTINGS).get("power_before", "")
        if mode not in MODES:
            return "There is nothing to switch back."
    elif mode not in MODES:
        return "Unknown power mode."
    code, before = run(["powerprofilesctl", "get"], 10)
    if code == 0 and before.strip() in MODES:
        save_json(SETTINGS, dict(load_json(SETTINGS), power_before=before.strip()))
    code, _ = run(["powerprofilesctl", "set", mode], 20)
    if code != 0:
        return "The power mode could not be changed."
    log("power mode: " + mode)
    return "Power mode is now %s." % mode.replace("-", " ").title()


def pause(job):
    if job != "find":
        return "Only Find Anything can be paused here."
    run(["systemctl", "--user", "stop", "forgeos-find-index.service"], 30)
    log("paused Find Anything")
    return "Find Anything is paused. It carries on by itself later."


def restart():
    log("restart")
    if run(["busctl", "--user", "call", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown", "logoutAndReboot"],
           30)[0] != 0:  # KDE asks every program to save first
        run(["systemctl", "reboot"], 30)
    return "Restarting..."


def fix(args):
    """Run one fix; returns (exit code, sentence)."""
    name, rest = (args[0], args[1:]) if args else ("", [])
    if name == "close" and len(rest) == 2 and rest[0].isdigit():
        text = procs.close(rest[0], rest[1])
        log("close %s %s: %s" % (rest[0], rest[1], text))
        return (0 if text.endswith("asked to close.") else 1), text
    one = {"power": power, "pause": pause, "startup-off": startup.switch_off, "startup-on": startup.switch_on,
           "trash": space.to_trash}
    if name in one and len(rest) == 1:
        return 0, one[name](rest[0])
    none = {"empty-trash": space.empty_trash, "thumbs": space.clear_thumbs, "unused-apps": space.unused_apps,
            "restart": restart}
    if name in none and not rest:
        return 0, none[name]()
    if name == "internet" and not rest:
        code, out = run(["forgeos-askpc", "fix", "restart-internet"], 90)
        log("restart the internet")
        return (0 if code == 0 else 1), (out.strip() or "The internet was restarted.")
    if name in ("cleansweep", "drivehealth") and not rest:
        start(["forgeos-%s-gui" % name])
        return 0, "Opening %s..." % ("Clean Sweep" if name == "cleansweep" else "Drive Health")
    return 3, "Unknown fix."

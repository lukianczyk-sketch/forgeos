"""More look-only tools: GhostFinder, Guard, Undo, Privacy, Clean Sweep, Family Mode, Panic.

Same shape as tools.py: each returns (text, actions, level). LOOK maps every tool name to its look.
"""
import os

from . import run, tools
from .tools import family, plain, win


def ghost_sweep(_arg):
    code, out = run(["forgeos-ghost", "sweep", "--secs", "15"], 120)
    text = plain(out) if code != 127 else "GhostFinder could not run."
    return text, win("ghost", "Open GhostFinder"), -1


def guard_status(_arg):
    code, out = run(["forgeos-guard", "status"], 30)
    f = {}
    for p in (x.split("\t") for x in out.splitlines()):
        if len(p) >= 2:
            f[p[0] + p[1] if p[0] == "GUARD" else p[0]] = p[2] if p[0] == "GUARD" and len(p) > 2 else p[1]
    if code != 0 or not f:
        return "Always-On Guard could not be checked.", win("guard", "Open Always-On Guard"), -1

    def onoff(k):
        return "on" if f.get(k) == "on" else "OFF"
    lines = ["Always-On Guard is %s." % ("running" if f.get("SERVICE") == "running" else "NOT running"),
             "Checking downloads: %s. Checking email: %s." % (onoff("GUARDdownloads"), onoff("GUARDemail")),
             "Blocking bad websites: %s." % onoff("GUARDwebsites"),
             "Files locked away: %s. Warnings so far: %s." % (f.get("LOCKED", "0"), f.get("WARNINGS", "0"))]
    code, out = run(["forgeos-guard", "events", "3"], 30)
    last = [x.split("\t") for x in out.splitlines() if x.count("\t") >= 4]
    if last:
        lines.append("Latest:")
        lines += ["- %s: %s %s" % (e[0][:16], e[1], os.path.basename(e[3])[:60]) for e in last]
    return "\n".join(lines), win("guard", "Open Always-On Guard"), -1


def drivers(_arg):
    code, out = run(["forgeos-autopilot", "check"], 300)
    text = plain(out) if code in (0, 1, 2) else "Drivers & BIOS could not be checked."
    return text, win("autopilot", "Open Drivers & BIOS"), -1


def switch_windows(_arg):
    code, out = run(["forgeos-switch", "status"], 30)
    if code == 0 and "WINDOWS\tfound" in out:
        return ("Windows 11 is on this PC too. \"Restart into Windows\" restarts into Windows one time; next time"
                " the PC starts, ForgeOS starts again."), win("switch", "Open Windows & ForgeOS"), -1
    return "Windows was not found on this PC, so there is nothing to switch to.", [], -1


def moving_day(_arg):
    return ("Moving Day brings your files, bookmarks and saved passwords over from Windows: the Windows drive on"
            " this PC, an old PC's drive, or a Moving Box USB stick. Nothing on Windows is changed."), win("movingday", "Open Moving Day"), -1


def drive_health(_arg):
    code, out = run(["forgeos-drivehealth", "report"], 60)
    text = plain(out) if code in (0, 1, 2, 3) else "Drive Health could not run."
    return text, win("drivehealth", "Open Drive Health"), -1


def ransomware(_arg):
    code, out = run(["forgeos-tripwire", "report"], 60)
    text = plain(out) if code in (0, 1, 3) else "Ransomware Tripwire could not be checked."
    return text + "\nNever pay a ransom: \"Put my files back\" brings them back from the Undo Button.", win("tripwire", "Open Ransomware Tripwire"), -1


def tech_support(_arg):
    code, out = run(["forgeos-techguard", "report"], 60)
    text = plain(out) if code in (0, 1, 3) else "Fake Tech Support Guard could not be checked."
    return text, win("techguard", "Open Fake Tech Support Guard"), -1


def digital_will(_arg):
    code, out = run(["forgeos-digitalwill", "report"], 60)
    text = plain(out) if code in (0, 1) else "Digital Will could not be checked."
    return text, win("digitalwill", "Open Digital Will"), -1


def find_my_pc(_arg):
    code, out = run(["forgeos-locate", "report"], 30)
    text = plain(out) if code in (0, 1) else "Find My PC could not be checked."
    return text, win("locate", "Open Find My PC"), -1


def undo_open(_arg):
    code, _out = run(["forgeos-undo", "status"], 30)
    if code == 0:
        return ("Undo Button keeps earlier copies of your files. It can bring back a deleted file"
                " or an older version."), win("undo", "Open Undo Button"), -1
    return ("Undo Button is not turned on yet, so there are no earlier copies. Open it to turn it on."), win("undo", "Open Undo Button"), -1


def privacy_report(_arg):
    code, out = run(["forgeos-privacy", "report", "7"], 60)
    return (plain(out, 1200) if code == 0 else "Privacy Report could not run."), win("privacy", "Open Privacy Report"), -1


def cleansweep_scan(_arg):
    return ("Clean Sweep checks the whole PC for viruses and hackers and locks anything bad away"
            " (nothing is deleted). It asks for your password. Always-On Guard is also checking every"
            " download and email."), win("cleansweep", "Open Clean Sweep"), -1


def text_bigger(arg):
    size = arg if arg in ("big", "bigger") else "big"
    if family().get("STATUS") == "on":
        return "I can make the text %s." % size, [("text_size", size, "Make the text %s" % size)], -1
    return ("Family Mode makes text and the mouse pointer bigger and the desktop simpler."
            " You can turn it off again any time."), [("family_on", size, "Turn on Family Mode (%s text)" % size)], -1


def family_call(_arg):
    who = family().get("HELPER", "-")
    if who in ("", "-"):
        return ("No family helper is set up yet. Open Family Mode and pick \"Set up my helper\"."), win("family", "Open Family Mode"), -1
    return "%s can see your screen and help. They will get a code to connect." % who, [("family_call", "", "Call %s for help" % who)], -1


def panic(_arg):
    return ("Panic Button cuts the camera, every microphone and the internet, then locks the screen."
            " You can also press Meta+Shift+Esc any time. All Clear in the menu turns it all back on."), [("panic", "", "Panic now")], -1




LOOK = {name: globals().get(name) or getattr(tools, name, None) for name in tools.TOOLS}

"""Family Mode "safety on": check every ForgeOS guard, and switch on the ones a user may switch on.

Your own guards (user units) are turned on right away. The PC-wide ones need a password,
so they are only checked and shown; Ask Your PC or your helper can turn them back on.
"""
from . import run

MINE = [("forgeos-privacy-watch.service", "Privacy Report - tells you when an app uses your camera or microphone"),
        ("forgeos-ghost-watch.timer", "GhostFinder - warns you if a tracker is following you")]
PC_WIDE = [("clamav-freshclam.service", "Virus checker (ClamAV) - new virus list every day"),
           ("forgeos-cleansweep.timer", "Clean Sweep - virus and hacker scan every week"),
           ("forgeos-scamshield-update.timer", "Scam Shield - new list of scam websites every day"),
           ("forgeos-willitrun-update.timer", "Will It Run? - new list of games with anti-cheat every day"),
           ("snapper-timeline.timer", "Undo Button - a saved copy of your files every hour")]


def enabled(unit, user):
    cmd = ["systemctl"] + (["--user"] if user else []) + ["is-enabled", unit]
    code, out = run(cmd, timeout=10)
    return code == 0 and out.strip() in ("enabled", "enabled-runtime", "static", "alias", "indirect")


def check(turn_on=True):
    """[(state, text)]: state 'on', 'turned-on', 'off' (yours, could not turn on) or 'needs-password'."""
    found = []
    for unit, text in MINE:
        if enabled(unit, True):
            found.append(("on", text))
        elif turn_on and run(["systemctl", "--user", "enable", "--now", unit], timeout=30)[0] == 0:
            found.append(("turned-on", text))
        else:
            found.append(("off", text))
    for unit, text in PC_WIDE:
        found.append(("on" if enabled(unit, False) else "needs-password", text))
    return found


WORDS = {"on": "On", "turned-on": "Turned on now", "off": "OFF - could not turn it on",
         "needs-password": "OFF - ask your helper to turn it on (needs a password)"}

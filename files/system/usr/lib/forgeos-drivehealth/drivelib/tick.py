"""The quiet user timer (12 minutes after login, then every 2 hours).

Danger: a big warning (a kdialog window; during a game or video a critical note, which shows over
full-screen apps) with "Back up now". It comes back every day until a backup newer than the warning exists.
After that, a gentle weekly reminder to replace the drive. No backup set up at all: one note a month.
Early signs (watch) are Forge Helper's job (it already limits itself to 3 notes a day).
"""
from . import DAY, GUI, USER_STATE, load_json, now, run, save_json, start
from . import backup, report

AGAIN = 20 * 3600


def busy():
    """True while a game or a full-screen video is playing (same check as Forge Helper)."""
    code, out = run(["busctl", "--user", "call", "org.freedesktop.PowerManagement.Inhibit",
                     "/org/freedesktop/PowerManagement/Inhibit", "org.freedesktop.PowerManagement.Inhibit",
                     "HasInhibit"], 10)
    if code == 0 and out.strip() == "b true":
        return True
    code, out = run(["gamemoded", "-s"], 10)
    if code == 0 and "is active" in out:
        return True
    return run(["pgrep", "-x", "gamescope"], 10)[0] == 0


def note(text, button, urgent=False):
    """A desktop note with one button. True when the button was clicked."""
    code, out = run(["notify-send", "--app-name=Drive Health", "--icon=drive-harddisk", "--wait",
                     "--urgency=" + ("critical" if urgent else "normal"), "--action=go=" + button,
                     "--action=later=Not now", "Drive Health", text], 3600)
    return code == 0 and out.strip() == "go"


def warn(text):
    """The big danger warning. True when the user picked Back up now."""
    if busy():
        return note(text, "Back up now", True)
    code, _out = run(["kdialog", "--title", "Drive Health", "--warningyesno", text,
                      "--yes-label", "Back up now", "--no-label", "Remind me tomorrow"], 3600)
    return code == 0


def main():
    r, b, t = report.load(), backup.status(), now()
    st = load_json(USER_STATE)
    if r and r["level"] == "danger":
        bad = [d for d in r["drives"] if d["level"] == "danger"]
        name = bad[0]["name"] if bad else "a drive"
        if b["set"] and b["last"] > r.get("danger_since", 0):
            if t - st.get("replace_told", 0) < 7 * DAY:
                return 2
            st["replace_told"] = t
            save_json(USER_STATE, st, 0o600)
            if note("Your files are backed up. %s may still fail - plan to replace it soon (a PC shop can help)."
                    % name, "Show me"):
                start([GUI])
            return 2
        if t - st.get("danger_told", 0) < AGAIN:
            return 2
        st["danger_told"] = t
        save_json(USER_STATE, st, 0o600)
        why = bad[0]["reasons"][0] if bad and bad[0].get("reasons") else ""
        text = ("Your drive may be failing: %s.\n\nBack up your files today, while they can still be read.\n\nWhy: %s"
                % (name, why))
        if warn(text):
            start([GUI, "--backup"])
        return 2
    if r and not b["set"] and t - st.get("nobackup_told", 0) >= 30 * DAY and not busy():
        st["nobackup_told"] = t
        save_json(USER_STATE, st, 0o600)
        if note("You have no backup yet. Drives can die with no warning at all - a backup keeps your photos and "
                "papers safe.", "Set up a backup"):
            start([GUI, "--backup"])
    return report.code(r) if r else 3

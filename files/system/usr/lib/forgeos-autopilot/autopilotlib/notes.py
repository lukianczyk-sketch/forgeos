"""Pop-ups: a note with buttons that waits for an answer, or a short note that doesn't wait."""
from . import GUI, run, start

APP = "--app-name=Drivers & BIOS"
WAIT = 3600


def ask(title, text, buttons, urgent=False):
    """Show a note with buttons [(key, label)]. Returns the key clicked, or '' (closed / timed out)."""
    cmd = ["notify-send", APP, "--icon=preferences-system", "--wait",
           "--urgency=" + ("critical" if urgent else "normal")]
    cmd += ["--action=%s=%s" % (key, label) for key, label in buttons]
    code, out = run(cmd + [title, text], WAIT)
    answer = out.strip().splitlines()[-1] if code == 0 and out.strip() else ""
    return answer if answer in [k for k, _ in buttons] else ""


def tell(title, text, urgent=False):
    """A short note; does not wait."""
    return start(["notify-send", APP, "--icon=preferences-system",
                  "--urgency=" + ("critical" if urgent else "normal"), title, text])


def window(*args):
    """Open the Drivers & BIOS window (e.g. window('--devices'))."""
    return start([GUI] + list(args))


def restart():
    """Ask KDE to restart the PC the normal way (programs get the chance to save first)."""
    code, _out = run(["busctl", "--user", "call", "org.kde.Shutdown", "/Shutdown",
                      "org.kde.Shutdown", "logoutAndReboot"], 30)
    return code == 0

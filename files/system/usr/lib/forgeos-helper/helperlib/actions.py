"""Actions: the ONLY things Forge Helper can change, and only after the user clicks Yes.

The window runs 'forgeos-helper run ACTION ARG --yes'; everything is checked again here.
"""
import os
import re
import subprocess

from . import SHARE, config_dir, read_lines, run
from .ai import QUICK_DEFAULT

FIX_IDS = ("restart-internet restart-sound unmute-sound restart-taskbar close-busy-app clear-thumbnails "
           "empty-trash open-cleansweep open-undo open-privacy open-scamshield open-backup").split()
WINDOWS = {"cleansweep": "forgeos-cleansweep-gui", "undo": "forgeos-undo-gui", "privacy": "forgeos-privacy-gui",
           "scamshield": "forgeos-scamshield-gui", "find": "forgeos-find-gui", "willitrun": "forgeos-willitrun-gui",
           "ghost": "forgeos-ghost-gui", "guard": "forgeos-guard-gui", "family": "forgeos-family-gui",
           "askpc": "forgeos-askpc-gui", "aisetup": "forgeos-ai-setup", "autopilot": "forgeos-autopilot-gui",
           "switch": "forgeos-switch-gui", "movingday": "forgeos-movingday-gui", "drivehealth": "forgeos-drivehealth-gui",
           "tripwire": "forgeos-tripwire-gui", "techguard": "forgeos-techguard-gui",
           "digitalwill": "forgeos-digitalwill-gui"}
SIZES = ("big", "bigger")
# The ONLY actions 'do' runs. Each needs the user's Yes click first (the window asks).
ACTIONS = ("pc_fix", "text_size", "family_on", "family_call", "panic", "open", "open_file", "forget_all", "get_model")


def libexec():
    return os.environ.get("FORGEOS_HELPER_LIBEXEC") or "/usr/libexec"


def start(cmd):
    """Start a window in the background. Returns True when it could be started."""
    try:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def fix_ids():
    """Ask Your PC's safe fixes, read from its own list so both always agree."""
    try:
        with open(os.path.join(libexec(), "forgeos-askpc-fixes"), encoding="utf-8") as f:
            m = re.search(r'^FIX_IDS="([a-z -]+)"', f.read(), re.M)
        return m.group(1).split() if m else FIX_IDS
    except OSError:
        return FIX_IDS


def allowed_models():
    """The quick model plus the free models on the candidate list (never anything else)."""
    names = [QUICK_DEFAULT]
    for line in read_lines(os.path.join(SHARE, "candidates.txt")):
        if not line.startswith("#") and line.split():
            names.append(line.split()[0])
    return names


def check_action(action, arg):
    """None when ACTION ARG is allowed, else the reason it is not."""
    if action not in ACTIONS:
        return "Forge Helper does not know how to do \"%s\"." % action
    if action == "pc_fix" and arg.split(" ")[0] not in fix_ids():
        return "That is not one of Ask Your PC's safe fixes."
    if action in ("text_size", "family_on") and arg not in SIZES:
        return "Text size must be big or bigger."
    if action == "open" and arg not in WINDOWS:
        return "Forge Helper does not know that window."
    home = os.path.realpath(os.path.expanduser("~")) + "/"
    if action == "open_file" and not (os.path.realpath(arg).startswith(home) and os.path.isfile(arg)):
        return "Forge Helper only opens your own files."
    if action == "get_model" and arg not in allowed_models():
        return "Forge Helper only downloads the free AI models on its own list."
    return None


def do(action, arg):
    """Run one action the user said Yes to. Returns (exit code, plain message)."""
    problem = check_action(action, arg)
    if problem:
        return 2, problem
    if action == "pc_fix":
        words = arg.split(" ", 1)
        code, out = run(["forgeos-askpc", "fix"] + words, 120)
        return (0 if code == 0 else 1), out.strip() or ("Done." if code == 0 else "That did not work.")
    if action == "text_size":
        code, out = run(["forgeos-family", "size", arg], 60)
        return (0 if code == 0 else 1), out.strip()
    if action == "family_on":
        code, out = run(["forgeos-family", "on", "--size", arg], 120)
        return (0 if code == 0 else 1), out.strip()
    if action == "family_call":
        ok = start([os.path.join(libexec(), "forgeos-family-call")])
        return (0 if ok else 1), "Calling your helper..." if ok else "Call for help could not start."
    if action == "panic":
        code, out = run(["forgeos-panic", "on"], 60)
        return (0 if code == 0 else 1), out.strip() or "Panic Button is on."
    if action == "open":
        ok = start([WINDOWS[arg]])
        return (0 if ok else 1), "Opening..." if ok else "That window could not be opened."
    if action == "open_file":
        ok = start(["xdg-open", arg])
        return (0 if ok else 1), "Opening " + os.path.basename(arg)
    if action == "forget_all":
        from . import memory
        memory.forget_all()
        return 0, "Done. I forgot everything you told me to remember, and your thumbs up and down."
    if run(["ollama", "pull", arg], 3600)[0] != 0:
        return 1, "The download did not work. Check the internet and try again."
    if arg == QUICK_DEFAULT:
        os.makedirs(config_dir(), exist_ok=True)
        with open(os.path.join(config_dir(), "ai-quick-model"), "w", encoding="utf-8") as f:
            f.write(arg + "\n")
        return 0, "The quick brain is ready. Answers will come faster now."
    return 0, "Downloaded. Forge Helper tests it this week and uses it only if it answers better."

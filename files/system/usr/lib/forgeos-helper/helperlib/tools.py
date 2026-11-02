"""The fixed list of tools Forge Helper may use. The AI can only pick a name from TOOLS.

Asking never changes the PC: these tools only LOOK. A change is offered as an action
(see actions.py) that the window turns into a button. Each look returns (text, actions, level);
actions are (action, argument, button label); level is Scam Shield's 0-2 (else -1).
"""
import os

from . import run

TOOLS = {
    "scam_check": "check a message, email, link, phone call or pop-up for scams (text = the message)",
    "pc_question": "a problem with this PC: sound, internet, Wi-Fi, slow, frozen, full disk, battery, updates",
    "pc_fix": "one safe fix from the fix list when the user asks to fix that exact thing",
    "find": "find the user's own files, photos, letters or papers (text = what to look for)",
    "will_it_run": "will a program, game or Windows .exe run on this PC (text = program name)",
    "ghost_sweep": "look for hidden cameras, trackers (AirTags) and strange devices nearby",
    "guard_status": "what Always-On Guard blocked or caught (downloads, websites, email)",
    "drivers": "drivers, BIOS, firmware or a part with no driver: up to date? what changed after an update?",
    "undo_open": "get back a deleted or changed file or an older version",
    "privacy_report": "which apps used the camera, microphone or screen",
    "cleansweep_scan": "the user thinks the PC is hacked or has a virus",
    "text_bigger": "make text and the mouse pointer bigger, easier to see",
    "family_call": "call the family helper so they can see the screen and help",
    "panic": "cut the camera, microphones and internet right now and lock the screen",
    "help_answer": "how do I... questions about using the PC (answered from ForgeOS help)",
    "just_answer": "anything else: chat, general questions, or a request no tool can do",
}
SLOW = 180


def family():
    """Family Mode facts from 'forgeos-family status': {'STATUS': 'on', 'SIZE': ..., 'HELPER': ...}."""
    code, out = run(["forgeos-family", "status"], 20)
    facts = {}
    for line in out.splitlines() if code == 0 else []:
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0] in ("STATUS", "SIZE", "HELPER"):
            facts[parts[0]] = parts[1]
    return facts


def plain(out, limit=1500):
    """The lines meant for people (not the TAB-separated or VERDICT/WAY/FIX lines for windows)."""
    keep = [x for x in out.splitlines() if "\t" not in x and not x.startswith(("VERDICT:", "WAY:", "FIX:"))]
    return "\n".join(keep)[:limit].strip()


def win(name, label):
    return [("open", name, label)]


def scam_check(arg):
    code, out = run(["forgeos-scamshield", "check", "-"], SLOW, stdin=arg)
    if code not in (0, 1, 2):
        return ("Scam Shield could not check it. Do not click links or call numbers in it until someone"
                " you trust has looked."), win("scamshield", "Open Scam Shield"), 1
    return plain(out), [], code


def pc_question(arg):
    code, out = run(["forgeos-askpc", "ask", arg], SLOW)
    if code == 127:
        return "Ask Your PC could not run.", win("askpc", "Open Ask Your PC"), -1
    acts = []
    label = next((x[15:].rstrip(".") for x in out.splitlines() if x.startswith("Suggested fix: ")), "")
    for line in out.splitlines():
        if line.startswith("FIX: "):
            acts.append(("pc_fix", line[5:].strip(), "Fix it: " + (label or line[5:].strip())))
    return plain(out), acts, -1


def fix_list():
    code, out = run(["forgeos-askpc", "fixes"], 30)
    rows = [x.split("\t") for x in out.splitlines()] if code == 0 else []
    return {p[0]: p for p in rows if len(p) >= 2}


def pc_fix(arg):
    fixes = fix_list()
    if arg not in fixes:
        return pc_question(arg)
    p = fixes[arg]
    full = arg + (" " + p[2] if len(p) > 2 and p[2] else "")
    return "I can do this for you: %s." % p[1], [("pc_fix", full, "Fix it: " + p[1])], -1


def find(arg):
    code, out = run(["forgeos-find", "ask", arg], SLOW)
    rows = [x.split("\t") for x in out.splitlines() if x.startswith("RESULT\t")]
    if code == 0 and rows:
        home = os.path.expanduser("~")
        lines = ["I found these files:"]
        for r in rows[:5]:
            where = os.path.dirname(r[1]).replace(home, "your home folder", 1)
            lines.append("- %s  (in %s, %s)" % (os.path.basename(r[1]), where, r[3] if len(r) > 3 else ""))
        acts = [("open_file", r[1], "Open " + os.path.basename(r[1])) for r in rows[:3]]
        return "\n".join(lines), acts + win("find", "Search in Find Anything"), -1
    if code == 2:
        return ("Find Anything has not finished reading your files yet. Open it and it will build"
                " its search list."), win("find", "Open Find Anything"), -1
    return ("I could not find it. Try other words, or a word you know is inside the file."), win("find", "Open Find Anything"), -1


def will_it_run(arg):
    code, out = run(["forgeos-willitrun", "check", arg], SLOW)
    if code in (3, 127):
        return "Will It Run? could not check \"%s\". Open it and pick the file." % arg, win("willitrun", "Open Will It Run?"), -1
    return plain(out), win("willitrun", "Open Will It Run?"), -1

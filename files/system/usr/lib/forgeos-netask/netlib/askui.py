"""The questions on the person's screen. Root runs each kdialog window as the person (dialog.window) and reads
its EXIT CODE itself: a program in their account can't type an answer for them, and a window that was killed
or ran out of time counts as no answer (= blocked for now). All windows share one time budget.

ask(uid, env, [mode, ...], seconds) -> one word:
  normal NAME TO KIND PATH  -> allow | block | once     red NAME TO WHERE PATH -> block | once
  remote NAME TO APP PATH   -> block | allow            confirm TEXT -> yes | no
  later N NAME1 NAME2 ...   -> "1,3" (the ticked ones) | none
"""
import time

from . import ASK_SECONDS, ENV, clean, home_of
from . import dialog

TITLE = "Ask Before Connecting"
CLI = ENV("FORGEOS_NETASK_CLI") or "/usr/bin/forgeos-netask"
NL = "\n"


def ask(uid, env, args, seconds):
    end = time.monotonic() + seconds

    def kd(most, *argv):
        return dialog.window(uid, env, ["kdialog", "--title", TITLE] + list(argv), min(most, end - time.monotonic()))

    mode, rest = (args[0], args[1:]) if args else ("", [])
    if mode == "normal" and len(rest) >= 4:
        return normal(uid, env, kd, rest[0], rest[1], rest[3], end)
    if mode == "red" and len(rest) >= 4:
        text = ("Careful: a program %s wants the internet.%s%s (to reach %s)%sFrom: %s%sReal programs don't usually "
                "do this - trojans hide there. Block it unless you just installed it yourself."
                % (rest[2], NL * 2, rest[0], rest[1], NL, short(rest[3], uid), NL * 2))
        code, _ = kd(ASK_SECONDS, "--warningyesnocancel", text, "--yes-label", "Block", "--no-label",
                     "Allow just this once", "--cancel-label", "Block and check it with Clean Sweep")
        if code == 2:
            dialog.start(uid, env, ["forgeos-cleansweep-gui"])
        return {0: "block", 1: "once", 2: "block"}.get(code, "")
    if mode == "remote" and len(rest) >= 4:
        code, _ = kd(ASK_SECONDS, "--warningyesno", "%s wants to use the internet. It is a remote-control app (%s): "
                     "it lets someone see and control this PC.%sIs someone you don't know asking you to install or use "
                     "it? Fake tech support callers do this.%sReal companies never call you to fix your computer."
                     % (rest[0], rest[2], NL * 2, NL), "--yes-label", "Yes, a stranger asked me - Block it",
                     "--no-label", "No, I set it up myself - Allow")
        return {0: "block", 1: "allow"}.get(code, "")
    if mode == "confirm" and len(rest) == 1:
        code, _ = kd(90, "--yesno", rest[0], "--yes-label", "Yes", "--no-label", "No")
        return "yes" if code == 0 else "no"
    if mode == "later" and len(rest) >= 2:
        items = []
        for i, name in enumerate(rest[1:], 1):
            items += [str(i), name, "off"]
        text = ("While you were busy (a game or away), these %d program(s) tried to use the internet.%sThey were "
                "blocked for now. Tick the ones to allow:" % (len(rest) - 1, NL))
        code, out = kd(300, "--checklist", text, *items)
        picked = [x.strip('"') for x in out.split()] if code == 0 else []
        return ",".join(x for x in picked if x.isdigit()) or "none"
    return ""


def short(path, uid):
    home = home_of(uid)
    return clean("~" + path[len(home):] if home and path.startswith(home + "/") else path, 120)


def normal(uid, env, kd, name, to, path, end):
    text = ("%s wants to use the internet%s(to reach %s).%sFrom: %s%sAllow it? Your answer is remembered, so you are "
            "asked only once.%sNot sure? Press Block - you can change it any time in Who Uses the Internet."
            % (name, NL, to, NL, short(path, uid), NL * 2, NL))
    most = ASK_SECONDS
    for _ in range(3):
        code, _ = kd(most, "--yesnocancel", text, "--yes-label", "Allow", "--no-label", "Block",
                     "--cancel-label", "Other choices...")
        if code in (0, 1):
            return "allow" if code == 0 else "block"
        if code != 2:
            return ""
        code, pick = kd(60, "--menu", "%s wants to use the internet." % name, "once", "Just this once",
                        "what", "What is this? (the private AI explains)", "block", "Block")
        pick = pick.strip() if code == 0 else ""
        if pick in ("once", "block"):
            return pick
        if pick != "what":
            return ""
        _, say = dialog.window(uid, env, [CLI, "explain", name, path], min(60, end - time.monotonic() - 20))
        kd(60, "--msgbox", clean(say, 600) or "I could not find out what %s is. If you did not just install or open "
           "it yourself, Block is the safe answer." % name)
        most = 60
    return ""

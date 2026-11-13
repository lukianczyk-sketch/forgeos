"""Looks for the newer jobs (looks.py and tools.py are full). Same shape as tools.py: each returns (text, actions, level)."""
from . import run
from .actions import WINDOWS
from .netask import net_access  # noqa: F401 - Ask Before Connecting (Job 24), found by looks.LOOK
from .tools import SLOW, plain, win

ERR_OPEN = {"open": "open", "askpc": "pc_fix", "showme": "showme"}


def why_slow(_arg):
    code, out = run(["forgeos-slow", "report"], 150)
    text = plain(out) if code in (0, 1) else "Why Is It Slow? could not check the PC."
    return text, win("slow", "Open Why Is It Slow?"), -1


def will_it_run(arg):
    code, out = run(["forgeos-willitrun", "check", arg], SLOW)
    if code in (3, 127):
        return "Will It Run? could not check \"%s\". Open it and pick the file." % arg, win("willitrun", "Open Will It Run?"), -1
    return plain(out), win("willitrun", "Open Will It Run?"), -1


def report_card(_arg):
    code, out = run(["forgeos-reportcard", "report"], 240)
    text = plain(out, 3000) if code in (0, 1) and out.strip() else "PC Report Card could not grade the PC right now."
    return text, win("reportcard", "Open PC Report Card"), -1


def show_me(arg):
    """Show Me How (Job 22): a built-in guide when one fits, else the private AI pointing at real words."""
    code, out = run(["forgeos-showme", "find", arg], 20)
    parts = out.strip().split("\t")
    if code == 0 and len(parts) == 3:
        text = ("I can show you on the screen: %s. A yellow arrow points at each thing to click."
                " You do the clicking." % parts[2])
        return text, [("showme", parts[1], "Show me on the screen")], -1
    text = ("There is no built-in guide for that yet. Show Me How can still try with the private AI,"
            " pointing only at words that are really on your screen.")
    return text, [("showme", "ask:" + arg[:200], "Try Show Me How")], -1


def explain_error(arg):
    """Plain-English Errors (Job 23): the error's card. Only fixes the helper itself knows become buttons."""
    code, out = run(["forgeos-errors", "explain", "-"], SLOW, stdin=arg)
    if code != 0:
        recent = [x.split("\t")[4] for x in run(["forgeos-errors", "recent", "7"], 20)[1].splitlines()
                  if x.startswith("ITEM\t") and len(x.split("\t")) > 4][:3]
        text = ("Copy the error's words and paste them here, or press Meta+Shift+E while the error is on the screen."
                + (" This week: " + "; ".join(recent) + "." if recent else ""))
        return text, win("errors", "Open What Went Wrong"), -1
    acts = []
    for line in out.splitlines():
        p = line.split("\t")
        kind, _, what = p[1].partition(":") if p[0] == "FIX" and len(p) == 3 else ("", "", "")
        if kind in ERR_OPEN and (kind != "open" or what in WINDOWS):
            acts.append((ERR_OPEN[kind], what, p[2]))
        elif p[0] == "SHOW" and len(p) == 2:
            acts.append(("showme", p[1], "Show me where to click"))
    return plain(out), acts + win("errors", "Open What Went Wrong"), -1

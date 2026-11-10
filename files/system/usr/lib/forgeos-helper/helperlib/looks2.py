"""Looks for the newer jobs (looks.py and tools.py are full). Same shape as tools.py: each returns (text, actions, level)."""
from . import run
from .tools import SLOW, plain, win


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

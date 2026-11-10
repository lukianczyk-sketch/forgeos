"""Show Me How (Job 22) for Forge Helper: the "Show me" button on help answers and the showme action.

Pointing changes nothing, so the window starts it without asking Yes first.
"""
import os
import re


def share():
    return os.environ.get("FORGEOS_SHOWME_SHARE") or "/usr/share/forgeos/showme"


def has_guide(name):
    return bool(re.fullmatch(r"[a-z0-9-]{1,40}", name)) and os.path.isfile(os.path.join(share(), "guides", name + ".txt"))


def button(name):
    """[("showme", NAME, label)] when Show Me How has a guide for this help card, else []."""
    return [("showme", name, "Show me on the screen")] if has_guide(name) else []


def ok(arg):
    """A guide name (its file is there), or "ask:" + a short question."""
    if arg.startswith("ask:"):
        return 2 <= len(arg[4:].strip()) <= 200
    return has_guide(arg)


def go(arg, start):
    """Start the walk (start = actions.start). Returns (exit code, plain message)."""
    cmd = ["forgeos-showme", "ask", arg[4:]] if arg.startswith("ask:") else ["forgeos-showme", "guide", arg]
    if start(cmd):
        return 0, "Look at the screen: a yellow arrow shows you where to click."
    return 1, "Show Me How could not start."

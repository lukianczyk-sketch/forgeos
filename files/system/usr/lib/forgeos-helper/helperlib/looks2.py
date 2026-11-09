"""Looks for the newer jobs (looks.py is full). Same shape as tools.py: each returns (text, actions, level)."""
from . import run
from .tools import plain, win


def why_slow(_arg):
    code, out = run(["forgeos-slow", "report"], 150)
    text = plain(out) if code in (0, 1) else "Why Is It Slow? could not check the PC."
    return text, win("slow", "Open Why Is It Slow?"), -1

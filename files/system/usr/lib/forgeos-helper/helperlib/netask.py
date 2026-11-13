"""Ask Before Connecting (Job 24) in Forge Helper: the quick rule, the look and the two buttons.

Kept here because rules.py, tools.py and actions.py are full. Allow is asked once more by the PC itself
(a program cannot allow itself through the helper); Block needs no question.
"""
import re

from . import run
from .tools import plain, win

# The quick rule: right after Plain-English Errors, before the other PC problems ("internet").
NET = ("net_access", r"\b(something|anything|any ?(apps?|programs?)|what|which (apps?|programs?)|who|apps?|programs?)\b.{0,30}"
                     r"\b(using|uses|use|used|on|connected to|talking to|went on|go on) (the |my )?internet\b|"
                     r"who uses the internet|ask before connecting|\block ?down\b|"
                     r"\b(unblock|allow|block) (?!(a |the |this |that )?(site|website|email|download|page|link|number|caller|call|pop.?up)s?\b)"
                     r"[\w .+-]{2,40}? (from|to use|to reach|on|to go on|access to) (the )?(internet|online)\b|"
                     r"^(please )?unblock [\w .+-]{2,40}$|"
                     r"why (can.?t|won.?t|doesn.?t|isn.?t|can ?not) (?!(i|we)\b|(my|the|this) (wi-?fi|wifi|internet|network|computer|pc|"
                     r"laptop|printer|phone)\b)[\w .+-]{2,40}? (connect|go online|get online|reach the internet|use the internet)")


def net_access(arg):
    """Ask Before Connecting (Job 24): who uses the internet, why an app can't connect, block or unblock it."""
    m = re.search(r"\b(unblock|allow|block)\s+(?:the |my )?([\w .+-]{2,40}?)(?:\s+(?:from|to use|to reach|on|to go on|"
                  r"access to)\b.*)?[?.!]*$", arg, re.I) or \
        re.search(r"why (?:can.?t|won.?t|doesn.?t|isn.?t|can ?not) (?:the |my )?([\w .+-]{2,40}?) (?:connect|go online|get "
                  r"online|reach the internet|use the internet)", arg, re.I)
    if m:
        want = m.group(1).lower() if m.lastindex == 2 else "why"
        name = m.group(m.lastindex).strip()
        code, out = run(["forgeos-netask", "why", name], 30)
        if code == 2:
            return plain(out), win("netask", "Open Who Uses the Internet"), -1
        if code != 0:
            return ("No program called \"%s\" has tried to use the internet on this PC yet." % name,
                    win("netask", "Open Who Uses the Internet"), -1)
        now = next((x.split("\t")[2] for x in out.splitlines() if x.startswith("WHY\t")), "ask")
        acts = []
        if want == "block" and now != "block":
            acts.append(("net_block", name, "Block %s from the internet" % name))
        elif want != "block" and now != "allow" and "every time" not in out:
            acts.append(("net_allow", name, "Allow %s to use the internet" % name))
        return plain(out), acts + win("netask", "Open Who Uses the Internet"), -1
    code, out = run(["forgeos-netask", "report"], 30)
    return plain(out), win("netask", "Open Who Uses the Internet"), -1


def act(action, arg):
    """net_allow / net_block ARG (an app's name or key), after the user's Yes. Returns (exit code, message)."""
    if action not in ("net_allow", "net_block") or not re.match(r"^[\w .+:/-]{1,200}$", arg):
        return 2, "That is not an app's name."
    code, out = run(["forgeos-netask", "allow" if action == "net_allow" else "block", arg], 150)
    return (0 if code == 0 else 1), out.strip() or ("Done." if code == 0 else "That did not work.")

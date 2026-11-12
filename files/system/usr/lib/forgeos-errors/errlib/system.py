"""Crashes and hidden problems: what the watcher finds besides pop-up messages.

Crashes: on Plasma 6 every crash goes through systemd-coredump, and 'coredumpctl' lists yours (no crash
report is ever sent anywhere). The system log: only errors the library marks 'log: yes' (the rest is noise).
"""
import json
import os
import re

from . import run
from . import fixes, history, library


def pretty(prog):
    """A program's menu name and its menu entry id, from its file name."""
    for name in (prog, prog.lower()):
        path = fixes.desktop(name)
        if path:
            with open(path, encoding="utf-8", errors="replace") as f:
                m = re.search(r"^Name=(.+)$", f.read(), re.M)
            return (m.group(1).strip() if m else prog), name
    return prog, ""


def crash_card(prog):
    name, did = pretty(prog)
    times = history.count("app-crash/" + prog) + 1
    card = {"id": "app-crash", "program": prog, "level": "green", "title": "%s closed by itself" % name,
            "say": "%s stopped working and closed. This happens now and then; it is not a virus." % name,
            "do": "Open it again. Anything you saved is safe."}
    if times >= 3:
        card.update(level="yellow", do="It keeps closing (%d times this week). Restart the PC. If it still"
                    " happens, an update usually fixes it; ask Forge Helper." % times)
    if did:
        card["fix"] = "reopen:" + did
    return card


def crashes(since):
    code, out = run(["coredumpctl", "list", "--json=short", "--no-pager", "--since=@%d" % int(since)], 30)
    try:
        rows = json.loads(out) if code == 0 and out.strip() else []
    except ValueError:
        rows = []
    progs = []
    for r in rows if isinstance(rows, list) else []:
        if isinstance(r, dict) and str(r.get("uid")) == str(os.getuid()) and r.get("exe"):
            p = os.path.basename(str(r["exe"]))
            if p and p not in progs and p.lower() not in ("drkonqi", "drkonqi-coredump-launcher"):
                progs.append(p)
    return progs


def log_errors(since, entries):
    code, out = run(["journalctl", "-b", "-p", "warning", "-o", "json", "--no-pager", "-n", "2000",
                     "--since=@%d" % int(since)], 60)
    found = {}
    for line in out.splitlines() if code == 0 else []:
        try:
            msg = json.loads(line).get("MESSAGE", "")
        except (ValueError, AttributeError):
            continue
        msg = bytes(msg).decode("utf-8", "replace") if isinstance(msg, list) else str(msg)
        e = library.best(msg, entries, log=True)
        if e and e["id"] not in found:
            found[e["id"]] = (e, msg)
    return list(found.values())

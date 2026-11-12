"""The watcher in your session (forgeos-errors-watch.service): it notices errors and offers to explain them.

It listens to the desktop's pop-ups (busctl monitor, your own session only) and offers "What does this mean?"
on the ones the library or the scam check knows; other pop-ups are never written down, and of an error only
the words that matched are kept. Every 3 minutes it also looks at new crashes and hidden problems in the
system log (system.py).
"""
import json
import os
import re
import select
import subprocess

from . import APP, clean, data_dir, load_json, now, save_json, start
from . import explain, history, library, scam, system

TICK = 180   # look at crashes and the system log every 3 minutes
ERRORISH = re.compile(r"\b(error|failed|failure|could ?n.?t|can.?t|cannot|unable|crash(ed)?|denied|warning|deactivated|"
                      r"disconnected|not (responding|connected|found|accepted|supported|installed)|is paused|"
                      r"paper jam|out of (paper|ink|toner|space|memory)|running out|no internet)\b", re.I)
# ForgeOS's own tools, and KDE's own crash pop-up (crashes are found below)
SKIP_APPS = re.compile(r"(%s|forgeos.*|forge helper|clean sweep|always-on guard|digital will|drive health|"
                       r"drivers & bios|fake tech support guard|family mode|find my pc|ransomware tripwire|"
                       r"panic button|privacy report|ghostfinder|drkonqi)" % re.escape(APP.lower()))
MATCH = "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"


def pop(entry):
    """Show the pop-up in its own process, so the watcher keeps listening while it waits for a click."""
    start(["forgeos-errors", "pop", entry["key"]])


def notice(app, summary, body, entries=None):
    """One pop-up message seen. Returns the history entry when it was a known error or a scam, else None."""
    if SKIP_APPS.fullmatch(app.strip().lower()):
        return None
    text = (summary + ". " + body).strip(". ")
    if not ERRORISH.search(text) and not scam.is_fake(text):
        return None   # a normal pop-up (a message, a song): never looked at again, never written down
    entries = library.load() if entries is None else entries
    card = explain.explain(text, use_ai=False, entries=entries)
    if not card:
        return None   # not one we know: left alone (Meta+Shift+E still explains it)
    kept = clean(summary, 80) if card["id"] == "scam-fake-error" else library.words(text, entries, card["id"])
    e, show = history.record(card, "notice", text, kept)
    if show:
        pop(e)
    return e


def parse_monitor(lines):
    """busctl monitor --json=short lines -> the Notify calls in them, as (app, summary, body)."""
    calls = []
    for line in lines:
        try:
            msg = json.loads(line)
            data = msg["payload"]["data"]
        except (ValueError, KeyError, TypeError):
            continue
        if msg.get("member") == "Notify" and isinstance(data, list) and len(data) >= 5:
            calls.append(tuple(str(x) for x in (data[0], data[3], data[4])))
    return calls


def tick():
    """Look at new crashes and the system log once. Returns the history entries written."""
    state_file = os.path.join(data_dir(), "watch.json")
    state = load_json(state_file, {})
    since = state.get("since") or now() - TICK
    state["since"] = now()
    save_json(state_file, state)
    entries, done = library.load(), []
    for prog in system.crashes(since):
        done.append(history.record(system.crash_card(prog), "crash", prog))
    for e, msg in system.log_errors(since, entries):
        done.append(history.record(explain.from_entry(e), "log", msg, library.words(msg, entries, e["id"])))
    for e, show in done:
        if show:
            pop(e)
    return [e for e, _ in done]


def watch():
    """Run until stopped: listen to pop-ups, and every 3 minutes look at crashes and the system log."""
    cmd = ["busctl", "--user", "monitor", "--json=short", "--match", MATCH]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
    fd, entries, rest, last = proc.stdout.fileno(), library.load(), b"", 0.0
    while proc.poll() is None:
        if select.select([fd], [], [], 2.0)[0]:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            *lines, rest = (rest + chunk).split(b"\n")
            for app, summary, body in parse_monitor(x.decode("utf-8", "replace") for x in lines):
                notice(app, summary, body, entries)
        if now() - last >= TICK:
            last = now()
            tick()
    return 1

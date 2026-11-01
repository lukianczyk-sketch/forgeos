"""What the user asked Forge Helper to remember, and their thumbs up / down. Never leaves the PC.

~/.config/forgeos/helper/memory.json             {"facts": [...]}  (shown in the window, "Forget everything")
~/.local/share/forgeos/helper/feedback.jsonl      one line per thumbs up / down
~/.local/share/forgeos/helper/my-tests.jsonl      thumbs-down questions: selftest makes sure they stay fixed
"""
import json
import os
import re
import time

from . import append_line, clean, config_dir, data_dir, read_json, write_json

MAX_FACTS = 50
SECRET = re.compile(r"pass ?word|passcode|\bpin\b|social security|\bssn\b|card number|bank account|"
                    r"routing number|\d[\d -]{10,}\d", re.I)


def memory_file():
    return os.path.join(config_dir(), "helper", "memory.json")


def feedback_file():
    return os.path.join(data_dir(), "feedback.jsonl")


def my_tests_file():
    return os.path.join(data_dir(), "my-tests.jsonl")


def facts():
    value = read_json(memory_file(), {})
    got = value.get("facts") if isinstance(value, dict) else None
    return [clean(f, 200) for f in got if isinstance(f, str)][:MAX_FACTS] if isinstance(got, list) else []


def remember(text):
    """Save one fact. Returns the plain message for the user."""
    fact = clean(" ".join(text.split()), 200).rstrip(".")
    if len(fact) < 3:
        return "Please tell me what to remember, for example: remember that my daughter is Brianna."
    if SECRET.search(fact):
        return ("I don't keep passwords, PINs, card or account numbers. Keep those in a password"
                " manager, never in a note.")
    have = facts()
    if fact.lower() in (f.lower() for f in have):
        return "I already remember that."
    have = (have + [fact])[-MAX_FACTS:]
    write_json(memory_file(), {"facts": have})
    return "OK, I'll remember that: %s. It stays on this PC. Ask \"what do you remember\" to see it." % fact


def show():
    have = facts()
    if not have:
        return "You haven't asked me to remember anything yet."
    return "Things you asked me to remember (only on this PC):\n" + "\n".join("- " + f for f in have)


def feedback(kind, tool, question):
    """Save a thumbs up / down. A thumbs down becomes one of the user's own test questions."""
    if kind not in ("up", "down"):
        return False
    q = clean(" ".join(question.split()), 500)
    line = {"when": time.strftime("%Y-%m-%d %H:%M"), "kind": kind, "tool": tool, "q": q}
    append_line(feedback_file(), json.dumps(line))
    if kind == "down" and q:
        append_line(my_tests_file(), json.dumps({"q": q, "not_tool": tool}))
    return True


def forget_all():
    for path in (memory_file(), feedback_file(), my_tests_file()):
        try:
            os.remove(path)
        except OSError:
            pass

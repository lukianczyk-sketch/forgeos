"""Who may connect without a question, and who gets the Fake Tech Support Guard question."""
import os
import re

from . import SHARE, TG_SHARE, home_of, load_json, read_lines


def remote_app(names):
    """(id, name) when one of the names is a remote-control app (Fake Tech Support Guard's list), else None."""
    simple = [re.sub(r"\s+", "_", re.split(r"[/\\]", str(n).strip())[-1].lower()) for n in names if n]
    for line in read_lines(os.path.join(TG_SHARE, "remote-apps.txt")):
        parts = [p.strip() for p in line.split("~")]
        if len(parts) != 3 or not all(parts):
            continue
        try:
            rx = re.compile(parts[2])
        except re.error:
            continue
        if any(rx.search(n) for n in simple):
            return parts[0], parts[1]
    return None


def family_helper_on(uid):
    """Family Mode is on for this person (then its helper app RustDesk may connect without a question)."""
    saved = os.path.join(home_of(uid), ".local", "state", "forgeos", "family", "saved.json")
    return load_json(saved, {}).get("on") is True


def trusted_apps():
    return set(read_lines(os.path.join(SHARE, "trusted-apps.txt")))

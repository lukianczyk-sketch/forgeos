"""The monthly 2-minute drive self-test (smartctl -t short). It only starts when the PC is idle and on
wall power; the drive runs it by itself and the result is read by the next daily check.
"""
import os

from . import DAY, ENV, SYS, run

EVERY = 30 * DAY


def on_wall_power():
    """True on a desktop (no battery) or when the charger is in."""
    base = os.path.join(SYS, "class", "power_supply")
    try:
        names = os.listdir(base)
    except OSError:
        return True
    kinds = {}
    for n in names:
        try:
            with open(os.path.join(base, n, "type")) as f:
                kind = f.read().strip()
            with open(os.path.join(base, n, "online" if kind == "Mains" else "type")) as f:
                kinds.setdefault(kind, []).append(f.read().strip())
        except OSError:
            continue
    if "Battery" not in kinds:
        return True
    return "1" in kinds.get("Mains", [])


def idle():
    load = ENV("FORGEOS_DH_LOAD")
    try:
        return float(load) < 1.0 if load else os.getloadavg()[0] < 1.0
    except (OSError, ValueError):
        return False


def maybe_start(found, hist, t):
    """Start the self-test on drives whose last one is 30+ days old. Returns the drives it started on."""
    last = hist.setdefault("selftest", {})
    due = [d for d in found if d["read"] and not d["usb"] and t - last.get(d["key"], 0) >= EVERY]
    if not due or not on_wall_power() or not idle():
        return []
    started = []
    for d in due:
        code, _out = run(["smartctl", "-t", "short", d["dev"]], 60)
        if code != 127 and not code & 7:  # 1 bad command, 2 could not open, 4 the drive said no
            last[d["key"]] = t
            started.append(d["dev"])
    return started

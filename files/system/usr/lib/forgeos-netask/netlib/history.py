"""Today's counts and the blocked list, per person (log-UID.json, 30 days). No web addresses are kept except
for blocked tries."""
import os

from . import KEEP_DAYS, LOCK, VAR, day, load_json, now, save_json


def log_file(uid):
    return os.path.join(VAR, "log-%d.json" % int(uid))


def count(uid, name, n=1):
    """Today's count: this app went online n more times."""
    with LOCK:
        lg = load_json(log_file(uid), {})
        days = lg.setdefault("days", {})
        today = days.setdefault(day(), {})
        today[name] = today.get(name, 0) + n
        _prune(lg)
        save_json(log_file(uid), lg)


def blocked(uid, key, name, host, why):
    """Write down a blocked try (the only time a web address is kept)."""
    with LOCK:
        lg = load_json(log_file(uid), {})
        last = (lg.get("blocked") or [[0, "", "", "", ""]])[-1]
        if last[2] == name and last[3] == (host or "")[:120] and now() - last[0] < 10:
            return   # the same try, seen again in OpenSnitch's events
        lg.setdefault("blocked", []).append([int(now()), key, name, (host or "")[:120], why])
        _prune(lg)
        save_json(log_file(uid), lg)


def _prune(lg):
    oldest = now() - KEEP_DAYS * 86400
    lg["days"] = {d: v for d, v in sorted(lg.get("days", {}).items()) if d >= day(oldest)}
    lg["blocked"] = [b for b in lg.get("blocked", []) if b[0] >= oldest][-500:]


def log(uid):
    return load_json(log_file(uid), {})

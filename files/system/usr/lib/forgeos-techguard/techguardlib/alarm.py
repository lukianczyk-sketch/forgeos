"""Alarms (a remote-control app was paused), the programs you said are yours, and Family Mode facts.

"I set this up myself" needs the PC password: root writes it into /var/lib/forgeos-techguard/trusted.json
(the program's file fingerprint), so a stranger can't just write it there. Family Mode's Call for help
(RustDesk, locked down, while its 2-hour timer runs) is always allowed: that is YOUR helper.
"""
import os
import re

from . import (ENV, FAMILY, HOME, TRUSTED, CALL_TIMER, clean, load_json, my_uid, new_id, now, run,
               save_json)
from . import procs

# Programs that run OTHER programs (Wine runs every Windows program): for these only that exact command
# line is trusted, never every Windows program.
RUNNERS = re.compile(r"^(wine.*|python[0-9.]*|java|bash|sh|dash|zsh|perl|node|mono|ruby|pwsh|bwrap|ld-linux.*)$")


def family_on():
    return load_json(os.path.join(FAMILY, "saved.json")).get("on") is True


def helper_name():
    conf = os.path.join(ENV("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "forgeos", "family.conf")
    try:
        with open(conf) as f:
            for line in f:
                k, sep, v = line.rstrip("\n").partition("=")
                if sep and k == "name" and clean(v, 40):
                    return clean(v, 40)
    except OSError:
        pass
    return ""


def helper_call():
    """Your helper's name while Family Mode's Call for help is running, else ''."""
    code, out = run(["systemctl", "--user", "is-active", CALL_TIMER], 10)
    return (helper_name() or "your helper") if code == 0 and out.strip() == "active" else ""


def runner(hit):
    return bool(RUNNERS.match(os.path.basename(hit.get("exe", ""))))


def trusted_entry(hit):
    """What root writes for "I set this up myself"."""
    return {"uid": hit["uid"], "app": hit["app"], "name": hit["title"], "flatpak": hit.get("flatpak", ""),
            "exe": hit.get("exe", ""), "sha256": procs.sha256(hit["pid"]),
            "cmd": hit.get("cmd", "") if runner(hit) else "", "time": now()}


def is_trusted(hit):
    """You said this exact program is yours (same app, same program file, same command line for Wine)."""
    mine = [t for t in load_json(TRUSTED, []) if isinstance(t, dict) and t.get("uid") == my_uid()
            and t.get("app") == hit["app"] and t.get("exe") == hit.get("exe", "")]
    if not mine:
        return False
    sha = procs.sha256(hit["pid"])
    return any(t.get("sha256") == sha and sha and (not runner(hit) or t.get("cmd") == hit.get("cmd"))
               for t in mine)


def root_trust(pid, caller):
    """The root half of "I set this up myself" (forgeos-techguard-trust). Exit 0 done, 3 refused."""
    i = procs.info(pid)
    hit = procs.remote_apps([i]) if i else {}
    if not hit or i["uid"] != caller:
        print("That is not one of your remote-control apps.")
        return 3
    hit = list(hit.values())[0]
    entry = trusted_entry(hit)
    if not entry["sha256"]:
        print("Could not read the program file.")
        return 3
    kept = [t for t in load_json(TRUSTED, []) if isinstance(t, dict) and not (
        t.get("uid") == entry["uid"] and t.get("app") == entry["app"] and t.get("exe") == entry["exe"])]
    save_json(TRUSTED, kept + [entry], 0o644)
    print("%s is trusted from now on." % entry["name"])
    return 0


def new(st, hit, how, pids, state):
    """Write down a new alarm in the state (st) and return it."""
    alarm = {"id": new_id(), "key": hit["key"], "app": hit["app"], "title": hit["title"],
             "program": clean(hit.get("exe") or hit.get("name"), 200), "flatpak": hit.get("flatpak", ""),
             "pid": hit["pid"], "pids": pids, "cgroup": hit.get("cgroup", ""), "how": how, "state": state,
             "time": now(), "test": hit.get("test", False), "family": family_on()}
    while alarm["id"] in st.setdefault("alarms", {}):
        alarm["id"] += "1"
    st["alarms"][alarm["id"]] = alarm
    old = sorted(st["alarms"].values(), key=lambda a: a["time"])
    for a in old[:-50]:
        if a["state"] != "paused":
            del st["alarms"][a["id"]]
    return alarm


def by_key(st, key):
    """The newest alarm for this app that is still about it (paused / allowed / helper)."""
    found = [a for a in st.get("alarms", {}).values() if a.get("key") == key and a.get("state") in
             ("paused", "running", "allowed", "helper", "ended-family")]
    return max(found, key=lambda a: a["time"]) if found else None


def paused(st):
    return [a for a in st.get("alarms", {}).values() if a.get("state") == "paused" and not a.get("test")]

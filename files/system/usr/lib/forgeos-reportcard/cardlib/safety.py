"""Subjects 1-2: the safety guards and updates.

Each asks the ForgeOS tool's own "status" (no new scans) and turns it into points: start at 100, take off
for each real problem, and say the worst problems in plain words. A tool that does not answer = not checked.
"""
import json

from . import age, days_ago, one, rows, run, subject, worst


def safety():
    bad, heard = [], 0
    g = rows(run(["forgeos-guard", "status"], 60)[1])
    if "SERVICE" in g:
        heard += 1
        if one(g, "SERVICE") != "running":
            bad.append((30, "Always-On Guard is stopped", "guard"))
        for parts in g.get("GUARD", []):
            if parts[:2] == ["downloads", "off"]:
                bad.append((20, "download checking is off", "guard"))
            elif parts[:2] == ["websites", "off"]:
                bad.append((20, "the scam website blocker is off", "guard"))
            elif parts[:2] == ["email", "off"] and parts[2:3] == ["thunderbird"]:
                bad.append((10, "email checking is off", "guard"))
            elif parts[:1] == ["websites"] and (age(parts[3] if len(parts) > 3 else "") or 0) > 7:
                bad.append((10, "the scam website list is %d days old" % age(parts[3]), "guard"))
        days = age(one(g, "VIRUSLIST"))
        if days is None or days > 7:
            bad.append((15, "the virus list is missing" if days is None else "the virus list is %d days old" % days, "guard"))
    for cmd, name, off in (("forgeos-tripwire", "Ransomware Tripwire", 20), ("forgeos-techguard", "Fake Tech Support Guard", 15)):
        t = rows(run([cmd, "status"], 60)[1])
        if "SERVICE" not in t:
            continue
        heard += 1
        if one(t, "SERVICE") != "on":
            bad.append((off, name + " is off", cmd[8:]))
        if one(t, "INTERNET") == "cut":
            bad.append((30, name + " cut the internet - open it to see why", cmd[8:]))
        if one(t, "SHARING", 0, "-") not in ("", "-"):
            bad.append((40, "someone can see or control this PC right now", cmd[8:]))
    code, out = run(["forgeos-netask", "status"], 60)
    n = rows(out)
    if "SERVICE" in n or code == 2:
        heard += 1
        if code == 2:
            bad.append((15, "Ask Before Connecting is not running", "netask"))
        elif one(n, "SERVICE") != "on":
            bad.append((15, "Ask Before Connecting is off (new programs can use the internet without asking)", "netask"))
    if not heard:
        return subject("safety", "Safety guards", None, "The safety guards did not answer.", "guard")
    pts, why, tool = worst(bad, "All guards are on and the virus and scam lists are fresh.", "guard")
    return subject("safety", "Safety guards", pts, why, tool)


def updates():
    bad, heard = [], 0
    a = rows(run(["forgeos-autopilot", "status"], 120)[1])
    if "UPDATES" in a:
        heard += 1
        way = one(a, "UPDATES")
        if way in ("off", "failing"):
            bad.append((40 if way == "off" else 30, "automatic updates are switched off" if way == "off"
                        else "the last automatic update failed", "autopilot"))
        if one(a, "DRIVERS") == "waiting":
            bad.append((10, "new drivers are waiting - restart to finish", "autopilot"))
        n = one(a, "FIRMWARE", 0, "0")
        if n.isdigit() and int(n):
            bad.append((10, "%s device update%s waiting" % (n, " is" if n == "1" else "s are"), "autopilot"))
        if one(a, "FIRMWARE", 1, "-") != "-":
            bad.append((10, "a BIOS update is waiting", "autopilot"))
        if one(a, "AFTERBOOT") == "problem":
            bad.append((30, "something stopped working after the last update", "autopilot"))
        n = one(a, "DEVICES", 0, "0")
        if n.isdigit() and int(n):
            bad.append((10, "%s part%s no driver" % (n, " has" if n == "1" else "s have"), "autopilot"))
    code, out = run(["rpm-ostree", "status", "--json"], 60)
    try:
        deps = json.loads(out).get("deployments", []) if code == 0 else []
    except (ValueError, AttributeError):
        deps = []
    booted = next((d for d in deps if isinstance(d, dict) and d.get("booted")), None)
    if booted and isinstance(booted.get("timestamp"), int):
        heard += 1
        days = days_ago(booted["timestamp"])
        if days > 30:
            bad.append((40 if days > 60 else 20, "ForgeOS has not updated in %d days" % days, "autopilot"))
        if any(d.get("staged") for d in deps if isinstance(d, dict)) and one(a, "DRIVERS") != "waiting":
            bad.append((5, "an update is ready - restart to finish", "autopilot"))
    if not heard:
        return subject("updates", "Updates", None, "Drivers & BIOS did not answer.", "autopilot")
    pts, why, tool = worst(bad, "ForgeOS, drivers and firmware are up to date.", "autopilot")
    return subject("updates", "Updates", pts, why, tool)

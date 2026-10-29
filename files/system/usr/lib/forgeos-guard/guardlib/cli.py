"""forgeos-guard commands: status, scan, locked-away files, warnings, guards on/off, check one email."""
import os
import sys

from . import GUARDS, HOSTS_STATUS, WHY_DIR, events, log_event, risky_name, run, save_settings, settings
from . import alerts, inbox, mail, quarantine, scan

SERVICE = "forgeos-guard.service"
NAMES = {"downloads": "Download Guard", "email": "Email Guard"}


def usage():
    print("usage: forgeos-guard status | scan FILE... | quarantine list|restore ID|delete ID\n"
          "       forgeos-guard events [N] | why ID | on|off downloads|email|all | check-mail FILE | watch", file=sys.stderr)
    return 3


def websites():
    """(on, how many websites are blocked, when) from the PC-wide Website Guard's status file."""
    found = {}
    try:
        with open(HOSTS_STATUS) as f:
            for line in f:
                key, _, value = line.strip().partition("=")
                found[key] = value
    except OSError:
        return False, 0, ""
    count = found.get("blocked", "0")
    return found.get("state") == "on", int(count) if count.isdigit() else 0, found.get("updated", "")


def status():
    on = settings()
    code, out = run(["systemctl", "--user", "is-active", SERVICE], 10)
    running = code == 0 and out.strip() == "active"
    print("SERVICE\t%s" % ("running" if running else "stopped"))
    print("GUARD\tdownloads\t%s\t%s" % ("on" if on["downloads"] else "off", "fast" if scan.fast() else "low-memory"))
    web_on, count, when = websites()
    print("GUARD\twebsites\t%s\t%d\t%s" % ("on" if web_on else "off", count, when))
    print("GUARD\temail\t%s\t%s" % ("on" if on["email"] else "off", "thunderbird" if inbox.roots() else "no-thunderbird"))
    print("VIRUSLIST\t%s" % (scan.db_date() or "unknown"))
    print("LOCKED\t%d" % len(quarantine.entries()))
    print("WARNINGS\t%d" % len(events(500)))
    return 0


def scan_cmd(paths):
    worst = 0
    found = scan.scan_files([os.path.abspath(p) for p in paths])
    for path, virus in found.items():
        if virus:
            qid = quarantine.lock_away(path, virus)
            log_event("virus", "scan", path, virus, qid or "could not lock it away")
            print("VIRUS\t%s\t%s\t%s" % (path, virus, qid))
            worst = 1
        elif virus is None:
            print("UNCHECKED\t%s" % path)
            worst = worst or 3
        elif risky_name(os.path.basename(path)):
            print("RISKY\t%s\t%s" % (path, risky_name(os.path.basename(path))))
            worst = 2 if worst in (0, 3) else worst
        else:
            print("CLEAN\t%s" % path)
    return worst


def quarantine_cmd(rest):
    if rest == ["list"]:
        items = quarantine.entries()
        for qid, date, original, virus in items:
            print("\t".join([qid, date, original, virus]))
        if not items:
            print("No files are locked away.")
        return 0
    if len(rest) == 2 and rest[0] == "restore":
        where = quarantine.restore(rest[1])
        print("Put back: %s" % where if where else "No locked-away file has that ID.")
        return 0 if where else 1
    if len(rest) == 2 and rest[0] == "delete":
        gone = quarantine.delete(rest[1])
        print("Deleted for good." if gone else "No locked-away file has that ID.")
        return 0 if gone else 1
    return usage()


def switch(turn_on, which):
    names = list(GUARDS) if which == "all" else [which]
    on = settings()
    for name in names:
        on[name] = turn_on
    save_settings(on)
    if any(on.values()):
        run(["systemctl", "--user", "enable", "--now", SERVICE], 30)
    else:
        run(["systemctl", "--user", "disable", "--now", SERVICE], 30)
    for name in names:
        print("%s is %s." % (NAMES[name], "ON" if turn_on else "OFF"))
    return 0


def why(eid):
    if not eid.replace("-", "").isdigit():
        return usage()
    try:
        with open(os.path.join(WHY_DIR, eid + ".txt")) as f:
            print(f.read().rstrip())
        return 0
    except OSError:
        print("No more details were saved for this warning.")
        return 1


def main(args):
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    if cmd == "status" and not rest:
        return status()
    if cmd == "scan" and rest:
        return scan_cmd(rest)
    if cmd == "quarantine":
        return quarantine_cmd(rest)
    if cmd == "events" and len(rest) <= 1 and all(x.isdigit() for x in rest):
        for line in events(int(rest[0]) if rest else 20):
            print("\t".join(line))
        return 0
    if cmd == "why" and len(rest) == 1:
        return why(rest[0])
    if cmd in ("on", "off") and len(rest) == 1 and rest[0] in GUARDS + ("all",):
        return switch(cmd == "on", rest[0])
    if cmd == "check-mail" and len(rest) == 1:
        alerts.QUIET = 0
        with open(rest[0], "rb") as f:
            level = mail.check(mail.parse(f.read()), "test")
        print(["FINE", "CAREFUL", "SCAM"][level])
        return level
    if cmd == "watch" and (not rest or (len(rest) == 2 and rest[0] == "--for" and rest[1].isdigit())):
        from . import watch
        return watch.main(int(rest[1]) if rest else 0)
    return usage()

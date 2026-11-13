"""forgeos-netask: Ask Before Connecting from a terminal, the window and Forge Helper (runs as the person).

  status | list | today | blocked [MINUTES] | allow APP | block APP | ask APP | why APP
  lockdown on|off | on | off | report | explain NAME [PATH]
APP = the app's name as the list shows it (or its key). Exit: 0 ok, 1 not done, 2 the service is not
running, 3 wrong use. Lines with a TAB are for the window.
"""
import json
import socket
import sys

from . import REQ_SOCK, clean

USAGE = ("usage: forgeos-netask status | list | today | blocked [MINUTES] | allow APP | block APP | ask APP | why APP\n"
         "                      | lockdown on|off | on | off | report | explain NAME [PATH]")


class Down(Exception):
    pass


def ask(req, timeout=120):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(REQ_SOCK)
            s.sendall((json.dumps(req) + "\n").encode("utf-8"))
            data = b""
            while not data.endswith(b"\n"):
                got = s.recv(65536)
                if not got:
                    break
                data += got
        return json.loads(data.decode("utf-8"))
    except (OSError, ValueError) as e:
        raise Down(str(e))


def find(name):
    """The key of the app the person means (exact name, else the only name that contains it)."""
    apps = ask({"do": "list"}).get("apps", [])
    low = name.lower().strip()
    for test in (lambda a: a["key"] == name or a["name"] == name.strip(), lambda a: a["name"].lower() == low,
                 lambda a: low and low in a["name"].lower()):
        some = [a for a in apps if test(a)]
        if len(some) == 1:
            return some[0]
    return None


WORDS = {"allow": "Allowed", "block": "Blocked", "ask": "Asks each time"}


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(USAGE, file=sys.stderr)
        return 3
    cmd, rest = argv[0], argv[1:]
    if cmd == "explain":
        if not 1 <= len(rest) <= 2:
            print(USAGE, file=sys.stderr)
            return 3
        from .explain import explain
        return explain(rest[0], rest[1] if len(rest) > 1 else "")
    try:
        return run(cmd, rest)
    except Down:
        print("Ask Before Connecting is not running right now (the PC still blocks programs it does not know).")
        return 2


def run(cmd, rest):
    if cmd in ("status", "report") and not rest:
        s = ask({"do": "status"})
        print("SERVICE\t%s" % ("on" if s.get("on") else "off"))
        print("LOCKDOWN\t%s" % ("on" if s.get("lockdown") else "off"))
        if cmd == "report":
            apps = ask({"do": "list"}).get("apps", [])
            mine = [a for a in apps if a["kind"] != "system" and a["kind"] != "steam"]
            today = ask({"do": "today"}).get("today", {})
            blocked = ask({"do": "blocked", "minutes": 1440}).get("blocked", [])
            print("Ask Before Connecting is %s%s." % ("on" if s.get("on") else "OFF",
                                                       " and Lock down is on" if s.get("lockdown") else ""))
            if today:
                top = sorted(today.items(), key=lambda x: -x[1])[:5]
                print("Online today: " + ", ".join("%s (%d)" % t for t in top) + ".")
            else:
                print("Nothing went online today that I counted.")
            print("Your apps: %d allowed, %d blocked, %d ask each time." % tuple(
                sum(1 for a in mine if a["answer"] == w) for w in ("allow", "block", "ask")))
            if blocked:
                print("Blocked in the last day: " + ", ".join(sorted({b["name"] for b in blocked})[:6]) + ".")
        else:
            print("Ask Before Connecting is %s." % ("on" if s.get("on") else "off")
                  + (" Lock down is on: new programs are blocked without asking." if s.get("lockdown") else ""))
        return 0
    if cmd == "list" and not rest:
        for a in ask({"do": "list"}).get("apps", []):
            print("APP\t%s\t%s\t%s\t%s\t%s" % (a["key"], a["answer"], a["kind"], a["name"], a["red"] or "-"))
        return 0
    if cmd == "today" and not rest:
        today = ask({"do": "today"}).get("today", {})
        for name, n in sorted(today.items(), key=lambda x: -x[1]):
            print("TODAY\t%s\t%d" % (name, n))
        print("%d app%s went online today." % (len(today), "" if len(today) == 1 else "s"))
        return 0
    if cmd == "blocked" and len(rest) <= 1 and (not rest or rest[0].isdigit()):
        rows = ask({"do": "blocked", "minutes": int(rest[0]) if rest else 60}).get("blocked", [])
        for b in rows:
            print("BLOCKED\t%s\t%d\t%s\t%s\t%s" % (b["key"], b["when"], b["name"], b["host"] or "-", b["why"]))
        print("%d blocked tr%s." % (len(rows), "y" if len(rows) == 1 else "ies"))
        return 0
    if cmd in ("allow", "block", "ask", "why") and len(rest) == 1:
        a = find(rest[0])
        if not a:
            print("I don't know a program called \"%s\" that tried to use the internet here." % clean(rest[0], 60))
            return 1
        if cmd == "why":
            print("%s: %s.%s" % (a["name"], WORDS.get(a["answer"], a["answer"]),
                                 " It lives %s, so it is asked about every time." % a["red"] if a["red"] else ""))
            print("WHY\t%s\t%s" % (a["key"], a["answer"]))
            return 0
        out = ask({"do": "set", "key": a["key"], "answer": cmd})
        print(out.get("say", ""))
        return 0 if out.get("ok") else 1
    if cmd == "lockdown" and rest in (["on"], ["off"]):
        out = ask({"do": "lockdown", "on": rest[0] == "on"})
        print(out.get("say", ""))
        return 0 if out.get("ok") else 1
    if cmd in ("on", "off") and not rest:
        out = ask({"do": "power", "on": cmd == "on"})
        print(out.get("say", ""))
        return 0 if out.get("ok") else 1
    print(USAGE, file=sys.stderr)
    return 3

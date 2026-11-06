"""forgeos-tripwire commands. Exit: 0 all fine, 1 something needs you (a frozen program or the internet
is still cut), 3 off / could not / wrong use."""
import os
import sys

from . import ALLOWED, ID_RX, RUN, STATE, STATUS, clean, is_root, load_json, my_uid, now, run, stamp, incident, restore


def usage():
    print("usage: forgeos-tripwire status | report | restore ID | remove ID | release ID | net-on | test\n"
          "       forgeos-tripwire watch [--feed FILE | --for SECONDS]   (root: the watcher service)\n"
          "       forgeos-tripwire alert-watch [--once]   (your session: shows the window)\n"
          "       forgeos-tripwire root-do remove|release ID | net-on   (root, through the helpers)", file=sys.stderr)
    return 3


def facts():
    uid = my_uid()
    st = load_json(STATUS)
    code, out = run(["systemctl", "is-active", "forgeos-tripwire.service"], 10)
    on = code == 0 and out.strip() == "active" and st.get("state") == "on"
    home = os.path.expanduser("~")
    bait = st.get("homes", {}).get(home, "unknown")
    snaps = restore.snapshots(now() + 60)
    return {"on": on, "bait": bait, "snap": snaps[0][1] if snaps else 0,
            "cut": os.path.exists(os.path.join(RUN, "net-cut")),
            "incidents": incident.mine(uid), "restored": load_json(STATE).get("restored", {}),
            "trusted": load_json(ALLOWED, [])}


def status():
    f = facts()
    print("SERVICE\t%s" % ("on" if f["on"] else "off"))
    print("BAIT\t%s" % f["bait"])
    print("SNAPSHOT\t%s" % (stamp(f["snap"]) if f["snap"] else "none"))
    print("INTERNET\t%s" % ("cut" if f["cut"] else "normal"))
    for i in f["incidents"][:20]:
        print("INCIDENT\t%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s" % (i["id"], i["kind"], i["state"], stamp(i["time"]),
              clean(i.get("program") or "-", 40), len(i.get("files", [])), "yes" if i["id"] in f["restored"] else "no",
              clean(i.get("reason", ""), 200)))
    for a in f["trusted"]:
        print("TRUSTED\t%s\t%s" % (clean(a.get("name", "?"), 40), clean(a.get("exe", "?"), 300)))
    return exit_code(f)


def exit_code(f):
    if not f["on"]:
        return 3
    return 1 if f["cut"] or any(i["state"] == "frozen" for i in f["incidents"]) else 0


def report():
    """Plain English (Forge Helper and the window use it)."""
    f = facts()
    if f["on"]:
        print("Ransomware Tripwire is ON: it watches your Documents, Pictures, Desktop, Downloads, Music and Videos.")
    else:
        print("Ransomware Tripwire is OFF. Open it from the menu, or ask your helper to turn it back on.")
    if f["bait"].startswith("ok"):
        print("Its hidden safety files are all in place (%s)." % f["bait"].split()[1])
    print("Last Undo Button snapshot: %s." % (stamp(f["snap"]) if f["snap"] else "none yet (Undo Button may be off)"))
    attacks = [i for i in f["incidents"] if i["kind"] == "attack"]
    words = {"frozen": "still frozen, waiting for you", "removed": "removed", "released": "you said it's yours"}
    for i in attacks[:3]:
        print("%s: stopped %s - %s (%s)" % (stamp(i["time"]), i.get("program") or "a program", i["reason"],
                                           words.get(i["state"], i["state"])))
    if not attacks:
        print("It never had to stop a program. Press \"Test the tripwire\" to watch it catch a pretend attacker.")
    if f["cut"]:
        print("The internet is still OFF since the tripwire stopped a program. Turn it back on in the window.")
    return exit_code(f)


def main(args):
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    one_id = len(rest) == 1 and bool(ID_RX.match(rest[0]))
    from . import actions
    if cmd == "status" and not rest:
        return status()
    if cmd == "report" and not rest:
        return report()
    if cmd in ("restore", "remove", "release") and one_id:
        return {"restore": actions.put_back, "remove": actions.remove, "release": actions.release}[cmd](rest[0])
    if cmd == "net-on" and not rest:
        return actions.net_on()
    if cmd == "test" and not rest:
        return actions.test()
    if cmd == "pretend-attacker" and len(rest) == 1:
        return actions.pretend_attacker(rest[0])
    if cmd == "alert-watch" and rest in ([], ["--once"]):
        from . import alert
        return alert.main(bool(rest))
    if cmd in ("watch", "root-do") and not is_root():
        print("%s must run as root." % cmd, file=sys.stderr)
        return 3
    if cmd == "watch" and not rest:
        from . import watch
        return watch.main()
    if cmd == "watch" and len(rest) == 2 and rest[0] in ("--feed", "--for"):
        from . import watch
        return watch.feed(rest[1]) if rest[0] == "--feed" else watch.main(int(rest[1]) if rest[1].isdigit() else 0)
    if cmd == "root-do" and (rest == ["net-on"] or (len(rest) == 2 and rest[0] in ("remove", "release")
                                                    and ID_RX.match(rest[1]))):
        return actions.root_do(*rest)
    return usage()

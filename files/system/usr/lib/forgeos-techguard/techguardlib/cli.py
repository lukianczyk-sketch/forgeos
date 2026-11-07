"""forgeos-techguard: the commands (the window and Forge Helper use them; root parts via pkexec)."""
from . import ENV, ID_RX, Locked, clean, load_json, my_uid, read_state, run, stamp
from . import TRUSTED, alarm, money

USAGE = ("usage: forgeos-techguard status | report | watch [--once] | kick | escape | net-on | end ID | allow ID |\n"
         "       helper ID | share-ok | checklist | remove flatpak|file VALUE | lock-file PATH | test |\n"
         "       root-money lock|unlock | root-trust add PID|share")
WORDS = {"paused": "paused, waiting for you", "running": "could not be paused", "ended": "closed",
         "kicked": "kicked out", "allowed": "you said it's yours", "helper": "your helper's connection",
         "ended-family": "closed by Family Mode", "gone": "closed"}


def facts():
    st = read_state()
    code, out = run(["systemctl", "--user", "is-active", "forgeos-techguard.service"], 10)
    alarms = sorted([a for a in st.get("alarms", {}).values() if not a.get("test")], key=lambda a: -a["time"])
    return {"on": code == 0 and out.strip() == "active", "st": st, "alarms": alarms, "money": money.locked(),
            "cut": st.get("net") == "cut", "sharing": st.get("sharing", []), "family": alarm.family_on(),
            "trusted": [t for t in load_json(TRUSTED, []) if isinstance(t, dict) and t.get("uid") == my_uid()]}


def exit_code(f):
    if not f["on"]:
        return 3
    return 1 if f["cut"] or f["sharing"] or any(a["state"] == "paused" for a in f["alarms"]) else 0


def status():
    f = facts()
    print("SERVICE\t%s" % ("on" if f["on"] else "off"))
    print("FAMILY\t%s" % ("on" if f["family"] else "off"))
    print("HELPERCALL\t%s" % (alarm.helper_call() or "-"))
    print("MONEY\t%s" % ("locked" if f["money"] else "open"))
    print("INTERNET\t%s" % ("cut" if f["cut"] else "on"))
    print("SHARING\t%s" % (clean(", ".join(f["sharing"]), 120) or "-"))
    for a in f["alarms"][:20]:
        print("ALARM\t%s\t%s\t%s\t%s\t%s" % (a["id"], a["state"], stamp(a["time"]), clean(a["title"], 40),
                                           clean(a.get("program", "-"), 200)))
    for t in f["trusted"]:
        print("TRUSTED\t%s\t%s" % (clean(t.get("name", "?"), 40), clean(t.get("exe", "?"), 200)))
    return exit_code(f)


def report():
    """Plain English (Forge Helper and the window use it)."""
    f = facts()
    print("Fake Tech Support Guard is %s." % ("ON: it pauses any remote-control app (AnyDesk, TeamViewer...) "
          "the moment it starts and asks you first" if f["on"] else "OFF. Open it from the menu and turn it on"))
    print("Microsoft, Apple, Amazon, your bank and the government NEVER call you to get into your computer. Hang up.")
    if f["sharing"]:
        print("RIGHT NOW someone can see this screen (%s). Money websites are %s." % (
            clean(", ".join(f["sharing"]), 80), "locked" if f["money"] else "open (you said it's on purpose)"))
    for a in f["alarms"][:3]:
        print("%s: %s - %s" % (stamp(a["time"]), a["title"], WORDS.get(a["state"], a["state"])))
    if not f["alarms"]:
        print("No remote-control app has tried to start. Press \"Test the guard\" to watch it catch a pretend one.")
    if f["cut"]:
        print("The internet is OFF since you kicked them out. Turn it back on in the window when you are ready.")
    print("If a stranger is in your computer: press Ctrl+Alt+K (Kick them out).")
    return exit_code(f)


def kick_all():
    from . import kick
    with Locked() as st:
        lines = kick.kick(st)
    for line in lines:
        print(line)
    print("BROWSERS\t%d" % kick.escape())
    return 0 if "INTERNET\tcut" in lines else 1


def main(args):
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    one_id = len(rest) == 1 and bool(ID_RX.match(rest[0]))
    from . import actions, kick, watch
    if cmd in ("status", "report", "kick", "escape", "net-on", "share-ok", "checklist", "test") and rest:
        cmd = "?"
    if cmd == "status":
        return status()
    if cmd == "report":
        return report()
    if cmd == "watch" and rest in ([], ["--once"]):
        return watch.main(once=bool(rest))
    if cmd == "kick":
        return kick_all()
    if cmd == "escape":
        print("BROWSERS\t%d" % kick.escape())
        return 0
    if cmd == "net-on":
        with Locked() as st:
            ok = kick.net_on(st)
        print("The internet is back on." if ok else "The internet could not be turned back on.")
        return 0 if ok else 1
    if cmd in ("end", "allow", "helper") and one_id:
        return getattr(actions, cmd)(rest[0])
    if cmd == "share-ok":
        return actions.share_ok()
    if cmd == "checklist":
        for k, v, label in kick.recent():
            print("ITEM\t%s\t%s\t%s" % (k, v, label))
        return 0
    if cmd == "remove" and len(rest) == 2 and rest[0] in ("flatpak", "file"):
        ok = kick.remove_item(rest[0], rest[1])
        print("Removed." if ok else "It could not be removed.")
        return 0 if ok else 1
    if cmd == "lock-file" and len(rest) == 1:
        return actions.lock_file(rest[0])
    if cmd == "test":
        return actions.test()
    if cmd == "root-money" and rest in (["lock"], ["unlock"]):
        return money.root_do(rest[0])
    if cmd == "root-trust" and (rest == ["share"] or (len(rest) == 2 and rest[0] == "add" and rest[1].isdigit())):
        if rest == ["share"]:
            return 0 if money.root_unlock() else 1
        return alarm.root_trust(int(rest[1]), int(ENV("PKEXEC_UID") or 0))
    print(USAGE)
    return 3


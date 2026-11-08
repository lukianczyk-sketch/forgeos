"""forgeos-digitalwill commands. Exit: 0 fine, 1 something needs you / could not, 2 wrong password, 3 wrong use."""
import os
import sys

from . import actions, cards, draft, remind, report, unlock

USAGE = """usage: forgeos-digitalwill status | report | catalog
  person add NAME [PHONE] | person remove NAME
  account set ID PLAN [WHO [NOTE]] | account other NAME PLAN [WHO [NOTE]] | account remove ID
  safe PATH|none | folders PATH...|none | letter NAME (text on stdin) | letter-show NAME
  note (text on stdin) | note-show | legacy | legacy-done ID | legacy-undo ID | legacy-open ID
  usb | check-login (password on stdin) | test (code on stdin)
  make [--two] --holder NAME [--holder NAME] [--usb FOLDER] [--unlock] (passwords on stdin)
  forget-cards | tick | root-unlock add DEVICE"""


def said(problem, ok="Saved."):
    print(problem or ok)
    return 3 if problem else 0


def catalog():
    d = draft.load()
    for acc_id, name, group in draft.catalog():
        a = d["accounts"].get(acc_id, {})
        print("\t".join((acc_id, name, group, "on" if a else "off", a.get("plan", "-"), a.get("who") or "-")))
    for acc_id, a in sorted(d["accounts"].items()):
        if acc_id.startswith("other-"):
            print("\t".join((acc_id, a.get("name", acc_id), "Other", "on", a.get("plan", "-"), a.get("who") or "-")))
    return 0


def make_args(rest):
    two, holders, usb, want = False, [], "", False
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--two":
            two = True
        elif a == "--unlock":
            want = True
        elif a in ("--holder", "--usb") and i + 1 < len(rest):
            i += 1
            if a == "--holder":
                holders.append(rest[i])
            else:
                usb = os.path.realpath(rest[i])
        else:
            return None
        i += 1
    return two, holders, usb, want


def main(argv):
    cmd, rest = (argv[0], argv[1:]) if argv else ("", [])
    n = len(rest)
    if cmd == "status" and n == 0:
        return report.status()
    if cmd == "report" and n == 0:
        return report.report()
    if cmd == "catalog" and n == 0:
        return catalog()
    if cmd == "person" and n in (2, 3) and rest[0] == "add":
        return said(draft.add_person(rest[1], rest[2] if n == 3 else ""))
    if cmd == "person" and n == 2 and rest[0] == "remove":
        return said(draft.remove_person(rest[1]), "Removed.")
    if cmd == "account" and 3 <= n <= 5 and rest[0] == "set":
        return said(draft.set_account(rest[1], rest[2], *rest[3:5]))
    if cmd == "account" and 3 <= n <= 5 and rest[0] == "other":
        return said(draft.set_account("other", rest[2], *(rest[3:5] + ["", ""])[:2], name=rest[1]))
    if cmd == "account" and n == 2 and rest[0] == "remove":
        return said(draft.remove_account(rest[1]), "Removed.")
    if cmd == "safe" and n == 1:
        return said(draft.set_safe("" if rest[0] == "none" else rest[0]))
    if cmd == "folders" and n >= 1:
        return said(draft.set_folders([] if rest == ["none"] else rest))
    if cmd == "letter" and n == 1:
        return said(draft.set_letter(rest[0], sys.stdin.read()))
    if cmd == "letter-show" and n == 1:
        print(draft.load()["letters"].get(rest[0], ""))
        return 0
    if cmd == "note" and n == 0:
        return said(draft.set_note(sys.stdin.read()))
    if cmd == "note-show" and n == 0:
        print(draft.load()["note"])
        return 0
    if cmd == "legacy" and n == 0:
        d = draft.load()
        for item, company, url, what in draft.legacy_list():
            print("\t".join((item, company, url, "done" if item in d["legacy"] else "todo", what)))
        return 0
    if cmd in ("legacy-done", "legacy-undo") and n == 1:
        return said(draft.legacy_done(rest[0], cmd == "legacy-done"))
    if cmd == "legacy-open" and n == 1:
        return actions.legacy_open(rest[0])
    if cmd == "usb" and n == 0:
        for folder, name in unlock.sticks():
            print("%s\t%s\t%d" % (folder, name, actions.pack.free(folder) // 2 ** 20))
        return 0
    if cmd == "check-login" and n == 0:
        rc = actions.check_login(sys.stdin.read().rstrip("\r\n"))
        print(("Right.", "That is not your sign-in password.", "It could not be checked.")[rc])
        return rc
    if cmd == "test" and n == 0:
        return actions.test(sys.stdin.read())
    if cmd == "make":
        parsed = make_args(rest)
        if parsed:
            return actions.make(*parsed, sys.stdin.read())
    if cmd == "forget-cards" and n == 0:
        cards.forget()
        return 0
    if cmd == "tick" and n == 0:
        return remind.tick()
    if cmd == "root-unlock" and n == 2 and rest[0] == "add":
        return unlock.root_add(rest[1], sys.stdin.read())
    print(USAGE, file=sys.stderr)
    return 3

"""The bigger jobs: make the envelope (new codes, PC unlock, pack, code cards), test it, check the
sign-in password. Passwords come in on stdin (one 'name base64' line each) and are never saved."""
import base64
import binascii
import os
import re

from . import CHKPWD, DOCS, FOLDER, NAME_RX, SEVEN, cards, clean, draft, now, pack, read_state, run, unlock, user, words
from .report import ready

SECRETS = ("login", "safe", "extra", "disk")


def read_secrets(text):
    """{'login': ..., 'safe': ..., 'extra': ..., 'disk': ...} from 'name base64' lines (bad lines skipped)."""
    sec = dict.fromkeys(SECRETS, "")
    for line in text.splitlines():
        parts = line.split(" ", 1)
        if len(parts) == 2 and parts[0] in SECRETS:
            try:
                sec[parts[0]] = base64.b64decode(parts[1].strip(), validate=True).decode("utf-8")[:20000]
            except (binascii.Error, UnicodeDecodeError):
                pass
    sec["login"], sec["safe"], sec["disk"] = (sec[k].strip("\r\n") for k in ("login", "safe", "disk"))
    return sec


def check_login(password):
    """0 right, 1 wrong, 2 could not check (the PC's own password checker, unix_chkpwd, is missing)."""
    rc, _out = run([CHKPWD, user(), "nonull"], 30, stdin=password + "\0")
    return 0 if rc == 0 else (2 if rc == 127 else 1)


def holders_ok(d, two, holders):
    names = draft.person_names(d)
    if two:
        if len(holders) != 2 or holders[0] not in names or not clean(holders[1], 60):
            return "Pick who gets Half A (one of your trusted people) and who keeps Half B."
    elif len(holders) != 1 or holders[0] not in names:
        return "Pick which trusted person gets the code card."
    return ""


def make(two, holders, usb, want_unlock, given):
    """Prints CODE / HALF, ENVELOPE, LETTER and CARDS lines and a message.
    Exit 0 made, 1 could not, 2 wrong password, 3 wrong use."""
    d = draft.load()
    _yes, why = ready(d)
    why = why or holders_ok(d, two, holders)
    if usb and usb not in (m for m, _n in unlock.sticks()):
        why = why or "That USB stick is not plugged in."
    if why:
        print(why)
        return 3
    sec = read_secrets(given)
    if sec["login"] and check_login(sec["login"]) == 1:
        print("That is not your PC sign-in password. Nothing was made.")
        return 2
    key = ""
    if want_unlock and unlock.status() != "no-luks":
        key = words.unlock_code()
        problem = unlock.add(key, sec["disk"])
        if problem:
            print(problem)
            return 2 if "not the disk password" in problem else 1
    code = words.opening_code()
    labels = ("Half A", "Half B") if two else ("Code card",)
    held = [(labels[i], clean(h, 60)) for i, h in enumerate(holders)]
    paths, msg = pack.make(code, sec, held, usb, key)
    if not paths:
        print(msg)
        return 1
    if two:
        a, b = words.halves(code)
        print("HALF\tA\t%s\nHALF\tB\t%s" % (a, b))
    else:
        print("CODE\t" + code)
    for p in paths:
        print("ENVELOPE\t" + p)
        print("LETTER\t" + os.path.join(os.path.dirname(p), "Letter to my family.html"))
    print("CARDS\t" + cards.write(code, two, held, now()))
    print(msg)
    return 0


def newest():
    """The newest envelope file, or ""."""
    for p in read_state().get("paths", []):
        if os.path.isfile(p):
            return p
    folder = os.path.join(DOCS, FOLDER)
    try:
        found = sorted(f for f in os.listdir(folder) if NAME_RX.match(f))
    except OSError:
        found = []
    return os.path.join(folder, found[-1]) if found else ""


def test(typed, path=""):
    """Exit 0 the envelope opens and is whole, 1 wrong code or damaged, 3 no envelope."""
    path = path or newest()
    if not path or not os.path.isfile(path):
        print("No Emergency Envelope found. Make one first.")
        return 3
    code = words.tidy(typed)
    rc, out = run([SEVEN, "l", "-y", "--", path], 600, stdin=code + "\n")
    if rc == 0 and "Open me first.html" in out and pack.test(path, code):
        print("Your envelope opens with that code and everything in it is readable (%s)." % os.path.basename(path))
        return 0
    if rc == 127:
        print("7-Zip is missing, so the envelope could not be tested.")
        return 3
    print("The envelope did NOT open with that code. Check the words on the code card%s." % (
        " (Half A, one space, then Half B)" if read_state().get("two") else ""))
    return 1


def legacy_open(item):
    for i, company, url, _what in draft.legacy_list():
        if i == item and re.match(r"^https://[A-Za-z0-9./?=_-]+$", url):
            rc, _out = run(["xdg-open", url], 30)
            print("Opened %s's page in the browser." % company if rc == 0 else "The browser could not be opened.")
            return 0 if rc == 0 else 1
    print("That item has no web page.")
    return 3

"""Money lock: while anyone can see or control the screen, bank, payment, gift-card and crypto websites
are locked for the whole PC (every browser and app) with a marked block in /etc/hosts.

Lines outside our block are never touched (Always-On Guard's Website Guard keeps its own block).
Root writes the file through pkexec /usr/libexec/forgeos-techguard-money (no password at the PC).
"""
import os
import re

from . import ENV, HOSTS, MONEY_HELPER, SHARE, is_root, run

BEGIN = "# >>> ForgeOS Fake Tech Support Guard: money websites locked while someone can see this screen >>>"
END = "# <<< ForgeOS Fake Tech Support Guard <<<"
PREFIXES = ("", "www.", "secure.", "online.", "login.", "logon.", "signin.", "auth.", "my.", "account.",
            "accounts.", "onlinebanking.", "banking.", "m.", "mobile.", "app.")
DOMAIN = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")


def sites():
    """The money websites from the list (lower case, checked, no doubles)."""
    found = []
    try:
        with open(os.path.join(SHARE, "money-sites.txt"), encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        lines = []
    for line in lines:
        d = line.split("#", 1)[0].strip().lower()
        if DOMAIN.match(d) and d not in found:
            found.append(d)
    return found


def _read():
    with open(HOSTS, encoding="utf-8") as f:
        return f.read().splitlines()


def outside(lines):
    """The hosts file without our block (exactly as it was before we added it)."""
    keep, skip = [], False
    for line in lines:
        if line == BEGIN:
            skip = True
        elif line == END:
            skip = False
        elif not skip:
            keep.append(line)
    return keep


def locked():
    try:
        return BEGIN in _read()
    except OSError:
        return False


def _put(lines):
    """Write the hosts file IN PLACE (same file, same owner and SELinux label); put it back if it fails."""
    try:
        old = _read()
    except OSError:
        return False
    text = "\n".join(lines) + "\n"
    try:
        with open(HOSTS, "w", encoding="utf-8") as f:
            f.write(text)
        if "\n".join(_read()) + "\n" == text:
            return True
    except OSError:
        pass
    try:
        with open(HOSTS, "w", encoding="utf-8") as f:
            f.write("\n".join(old) + "\n")
    except OSError:
        pass
    return False


def root_lock():
    try:
        lines = outside(_read())
    except OSError:
        return False
    block = [BEGIN]
    for d in sites():
        for p in PREFIXES:
            block += ["0.0.0.0 " + p + d, ":: " + p + d]
    return _put(lines + block + [END])


def root_unlock():
    try:
        lines = _read()
    except OSError:
        return False
    return True if BEGIN not in lines else _put(outside(lines))


def root_do(what):
    """The root half (forgeos-techguard-money). Exit 0 done, 1 failed, 3 wrong use."""
    if what == "lock":
        ok = root_lock()
        print("Money websites are locked." if ok else "Could not lock the money websites.")
    elif what == "unlock":
        ok = root_unlock()
        print("Money websites are open again." if ok else "Could not open the money websites again.")
    else:
        return 3
    return 0 if ok else 1


def set_lock(on):
    """As yourself: lock (True) or open (False) the money websites. True when it is done."""
    if locked() == on:
        return True
    if is_root():
        return root_do("lock" if on else "unlock") == 0
    code = run([ENV("FORGEOS_TG_PKEXEC") or "pkexec", MONEY_HELPER, "lock" if on else "unlock"], 60)[0]
    return code == 0 and locked() == on

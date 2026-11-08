"""PC unlock for family: an extra key on the drive's lock (LUKS full-disk encryption), so your family can
start this PC with the 8-word PC unlock code from the envelope. Without it a locked drive can never be
opened again.

The first time it needs the disk password you type when the PC starts. ForgeOS keeps its own copy of the
current PC unlock code where only the system can read it (/var/lib/forgeos-digitalwill, on the locked drive), so
a new envelope swaps the old code for a new one without asking again. Your own disk password never changes.
"""
import json
import os
import re

from . import CRYPTSETUP, MEDIA, UNLOCK_HELPER, VAR, clean, is_root, now, read_state, run, user, write_state

KEYS_RX = re.compile(r"^[a-z]{3,9}( [a-z]{3,9}){7}$")
SYSTEM = ("/", "/sysroot", "/var", "/var/home", "/home", "/usr")


def blocks():
    rc, out = run(["lsblk", "-J", "-b", "-o", "PATH,FSTYPE,TYPE,RM,HOTPLUG,LABEL,SIZE,MOUNTPOINTS"], 30)
    try:
        return json.loads(out).get("blockdevices", []) if rc == 0 else []
    except ValueError:
        return []


def sticks():
    """[(folder, name)] of the USB sticks and drives plugged in and open (under /run/media/<you>)."""
    found, mine = [], os.path.join(MEDIA, user()) + os.sep

    def walk(node, removable):
        removable = removable or node.get("rm") in (True, "1") or node.get("hotplug") in (True, "1")
        for m in node.get("mountpoints") or []:
            if removable and m and m.startswith(mine) and os.path.isdir(m):
                found.append((m, clean(node.get("label") or os.path.basename(m), 40)))
        for c in node.get("children") or []:
            walk(c, removable)
    for n in blocks():
        walk(n, False)
    return found


def devices():
    """The locked (LUKS) partitions that hold this PC's system or home folder."""
    tree, found = blocks(), []

    def mounted(node):
        points = [m for m in (node.get("mountpoints") or []) if m]
        return any(m in SYSTEM for m in points) or any(mounted(c) for c in node.get("children") or [])

    def walk(node):
        if node.get("fstype") == "crypto_LUKS" and mounted(node) and node.get("path"):
            found.append(node["path"])
        for c in node.get("children") or []:
            walk(c)
    for n in tree:
        walk(n)
    return found


def status():
    """no-luks | added | not-added (the drive is locked, but no PC unlock code yet)."""
    if not devices():
        return "no-luks"
    return "added" if read_state().get("unlock_added") else "not-added"


def add(code, disk_password=""):
    """Put a new PC unlock code on every locked system drive (asks for the PC password through polkit).
    Returns "" when done, else why not."""
    devs = devices()
    if not devs:
        return "This PC's drive is not locked, so your family only needs your sign-in password."
    for dev in devs:
        rc, out = run(["pkexec", UNLOCK_HELPER, "add", dev], 300, stdin=code + "\n" + disk_password + "\n")
        if rc == 2:
            return "That is not the disk password (the one you type when the PC starts). Nothing was changed."
        if rc in (126, 127):
            return "The PC password was not given, so the PC unlock code was not added."
        if rc != 0:
            return "The PC unlock code could not be added: " + (clean(out, 150) or "unknown problem") + "."
    st = read_state()
    st["unlock_added"] = now()
    write_state(st)
    return ""


def keyfile(dev):
    return os.path.join(VAR, "unlock-%s.key" % re.sub(r"[^A-Za-z0-9]+", "_", dev).strip("_"))


def cs(args, stdin=None):
    return run([CRYPTSETUP] + args, 300, stdin=stdin)[0]


def root_add(dev, given):
    """Root half (through /usr/libexec/forgeos-digitalwill-unlock). given = 'new code\\ndisk password\\n'.
    Exit 0 done, 2 wrong disk password, 3 refused."""
    lines = (given.split("\n") + ["", ""])[:2]
    code, disk = lines[0].strip(), lines[1]
    if not is_root() or dev not in devices() or not KEYS_RX.match(code):
        return 3
    os.makedirs(VAR, mode=0o700, exist_ok=True)
    os.chmod(VAR, 0o700)
    old, new = keyfile(dev), keyfile(dev) + ".new"
    with open(os.open(new, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600), "w") as f:
        f.write(code)  # no newline: the code typed at start-up is exactly these letters
    have_old = os.path.isfile(old) and cs(["open", "--test-passphrase", "--key-file", old, dev]) == 0
    if have_old:
        rc = cs(["luksAddKey", "--key-file", old, dev, new])
    else:
        rc = cs(["luksAddKey", dev, new], stdin=disk + "\n") if disk else 2
    if rc != 0 or cs(["open", "--test-passphrase", "--key-file", new, dev]) != 0:
        os.unlink(new)
        return 2 if not have_old else 3
    if have_old and open(old).read() != code:
        cs(["luksRemoveKey", dev, old])
    os.replace(new, old)
    return 0

"""Where your old stuff is: the Windows drive on this PC, an old PC's drive, or a Moving Box USB stick.

Drives are opened READ-ONLY by the root helper /usr/libexec/forgeos-movingday-mount (your PC password,
polkit org.forgeos.movingday.mount). BitLocker drives open with the 48-digit recovery key.
"""
import json
import os

from . import BOX, ENV, MOUNT, clean, gb, path_in, run

TYPES = ("ntfs", "BitLocker", "exfat", "vfat")
SKIP_PARTS = ("c12a7328-f81f-11d2-ba4b-00a0c93ec93b",  # EFI start-up partition
              "e3c9e316-0b5c-4db8-817d-f92df00215ae",  # Microsoft reserved
              "de94bba4-06d1-4d40-a16a-bfd50179d6ac")  # Windows recovery
SYSTEM = ("/", "/boot", "/boot/efi", "/efi", "/usr", "/var", "/sysroot", "/etc", "/home", "/var/home")


def kind(root):
    """box / windows / drive (has a Users folder) / folder."""
    if path_in(root, BOX, "box.json") or (os.path.basename(root) == BOX and path_in(root, "box.json")):
        return "box"
    if path_in(root, "Users") and path_in(root, "Windows", "System32"):
        return "windows"
    return "drive" if path_in(root, "Users") else "folder"


def base(root):
    """The folder that holds Users\\..., for a Moving Box the box folder itself."""
    return path_in(root, BOX) if path_in(root, BOX, "box.json") else root


def parts():
    """Every partition as a dict (lsblk tree, so USB is known from the disk)."""
    code, out = run(["lsblk", "-J", "-p", "-o", "PATH,FSTYPE,SIZE,LABEL,MOUNTPOINT,PARTTYPE,TRAN,RM,TYPE"], 20)
    try:
        tree = json.loads(out).get("blockdevices", []) if code == 0 else []
    except ValueError:
        tree = []
    found = []

    def walk(nodes, usb):
        for n in nodes:
            here = usb or n.get("tran") == "usb" or str(n.get("rm")).lower() in ("1", "true")
            kids = n.get("children") or []
            if n.get("type") in ("part", "crypt", "disk") and n.get("fstype"):
                found.append(dict(n, usb=here, inside=any(k.get("mountpoint") for k in kids)))
            walk(kids, here)
    walk(tree, False)
    return found


def find():
    """SOURCE lines: dev, kind, open|closed|locked, path, label, size, usb."""
    rows, seen = [], set()
    for p in parts():
        dev, fs, mnt = p.get("path") or "-", p.get("fstype") or "", p.get("mountpoint") or ""
        if fs not in TYPES or (p.get("parttype") or "").lower() in SKIP_PARTS or mnt in SYSTEM or p["inside"]:
            continue
        label, size, usb = clean(p.get("label") or "", 40) or "-", p.get("size") or "-", "yes" if p["usb"] else "no"
        if mnt:
            k = kind(mnt)
            if k == "folder":
                k = "stick" if p["usb"] else ""
            if k:
                rows.append((dev, k, "open", mnt, label, size, usb))
                seen.add(mnt)
        elif fs == "BitLocker":
            rows.append((dev, "drive", "locked", "-", label, size, usb))
        else:
            rows.append((dev, "drive", "closed", "-", label, size, usb))
    for extra in (ENV("FORGEOS_MD_ROOTS") or "").split(":"):
        if extra and os.path.isdir(extra) and extra not in seen:
            rows.append(("-", kind(extra), "open", extra, os.path.basename(extra) or "-", "-", "no"))
    return rows


def describe(row):
    """Plain words for one SOURCE row, for the window's list."""
    dev, k, state, path, label, size, usb = row
    what = {"windows": "Windows drive", "box": "Moving Box", "drive": "Drive", "stick": "USB stick"}.get(k, "Folder")
    where = "USB " if usb == "yes" and k not in ("stick", "box") else ""
    name = "" if label == "-" else " \"%s\"" % label
    extra = {"locked": " - locked with BitLocker", "closed": " - not opened yet"}.get(state, "")
    return "%s%s%s (%s)%s" % (where, what, name, size if size != "-" else path, extra)


def open_dev(dev, key=None):
    """Open a drive read-only. (0, folder) or (code, message). 5 = needs the BitLocker key, 6 = wrong key."""
    cmd = [ENV("FORGEOS_MD_PKEXEC") or "pkexec", MOUNT, "open", dev] + (["--key-stdin"] if key else [])
    code, out = run(cmd, 120, stdin=key)
    for line in out.splitlines():
        f = line.split("\t")
        if f[0] == "OPEN" and len(f) >= 3 and code == 0:
            return 0, f[2]
    if code in (126, 127):
        return 1, "You said No to the password, so the drive was not opened."
    msg = " ".join(x for x in out.splitlines() if "\t" not in x)
    return (code or 1), clean(msg, 300) or "The drive could not be opened."


def close_dev(dev):
    code, _out = run([ENV("FORGEOS_MD_PKEXEC") or "pkexec", MOUNT, "close", dev], 60)
    return code


def free_space(folder):
    """Free bytes where Moving Day copies to (FORGEOS_MD_FREE overrides it for tests)."""
    if ENV("FORGEOS_MD_FREE"):
        return int(ENV("FORGEOS_MD_FREE"))
    st = os.statvfs(folder)
    return st.f_bavail * st.f_frsize


def free_words(folder):
    return gb(free_space(folder))

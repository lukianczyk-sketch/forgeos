"""The Moving Box USB stick: "Pack my old PC" for an old Windows PC that can't be opened up.

The Windows files get Windows line endings (CRLF). Nothing else on the stick is touched.
"""
import os

from . import SHARE
from . import sources

STICK_FILES = (("Pack my old PC.cmd", ""), ("pack.ps1", "ForgeOS Moving Day"))


def pack(rest):
    if len(rest) != 1 or not os.path.isdir(rest[0]) or not os.access(rest[0], os.W_OK):
        print("Pick a USB stick that ForgeOS can write to.")
        return 3
    if sources.kind(rest[0]) == "windows":
        print("That is a Windows drive. Pick a USB stick.")
        return 3
    for name, sub in STICK_FILES:
        dest = os.path.join(rest[0], sub, name) if sub else os.path.join(rest[0], name)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(os.path.join(SHARE, name), encoding="utf-8") as a, open(dest, "w", encoding="utf-8", newline="\r\n") as b:
            b.write(a.read())
    print("PACKED\t%s" % rest[0])
    print("Done. On the old Windows PC, open the stick and double-click \"Pack my old PC\". When it says Done,"
          " plug the stick into this PC and open Moving Day.")
    return 0

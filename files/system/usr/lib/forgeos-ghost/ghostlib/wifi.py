"""Nearby Wi-Fi: cheap hidden cameras make their own little Wi-Fi network to be set up from a phone."""
import re

from . import run

# Setup networks cheap spy cameras make: "IPC-XXXXX" (FCC manual 2A5I7A10PLUS), V380..., HDWiFiCam...
SPY_NAMES = re.compile(r"^(IPC-|V380|HDWiFiCam)|spy.?cam|mini.?cam|hidden.?cam|nanny.?cam", re.I)


def _fields(line):
    """Split one nmcli -t line on ':' (a '\\:' inside a value is a real colon)."""
    out, cur, esc = [], "", False
    for ch in line:
        if esc:
            cur, esc = cur + ch, False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            out, cur = out + [cur], ""
        else:
            cur += ch
    return out + [cur]


def networks(rescan=True):
    """[(name, bssid, signal 0-100, in use)] for every Wi-Fi network this PC can hear."""
    cmd = ["nmcli", "-t", "-f", "IN-USE,SSID,BSSID,SIGNAL", "device", "wifi", "list", "--rescan"]
    out = run(cmd + ["yes"], timeout=25) if rescan else ""
    out = out or run(cmd + ["no"])  # a fresh scan can be refused right after another one
    nets = []
    for line in out.splitlines():
        f = _fields(line)
        if len(f) == 4 and f[3].isdigit():
            nets.append((f[1], f[2].upper(), int(f[3]), f[0] == "*"))
    return nets


def spy_hotspots(nets):
    return [(name, bssid, sig) for name, bssid, sig, _ in nets if name and SPY_NAMES.search(name)]


def place(nets=None):
    """Where this PC is right now, for "is it following me?": the Wi-Fi it is on, else "no Wi-Fi"."""
    for name, bssid, _, used in nets if nets is not None else networks(rescan=False):
        if used:
            return "%s (%s)" % (name or "hidden network", bssid)
    return "no Wi-Fi"


def signal(bssid):
    """Signal 0-100 of one Wi-Fi network right now (None if it cannot be heard)."""
    for _, b, sig, _ in networks():
        if b == bssid.upper():
            return sig
    return None

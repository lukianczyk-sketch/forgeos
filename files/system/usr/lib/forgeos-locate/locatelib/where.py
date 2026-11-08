"""Where is the PC? Only asked while it is marked lost (or for the phone's test).
- Nearby Wi-Fi (nmcli) -> beaconDB, the free open location service (no Google). Needs 2 or more networks.
- Backup: the public internet address -> rough city (ipinfo.io).
- Plus the Wi-Fi it is on, the battery, who is signed in, and (only if you turned it on) a small webcam photo.
"""
import glob
import math
import os
import re
import socket

from . import ENV, RUN, clean, now, remove, run, settings
from .relay import get_json

SYSFS = ENV("FORGEOS_LOC_SYS") or "/sys/class/power_supply"
CAMERA = ENV("FORGEOS_LOC_CAMERA") or "/dev/video0"
BSSID = re.compile(r"^[0-9A-F]{2}(:[0-9A-F]{2}){5}$")


def _fields(line):
    """nmcli -t splits with ':' and writes a real ':' as '\\:'."""
    out, cur, i = [], "", 0
    while i < len(line):
        if line[i] == "\\" and i + 1 < len(line):
            cur += line[i + 1]
            i += 2
            continue
        if line[i] == ":":
            out.append(cur)
            cur = ""
        else:
            cur += line[i]
        i += 1
    return out + [cur]


def wifi(rescan=True):
    """Nearby Wi-Fi: list of dicts (bssid, signal 0-100, open, ssid, using)."""
    _c, out = run(["nmcli", "-t", "-f", "IN-USE,BSSID,SIGNAL,SECURITY,SSID", "device", "wifi", "list",
                   "--rescan", "yes" if rescan else "no"], 40)
    found = []
    for line in out.splitlines():
        f = _fields(line)
        if len(f) != 5 or not BSSID.match(f[1].upper()) or not f[2].isdigit():
            continue
        found.append({"bssid": f[1].upper(), "signal": min(100, int(f[2])), "open": f[3].strip() in ("", "--"),
                      "ssid": clean(f[4], 40), "using": f[0].strip() == "*"})
    return found


def from_wifi(aps):
    """(lat, lon, metres) from beaconDB, or None. dBm is about signal/2 - 100."""
    if len(aps) < 2:
        return None
    body = {"considerIp": False, "wifiAccessPoints": [
        {"macAddress": a["bssid"].lower(), "signalStrength": a["signal"] // 2 - 100}
        for a in sorted(aps, key=lambda a: -a["signal"])[:20]]}
    got = get_json(settings()["geo"], body)
    loc = got.get("location") or {}
    try:
        lat, lon, acc = float(loc["lat"]), float(loc["lng"]), float(got.get("accuracy", 0))
    except (KeyError, TypeError, ValueError):
        return None
    if not all(math.isfinite(x) for x in (lat, lon, acc)) or abs(lat) > 90 or abs(lon) > 180:
        return None
    return round(lat, 6), round(lon, 6), int(min(max(acc, 0), 100000))


def from_ip():
    """Public address, rough city and (lat, lon) from ipinfo.io; {} when there is no answer."""
    got = get_json(settings()["ip"])
    if not got.get("ip"):
        return {}
    out = {"ip": clean(got["ip"], 45),
           "city": clean(", ".join(x for x in (got.get("city"), got.get("region"), got.get("country")) if x), 80)}
    try:
        lat, lon = (float(x) for x in str(got.get("loc", "")).split(","))
        if math.isfinite(lat) and math.isfinite(lon) and abs(lat) <= 90 and abs(lon) <= 180:
            out["lat"], out["lon"] = round(lat, 4), round(lon, 4)
    except ValueError:
        pass
    return out


def battery():
    """(percent, charging) of the first battery, or (None, None) on a desktop PC."""
    for d in sorted(glob.glob(os.path.join(SYSFS, "BAT*"))):
        try:
            with open(os.path.join(d, "capacity")) as f:
                pct = int(f.read().strip())
            with open(os.path.join(d, "status")) as f:
                return pct, f.read().strip() in ("Charging", "Full")
        except (OSError, ValueError):
            continue
    return None, None


def users():
    """Who is signed in right now (names only)."""
    _c, out = run(["who"], 10)
    names = []
    for line in out.splitlines():
        n = clean(line.split(" ")[0], 32)
        if n and n not in names:
            names.append(n)
    return names


def photo():
    """A small webcam photo (JPEG bytes, at most 12 KB) or None. Only when you turned photos on.
    Tries 320 pixels wide, then smaller and rougher if that is too big."""
    path = os.path.join(RUN, "photo.jpg")
    for width, rough in ((320, 10), (240, 20)):
        remove(path)
        code, _o = run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "v4l2", "-i", CAMERA, "-frames:v", "1",
                        "-vf", "scale=%d:-2" % width, "-q:v", str(rough), "-y", path], 30)
        try:
            with open(path, "rb") as f:
                data = f.read(12289)
        except OSError:
            return None
        finally:
            remove(path)
        if code != 0 or len(data) < 100 or data[:2] != b"\xff\xd8":
            return None
        if len(data) <= 12288:
            return data
    return None


def report():
    """One report: where (Wi-Fi first, then the internet address), the Wi-Fi name, battery, who, time."""
    aps = wifi()
    r = {"k": "where", "t": int(now()), "host": clean(socket.gethostname(), 40), "users": users()}
    spot = from_wifi(aps)
    ip = from_ip()
    if spot:
        r.update({"lat": spot[0], "lon": spot[1], "acc": spot[2], "src": "wifi"})
    elif "lat" in ip:
        r.update({"lat": ip["lat"], "lon": ip["lon"], "acc": 10000, "src": "ip"})
    else:
        r["src"] = "none"
    r.update({k: ip[k] for k in ("ip", "city") if k in ip})
    using = [a["ssid"] for a in aps if a["using"]]
    r["wifi"], r["seen"] = (using[0] if using else ""), len(aps)
    r["bat"], r["chg"] = battery()
    return r

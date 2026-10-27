"""Plain-English names for devices: maker (from the free IEEE list in hwdata) and what they say they are (mDNS)."""
import re

from . import env, run

CAMERA_MAKERS = ("hikvision", "dahua", "xiongmai", "wyze", "reolink", "amcrest", "foscam", "arlo",
                 "ezviz", "uniview", "axis communications", "hanwha", "lorex", "swann", "vivotek",
                 "ring llc")
CAMERA_CHIPS = ("ingenic", "anyka", "hisilicon")
GADGET_MAKERS = ("espressif", "tuya", "beken", "bouffalo", "winner micro", "shenzhen", "hangzhou")
MAKER_WORDS = [
    ("apple", "Apple device (iPhone, iPad, Mac, Apple TV...)"),
    ("samsung", "Samsung device (phone, TV...)"),
    ("google", "Google / Nest device"),
    ("amazon", "Amazon device (Echo, Fire TV, Kindle...)"),
    ("roku", "Roku TV or streaming stick"),
    ("sonos", "Sonos speaker"),
    ("hewlett packard", "HP printer or computer"),
    ("hp inc", "HP printer or computer"),
    ("canon", "Canon printer or camera"),
    ("seiko epson", "Epson printer"),
    ("brother", "Brother printer"),
    ("nintendo", "Nintendo game console"),
    ("sony", "Sony device (PlayStation, TV...)"),
    ("microsoft", "Microsoft device (Xbox, Surface...)"),
    ("netgear", "Netgear network gear"),
    ("tp-link", "TP-Link device (Wi-Fi gear, smart plug or camera)"),
]
SERVICE_WORDS = [
    ("_rtsp._tcp", "camera video stream"),
    ("_ipp._tcp", "printer"), ("_printer._tcp", "printer"), ("_uscan._tcp", "printer / scanner"),
    ("_googlecast._tcp", "TV or Chromecast"),
    ("_airplay._tcp", "Apple TV, AirPlay TV or speaker"), ("_raop._tcp", "AirPlay speaker or TV"),
    ("_hap._tcp", "smart-home gadget (HomeKit)"),
    ("_spotify-connect._tcp", "speaker"), ("_sonos._tcp", "Sonos speaker"),
    ("_amzn-wplay._tcp", "Fire TV"),
    ("_companion-link._tcp", "iPhone, iPad or Mac"),
    ("_smb._tcp", "computer sharing files"), ("_workstation._tcp", "computer"),
]

_OUI = None


def private_mac(mac):
    """Phones and laptops hide their maker with a made-up address (2nd digit 2, 6, A or E)."""
    return len(mac) > 1 and mac[1].lower() in "26ae"


def maker(mac):
    """Company that made the network chip, from /usr/share/hwdata/oui.txt ("" if unknown)."""
    global _OUI
    if _OUI is None:
        _OUI = {}
        try:
            with open(env("FORGEOS_GHOST_OUI", "/usr/share/hwdata/oui.txt"), encoding="utf-8", errors="replace") as f:
                for line in f:
                    if "(base 16)" in line:
                        key, _, name = line.partition("(base 16)")
                        _OUI[key.strip().upper()] = name.strip()
        except OSError:
            pass
    return _OUI.get(mac.replace(":", "").upper()[:6], "")


def _unescape(text):
    """avahi writes a space as \\032 and a dot as \\046."""
    return re.sub(r"\\(\d{3})", lambda m: chr(int(m.group(1))), text)


def services():
    """{address: [(name, service type)]} from devices that announce themselves (mDNS)."""
    found = {}
    for line in run(["avahi-browse", "-aprt"], timeout=8).splitlines():
        f = line.split(";")
        if len(f) >= 9 and f[0] == "=" and f[2] == "IPv4":
            found.setdefault(f[7], []).append((_unescape(f[3]), f[4]))
    return found


def describe(mac, svcs, is_router=False):
    """(kind, plain words, maker). kind: router, camera, chip, gadget, private, device."""
    made = maker(mac)
    low = made.lower()
    types = [t for _, t in svcs]
    if is_router:
        return "router", "your router (the box that gives you Wi-Fi)", made
    if "_rtsp._tcp" in types or any(w in low for w in CAMERA_MAKERS):
        return "camera", "camera" + (" made by " + made if made else ""), made
    for t, words in SERVICE_WORDS:
        if t in types:
            return "device", words, made
    if any(w in low for w in CAMERA_CHIPS):
        return "chip", "gadget with a chip often used in cheap cameras (" + made + ")", made
    if any(w in low for w in GADGET_MAKERS):
        return "gadget", "small smart gadget - a plug, bulb... or a cheap camera (" + made + ")", made
    for w, words in MAKER_WORDS:
        if w in low:
            return "device", words, made
    if private_mac(mac):
        return "private", "phone, tablet or laptop (hides its maker - normal for phones)", made
    return "device", "device made by " + made if made else "device (maker unknown)", made

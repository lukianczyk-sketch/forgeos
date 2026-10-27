"""The network you are on: every device on it, and which ones act like cameras.

No root needed: one tiny UDP packet to every address makes the PC ask "who has this address?"
(ARP), and every device answers that, even with a firewall. Then we read the PC's neighbor list.
"""
import ipaddress
import json
import re
import socket
import threading
import time

from . import env, run

# Ports only cameras / video recorders use. Port 80 alone means nothing (routers, printers...).
CAMERA_PORTS = {
    554: "video stream (RTSP)",
    8554: "video stream (RTSP)",
    8000: "Hikvision camera control",
    37777: "Dahua camera control",
    34567: "XMEye camera / recorder control",
}
WSD_PROBE = (
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"'
    ' xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"'
    ' xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"'
    ' xmlns:dn="http://www.onvif.org/ver10/network/wsdl">'
    "<e:Header><w:MessageID>uuid:%s</w:MessageID>"
    '<w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>'
    '<w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>'
    "</e:Header><e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body></e:Envelope>"
)


def ports():
    """Camera ports to try (tests: FORGEOS_GHOST_PORTS="15540:video stream (RTSP),...")."""
    spec = env("FORGEOS_GHOST_PORTS")
    if not spec:
        return dict(CAMERA_PORTS)
    return {int(p.split(":", 1)[0]): p.split(":", 1)[1] for p in spec.split(",")}


def _json(cmd):
    try:
        return json.loads(run(cmd) or "[]")
    except ValueError:
        return []


def my_network():
    """(device, my address, network) of the main connection, or None when offline."""
    route = _json(["ip", "-j", "route", "show", "default"])
    if not route or "dev" not in route[0]:
        return None
    dev = route[0]["dev"]
    for link in _json(["ip", "-j", "-4", "addr", "show", "dev", dev]):
        for a in link.get("addr_info", []):
            if a.get("family") == "inet":
                prefix = a.get("prefixlen", 24)
                prefix = 24 if prefix < 22 else prefix  # big networks: just our own block of 256
                net = ipaddress.ip_network("%s/%d" % (a["local"], prefix), strict=False)
                return dev, a["local"], net, route[0].get("gateway", "")
    return None


def wake(net, mine):
    """Knock once on every address so each device shows up in the neighbor list."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    for host in net.hosts():
        if str(host) != mine:
            try:
                s.sendto(b"\0", (str(host), 9))
            except OSError:
                pass
    s.close()
    time.sleep(float(env("FORGEOS_GHOST_WAIT", "2")))


def neighbors(dev):
    """[(address, mac)] for every device that answered."""
    out = []
    for n in _json(["ip", "-j", "-4", "neigh", "show", "dev", dev]):
        state = n.get("state", [])
        if n.get("lladdr") and "FAILED" not in state and "INCOMPLETE" not in state:
            out.append((n["dst"], n["lladdr"].lower()))
    return out


def open_ports(addrs, wanted):
    """{address: [open camera ports]} trying all at once (0.5 s each)."""
    found = {}

    def knock(a, p):
        try:
            with socket.create_connection((a, p), timeout=0.5):
                found.setdefault(a, []).append(p)
        except OSError:
            pass

    jobs = [threading.Thread(target=knock, args=(a, p), daemon=True) for a in addrs for p in wanted]
    for i in range(0, len(jobs), 64):
        for j in jobs[i:i + 64]:
            j.start()
        for j in jobs[i:i + 64]:
            j.join(2)
    return {a: sorted(p) for a, p in found.items()}


def onvif_cameras(secs=2.0):
    """Addresses of devices that answer the standard "are you a network camera?" call (ONVIF)."""
    target = env("FORGEOS_GHOST_WSD", "239.255.255.250:3702").rsplit(":", 1)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(0.3)
    cams = set()
    try:
        s.sendto((WSD_PROBE % ("forgeos-%d" % time.time())).encode(), (target[0], int(target[1])))
        end = time.time() + secs
        while time.time() < end:
            try:
                data, src = s.recvfrom(65535)
            except socket.timeout:
                continue
            text = data.decode("utf-8", "replace")
            if "NetworkVideoTransmitter" in text or "onvif" in text.lower():
                hosts = re.findall(r"https?://\[?([0-9.]+)", text)
                cams.update(hosts or [src[0]])
    except OSError:
        pass
    finally:
        s.close()
    return cams

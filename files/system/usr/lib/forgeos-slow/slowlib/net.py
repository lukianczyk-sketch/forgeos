"""Check 9: is it the internet, not the PC? Wi-Fi signal, the router, the internet itself, finding websites."""
import re
import socket
import threading
import time

from . import ENV, run
from .checks import ok, problem


def ping(host):
    """(average ms, lost %) of 3 pings, or (None, 100)."""
    code, out = run(["ping", "-n", "-c", "3", "-W", "2", host], 15)
    lost = re.search(r"([0-9.]+)% packet loss", out)
    avg = re.search(r"= [0-9.]+/([0-9.]+)/", out)
    return (float(avg.group(1)) if avg else None), (float(lost.group(1)) if lost else 100.0)


def lookup_secs(host):
    """How long it takes to look up a website's name (None = it did not work in 5 seconds)."""
    box = []

    def go():
        t = time.time()
        try:
            socket.getaddrinfo(host, 443)
            box.append(time.time() - t)
        except OSError:
            pass
    th = threading.Thread(target=go, daemon=True)
    th.start()
    th.join(5)
    return box[0] if box else None


def internet():
    code, out = run(["ip", "-4", "route", "show", "default"], 10)
    gw = re.search(r"default via ([0-9.]+)", out)
    if not gw:
        return [problem("internet", "red", "This PC is not connected to the internet.", "internet",
                        "Restart the internet")]
    code, out = run(["nmcli", "-t", "-f", "ACTIVE,SIGNAL,SSID", "dev", "wifi"], 15)
    wifi = next((x.split(":") for x in out.splitlines() if x.startswith("yes:")), None)
    signal = int(wifi[1]) if wifi and wifi[1].isdigit() else None
    r_ms, r_lost = ping(gw.group(1))
    i_ms, i_lost = ping(ENV("FORGEOS_SLOW_PING") or "9.9.9.9")
    dns = lookup_secs(ENV("FORGEOS_SLOW_LOOKUP") or "example.com")
    if signal is not None and signal < 40:
        return [problem("internet", "yellow", "Your PC is fine. The Wi-Fi signal is weak (%d of 100) - move closer"
                        " to the router or restart the router." % signal)]
    if r_lost > 0 or (r_ms or 0) > 50:
        return [problem("internet", "yellow", "Your PC is fine. The connection to your router is poor - restart"
                        " the router (unplug it for 30 seconds).")]
    if i_lost > 0 or i_ms is None or i_ms > 200:
        return [problem("internet", "yellow", "Your PC and your router are fine. The internet itself is slow right"
                        " now - that is your internet company. Restarting the router can help.")]
    if dns is None or dns > 1.0:
        return [problem("internet", "yellow", "Finding websites by name is slow. Restarting the router usually"
                        " fixes it.", "internet", "Restart the internet")]
    return [ok("internet", "Internet: fine (%d ms)." % i_ms)]

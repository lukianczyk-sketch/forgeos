#!/usr/bin/env python3
"""Fake network for the GhostFinder tests (Job 12): 127.0.0.11 has a camera video port open, and a
fake camera answers the ONVIF "are you a network camera?" call for 127.0.0.12.
Writes its ports to WORK/rtsp-port and WORK/wsd-port; the probe it got goes to WORK/wsd-probe."""
import os
import socket
import sys
import threading

WORK = sys.argv[1]
REPLY = (
    '<?xml version="1.0" encoding="UTF-8"?><e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"'
    ' xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"><e:Body><d:ProbeMatches><d:ProbeMatch>'
    "<d:Types>dn:NetworkVideoTransmitter</d:Types>"
    "<d:XAddrs>http://127.0.0.12/onvif/device_service</d:XAddrs>"
    "</d:ProbeMatch></d:ProbeMatches></e:Body></e:Envelope>"
)

tcp = socket.socket()
tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
tcp.bind(("127.0.0.11", 0))
tcp.listen(16)
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.bind(("127.0.0.1", 0))


def accept():
    while True:
        conn, _ = tcp.accept()
        conn.close()


def answer():
    while True:
        data, src = udp.recvfrom(65535)
        with open(os.path.join(WORK, "wsd-probe"), "wb") as f:
            f.write(data)
        if b"NetworkVideoTransmitter" in data:
            udp.sendto(REPLY.encode(), src)


for name, sock in (("rtsp-port", tcp), ("wsd-port", udp)):
    with open(os.path.join(WORK, name + ".new"), "w") as f:
        f.write(str(sock.getsockname()[1]))
    os.replace(os.path.join(WORK, name + ".new"), os.path.join(WORK, name))
threading.Thread(target=accept, daemon=True).start()
answer()

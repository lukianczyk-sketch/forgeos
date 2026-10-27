#!/usr/bin/env python3
"""Write the fake Bluetooth world for the GhostFinder tests (Job 12).

Usage: ghost-ble-world.py FILE POWER BLOCKED POLL...
Each POLL is one second: devices joined by ";", each "ID,RSSI,KIND[,HEX]".
KIND: apple (manufacturer 0x004C data = HEX), svc:UUID (service data = HEX), uuid:UUID, none.
"""
import json
import sys

path, power, blocked, polls = sys.argv[1], sys.argv[2], sys.argv[3] == "1", []
for poll in sys.argv[4:]:
    devs = []
    for d in filter(None, poll.split(";")):
        f = d.split(",")
        dev = {"id": f[0], "rssi": int(f[1]), "name": ""}
        if f[2] == "apple":
            dev["mfg"] = {"0x004C": f[3]}
        elif f[2].startswith("svc:"):
            dev["svc"] = {f[2][4:]: f[3]}
        elif f[2].startswith("uuid:"):
            dev["uuids"] = [f[2][5:]]
        devs.append(dev)
    polls.append(devs)
with open(path, "w", encoding="utf-8") as f:
    json.dump({"power": power, "blocked": blocked, "polls": polls}, f)

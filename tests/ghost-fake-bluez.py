#!/usr/bin/env python3
"""A fake BlueZ (the Linux Bluetooth service) for the GhostFinder real test (Job 12).

Runs on a private D-Bus session bus with python3-dbus, so GhostFinder's real Bluetooth code is used.
Like BlueZ, devices only have a signal strength (RSSI) while discovery is on. Calls go to WORK/bluez.log.
The AirTag gets closer every time it is looked at (for the hunt meter).
"""
import os
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

WORK = sys.argv[1]
AD = "org.bluez.Adapter1"
DEV = "org.bluez.Device1"
BASE = "-0000-1000-8000-00805f9b34fb"


def log(text):
    with open(os.path.join(WORK, "bluez.log"), "a", encoding="utf-8") as f:
        f.write(text + "\n")


def ay(hexstr):
    return dbus.Array(bytearray.fromhex(hexstr), signature="y")


AIRTAG = "1219" + "50" * 23
DEVICES = {
    "AA_00_00_00_00_01": {"Address": "AA:00:00:00:00:01", "RSSI": -90,
                          "ManufacturerData": dbus.Dictionary({dbus.UInt16(0x004C): ay(AIRTAG)}, signature="qv")},
    "AA_00_00_00_00_02": {"Address": "AA:00:00:00:00:02", "RSSI": -50,
                          "ManufacturerData": dbus.Dictionary({dbus.UInt16(0x004C): ay("1202001A")}, signature="qv")},
    "AA_00_00_00_00_03": {"Address": "AA:00:00:00:00:03", "RSSI": -75,
                          "ServiceData": dbus.Dictionary({"0000fd5a" + BASE: ay("0300")}, signature="sv")},
    "AA_00_00_00_00_08": {"Address": "AA:00:00:00:00:08", "RSSI": -85, "Alias": "Tile",
                          "UUIDs": dbus.Array(["0000feed" + BASE], signature="s")},
    "AA_00_00_00_00_0C": {"Address": "AA:00:00:00:00:0C", "RSSI": None,  # remembered, not heard now
                          "ManufacturerData": dbus.Dictionary({dbus.UInt16(0x004C): ay(AIRTAG)}, signature="qv")},
}


class Bluez(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, "/")
        self.powered, self.discovering = True, False
        Adapter(bus, self)

    @dbus.service.method("org.freedesktop.DBus.ObjectManager", out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        objs = {dbus.ObjectPath("/org/bluez/hci0"): {AD: {"Powered": dbus.Boolean(self.powered),
                                                          "Discovering": dbus.Boolean(self.discovering)}}}
        for name, props in DEVICES.items():
            p = {k: v for k, v in props.items() if k != "RSSI"}
            p["AddressType"] = "random"
            if self.discovering and props["RSSI"] is not None:
                p["RSSI"] = dbus.Int16(props["RSSI"])
            objs[dbus.ObjectPath("/org/bluez/hci0/dev_" + name)] = {DEV: p}
        if self.discovering:  # the AirTag gets 15 dBm closer each look
            DEVICES["AA_00_00_00_00_01"]["RSSI"] = min(-40, DEVICES["AA_00_00_00_00_01"]["RSSI"] + 15)
        return objs


class Adapter(dbus.service.Object):
    def __init__(self, bus, root):
        super().__init__(bus, "/org/bluez/hci0")
        self.root = root

    @dbus.service.method(AD, in_signature="a{sv}")
    def SetDiscoveryFilter(self, f):
        log("SetDiscoveryFilter " + " ".join("%s=%s" % (k, f[k]) for k in sorted(f)))

    @dbus.service.method(AD)
    def StartDiscovery(self):
        log("StartDiscovery")
        if not self.root.powered:
            raise dbus.exceptions.DBusException("Resource Not Ready", name="org.bluez.Error.NotReady")
        self.root.discovering = True

    @dbus.service.method(AD)
    def StopDiscovery(self):
        log("StopDiscovery")
        self.root.discovering = False

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv")
    def Set(self, iface, name, value):
        log("Set %s %s %s" % (iface, name, bool(value)))
        if iface == AD and name == "Powered":
            self.root.powered = bool(value)


dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
BUS = dbus.SessionBus()
NAME = dbus.service.BusName("org.bluez", BUS)
Bluez(BUS)
log("ready")
GLib.MainLoop().run()

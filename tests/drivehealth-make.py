"""Writes pretend drive data for the Drive Health tests (Job 15).

  python3 tests/drivehealth-make.py smart FILE key=value...   a smartctl --json answer
    kind=nvme|ssd|hdd model= serial= passed=1|0 worn= bad= temp= hours= crit= spare= exit=
    failed= past= (an attribute name failing now / in the past) selftest=ok|fail devstat=1|0 life=ID:VALUE
  python3 tests/drivehealth-make.py lsblk FILE DEV:SIZE:TRAN:ROTA:MODEL...   the lsblk -d list
"""
import json
import sys


def smart(path, o):
    kind = o.get("kind", "nvme")
    d = {"smartctl": {"exit_status": int(o.get("exit", 0))}, "model_name": o.get("model", "Test Drive"),
         "serial_number": o.get("serial", "SN-SECRET-1"), "smart_status": {"passed": o.get("passed", "1") == "1"},
         "power_on_time": {"hours": int(o.get("hours", 1000))}, "temperature": {"current": int(o.get("temp", 40))}}
    if kind == "nvme":
        d["device"] = {"type": "nvme", "protocol": "NVMe"}
        d["nvme_smart_health_information_log"] = {
            "critical_warning": int(o.get("crit", 0)), "available_spare": int(o.get("spare", 100)),
            "available_spare_threshold": 10, "percentage_used": int(o.get("worn", 2)),
            "media_errors": int(o.get("bad", 0)), "temperature": int(o.get("temp", 40))}
        if "selftest" in o:
            d["nvme_self_test_log"] = {"table": [{"self_test_result": {"value": 7 if o["selftest"] == "fail" else 0}}]}
    else:
        d["device"] = {"type": "sat", "protocol": "ATA"}
        d["rotation_rate"] = 7200 if kind == "hdd" else 0
        bad = int(o.get("bad", 0))
        table = [{"id": 5, "name": "Reallocated_Sector_Ct", "value": 100, "thresh": 10, "when_failed": "",
                  "raw": {"value": bad}},
                 {"id": 197, "name": "Current_Pending_Sector", "value": 100, "thresh": 0, "when_failed": "",
                  "raw": {"value": 0}},
                 {"id": 9, "name": "Power_On_Hours", "value": 99, "thresh": 0, "when_failed": "", "raw": {"value": 1}}]
        if o.get("failed"):
            table.append({"id": 1, "name": o["failed"], "value": 1, "thresh": 6, "when_failed": "now", "raw": {"value": 9}})
        if o.get("past"):
            table.append({"id": 10, "name": o["past"], "value": 90, "thresh": 97, "when_failed": "past", "raw": {"value": 3}})
        if o.get("life"):
            i, v = o["life"].split(":")
            table.append({"id": int(i), "name": "Wear", "value": int(v), "thresh": 0, "when_failed": "", "raw": {"value": 0}})
        d["ata_smart_attributes"] = {"table": table}
        if kind == "ssd" and o.get("devstat", "1") == "1" and "worn" in o:
            d["ata_device_statistics"] = {"pages": [{"number": 7, "table": [
                {"name": "Percentage Used Endurance Indicator", "value": int(o["worn"])}]}]}
        if "selftest" in o:
            d["ata_smart_self_test_log"] = {"standard": {"table": [{"status": {"passed": o["selftest"] != "fail"}}]}}
    with open(path, "w") as f:
        json.dump(d, f)


def lsblk(path, rows):
    devs = []
    for r in rows:
        dev, size, tran, rota, model = r.split(":", 4)
        devs.append({"path": dev, "type": "disk", "tran": tran or None, "model": model, "size": int(size),
                     "rm": tran == "usb", "rota": rota == "1"})
    with open(path, "w") as f:
        json.dump({"blockdevices": devs}, f)


if sys.argv[1] == "smart":
    smart(sys.argv[2], dict(a.split("=", 1) for a in sys.argv[3:]))
else:
    lsblk(sys.argv[2], sys.argv[3:])

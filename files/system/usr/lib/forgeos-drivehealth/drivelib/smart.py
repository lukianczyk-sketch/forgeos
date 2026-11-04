"""Turns a drive's health report (smartctl JSON) into a few plain facts.

ATA/SATA attributes: 5 reallocated sectors, 187 reported uncorrectable, 197 pending sectors,
198 offline uncorrectable = "bad sectors". Wear comes from the drive's own "percentage used" (NVMe, ATA
device statistics) or, for older SSDs, from their wear attributes (177, 231, 233, 202, 169: value = life left).
"""
BAD_ATTRS = (5, 187, 197, 198)
LIFE_ATTRS = (231, 233, 177, 202, 169)
NVME_FAILING = 0x01 | 0x04 | 0x08  # spare space too low, reliability degraded, the drive went read-only
NVME_HOT = 0x02
NVME_DST_FAILED = (5, 6, 7)  # self-test: fatal error, failed segment unknown, failed segments


def num(x, default=None):
    try:
        return int(x)
    except (TypeError, ValueError):
        return default


def ata_table(data):
    return {num(a.get("id")): a for a in (data.get("ata_smart_attributes") or {}).get("table") or []
            if isinstance(a, dict)}


def ata_worn(data, attrs):
    for page in (data.get("ata_device_statistics") or {}).get("pages") or []:
        for row in page.get("table") or []:
            if row.get("name") == "Percentage Used Endurance Indicator" and num(row.get("value")) is not None:
                return min(num(row.get("value")), 100)
    for i in LIFE_ATTRS:
        value = num((attrs.get(i) or {}).get("value"))
        if value is not None and 0 <= value <= 100:
            return 100 - value
    return None


def selftest_failed(data):
    rows = ((data.get("ata_smart_self_test_log") or {}).get("standard") or {}).get("table") or []
    if rows and (rows[0].get("status") or {}).get("passed") is False:
        return True
    rows = (data.get("nvme_self_test_log") or {}).get("table") or []
    return bool(rows) and num((rows[0].get("self_test_result") or {}).get("value")) in NVME_DST_FAILED


def facts(d, data):
    """{kind, name, worn, hours, temp, bad, failing, hot, spare_low, attr_failed, attr_past, selftest}."""
    f = {"name": (data.get("model_name") or d["model"] or "Drive").strip()[:60], "worn": None, "bad": 0,
         "hours": num((data.get("power_on_time") or {}).get("hours")),
         "temp": num((data.get("temperature") or {}).get("current")),
         "failing": (data.get("smart_status") or {}).get("passed") is False or bool(
             num((data.get("smartctl") or {}).get("exit_status"), 0) & 8),
         "hot": False, "spare_low": False, "attr_failed": "", "attr_past": "", "selftest": selftest_failed(data)}
    nv = data.get("nvme_smart_health_information_log")
    if isinstance(nv, dict):
        f["kind"] = "NVMe SSD"
        warn = num(nv.get("critical_warning"), 0)
        f["failing"] = f["failing"] or bool(warn & NVME_FAILING)
        f["hot"] = bool(warn & NVME_HOT)
        f["worn"] = num(nv.get("percentage_used"))
        f["bad"] = num(nv.get("media_errors"), 0)
        spare, low = num(nv.get("available_spare")), num(nv.get("available_spare_threshold"), 10)
        f["spare_low"] = spare is not None and spare <= low + 10
        f["hours"] = f["hours"] if f["hours"] is not None else num(nv.get("power_on_hours"))
        f["temp"] = f["temp"] if f["temp"] is not None else num(nv.get("temperature"))
    else:
        rpm = num(data.get("rotation_rate"))
        f["kind"] = "hard drive" if (rpm or 0) > 0 or (rpm is None and d["rotating"]) else "SSD"
        attrs = ata_table(data)
        f["bad"] = sum(num(((attrs.get(i) or {}).get("raw") or {}).get("value"), 0) for i in BAD_ATTRS)
        f["worn"] = ata_worn(data, attrs) if f["kind"] == "SSD" else None
        for a in attrs.values():
            when = (a.get("when_failed") or "").strip()
            name = str(a.get("name") or a.get("id")).replace("_", " ")
            if when in ("now", "FAILING_NOW"):
                f["attr_failed"] = f["attr_failed"] or name
            elif when in ("past", "In_the_past"):
                f["attr_past"] = f["attr_past"] or name
    f["failing"] = f["failing"] or bool(f["attr_failed"])
    if f["worn"] is not None:
        f["worn"] = max(0, min(f["worn"], 100))
    return f

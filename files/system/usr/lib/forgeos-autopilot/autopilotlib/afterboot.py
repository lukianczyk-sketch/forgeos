"""After-restart check: did the new system version (new drivers) break anything?

Every check remembers the last version where everything worked ("last good"). After an update, any
important part that had a driver then and has none now is a problem, and Autopilot offers to go back
to the version before (Undo Button's rpm-ostree rollback; your files are not touched).
"""
import time

from . import log, run, save_state, state
from . import devices, drivers, gpu

WORDS = devices.WORDS


def current():
    booted, pending = drivers.deployments()
    return {"checksum": str((booted or {}).get("checksum") or "unknown"), "image": drivers.image(booted),
            "devices": devices.scan(), "packages": drivers.installed(),
            "pending": str((pending or {}).get("checksum") or "")}


def problems(good, now):
    """Plain problems: [{'key', 'text'}] - parts that stopped working, and an NVIDIA driver that did not load."""
    found = [{"key": it["key"], "text": "%s stopped working (%s)." % (WORDS.get(it["kind"], it["kind"]), it["name"])}
             for it in devices.lost(good.get("devices") or [], now["devices"])]
    nv = gpu.nvidia_problem(now["devices"], now["image"])
    if nv == "not-loaded" and not any(p["text"].startswith("Graphics") for p in found):
        found.append({"key": "nvidia", "text": "The NVIDIA graphics driver did not start."})
    return found


def remember_good(st, now):
    st["last_good"] = {"checksum": now["checksum"], "devices": now["devices"], "packages": now["packages"],
                       "image": now["image"], "date": time.strftime("%Y-%m-%d %H:%M")}
    st.pop("problem", None)


def check():
    """{'state': 'first'|'same'|'works'|'problem', 'problems': [...], 'changes': [...], 'now': {...}}."""
    st = state()
    now = current()
    good = st.get("last_good") or {}
    result = {"state": "same", "problems": [], "changes": [], "now": now}
    if not good:
        remember_good(st, now)
        result["state"] = "first"
    elif good.get("checksum") == now["checksum"] or st.get("accepted") == now["checksum"]:
        if good.get("checksum") != now["checksum"]:
            result["changes"] = drivers.compare(good.get("packages") or {}, now["packages"])
        remember_good(st, now)
    else:
        found = problems(good, now)
        result["changes"] = drivers.compare(good.get("packages") or {}, now["packages"])
        if found:
            result.update(state="problem", problems=found)
            if (st.get("problem") or {}).get("checksum") != now["checksum"]:
                log("problem", "After the update: " + " ".join(p["text"] for p in found))
            st["problem"] = {"checksum": now["checksum"], "items": found}
        else:
            result["state"] = "works"
            text = drivers.describe(result["changes"]) or "no driver changes"
            log("works", "New system version works (%s)." % text)
            st["last_change"] = {"date": time.strftime("%Y-%m-%d"), "text": text}
            remember_good(st, now)
    save_state(st)
    return result


def keep_version():
    """The user chose to keep this version even though something stopped working."""
    st = state()
    now = current()
    st["accepted"] = now["checksum"]
    remember_good(st, now)
    save_state(st)
    log("kept", "Kept the new version (chosen by you).")
    return True


def go_back():
    """Go back to the version before the update (Undo Button). Takes effect at the next restart."""
    code, _out = run(["forgeos-undo", "undo-update"], 600)
    log("go-back", "Going back to the version before the update: %s." % ("done - restart to finish" if code == 0 else "FAILED"))
    return code == 0

"""Driver updates: they come inside ForgeOS's system updates (Bazzite's uupd installs them every night).

Reads rpm-ostree to see the running version and one waiting for a restart, and says in plain words
which drivers changed. Also checks that the nightly updater is switched on and working.
"""
import re

from . import run, run_json

# (pattern for the package name, plain name) - the first match wins
KINDS = [(r"^kernel(-core)?$", "Core drivers (Linux kernel)"),
         (r"^mesa-dri-drivers$", "Graphics driver (AMD/Intel)"),
         (r"^(nvidia-driver|kmod-nvidia.*|nvidia-kmod-common)$", "Graphics driver (NVIDIA)"),
         (r"^linux-firmware$", "Device firmware files"),
         (r"^(microcode_ctl|amd-ucode-firmware)$", "Processor security fixes"),
         (r"^(NetworkManager|iwd|wpa_supplicant)$", "Wi-Fi and network"),
         (r"^(pipewire|wireplumber)$", "Sound"),
         (r"^bluez$", "Bluetooth")]
UPDATER = "uupd.timer"


def kind(name):
    for pattern, plain in KINDS:
        if re.match(pattern, name):
            return plain
    return ""


def short(evr):
    """'0:590.12-1.fc44' -> '590.12' (epoch and release dropped)."""
    evr = str(evr).split(":")[-1]
    return evr.split("-")[0] or evr


def deployments():
    """(booted, pending): pending is a newer version waiting for a restart (or None)."""
    code, data = run_json(["rpm-ostree", "status", "--json"], 60)
    deps = data.get("deployments") if code == 0 and isinstance(data, dict) else None
    if not isinstance(deps, list) or not deps:
        return None, None
    booted = next((d for d in deps if d.get("booted")), None)
    pending = next((d for d in deps if d.get("staged")), None)
    if pending is None and deps[0] is not booted and booted is not None:
        if deps.index(booted) > 0 and (deps[0].get("timestamp") or 0) >= (booted.get("timestamp") or 0):
            pending = deps[0]
    return booted, pending


def image(dep):
    return str((dep or {}).get("container-image-reference") or "")


def changes(old, new):
    """(driver changes [(plain name, old, new)] or None, number of security fixes) from 'rpm-ostree db diff'."""
    code, data = run_json(["rpm-ostree", "db", "diff", "--format=json", old, new], 120)
    rows = data.get("pkgdiff") if code == 0 and isinstance(data, dict) else None
    if not isinstance(rows, list):
        return None, 0
    adv = data.get("advisories")
    found, seen = [], set()
    for row in rows:
        if not isinstance(row, list) or len(row) < 3 or not isinstance(row[2], dict):
            continue
        plain = kind(str(row[0]))
        if not plain or plain in seen:
            continue
        was, now = row[2].get("PreviousPackage"), row[2].get("NewPackage")
        was = short(was[1]) if isinstance(was, list) and len(was) > 1 else "-"
        now = short(now[1]) if isinstance(now, list) and len(now) > 1 else "-"
        if was != now:
            seen.add(plain)
            found.append((plain, was, now))
    return found, len(adv) if isinstance(adv, list) else 0


def installed():
    """{plain name: version} for the drivers in the running system (from rpm)."""
    code, out = run(["rpm", "-qa", "--qf", "%{NAME}\\t%{VERSION}-%{RELEASE}\\n"], 60)
    found = {}
    for line in out.splitlines() if code == 0 else []:
        name, _, evr = line.partition("\t")
        plain = kind(name)
        if plain and plain not in found:
            found[plain] = short(evr)
    return found


def compare(before, after):
    """[(plain name, old, new)] between two {plain name: version} lists."""
    return [(k, before.get(k, "-"), after[k]) for k in sorted(after) if before.get(k, "-") != after[k]]


def describe(rows, fix_count=0):
    """'Graphics driver (NVIDIA) 580.95 to 590.12, Sound 1.4.1 to 1.4.2, 3 security fixes'."""
    parts = ["%s %s (new)" % (n, b) if a == "-" else ("%s removed" % n if b == "-" else "%s %s to %s" % (n, a, b))
             for n, a, b in rows]
    if fix_count:
        parts.append("%d security fix%s" % (fix_count, "es" if fix_count > 1 else ""))
    return ", ".join(parts)


def updater():
    """'ok', 'off' (switched off) or 'failing' (the last nightly update failed)."""
    code, out = run(["systemctl", "is-enabled", UPDATER], 10)
    if out.strip() not in ("enabled", "static", "alias", "indirect", "enabled-runtime"):
        return "off"
    code, out = run(["systemctl", "show", "uupd.service", "-p", "Result", "--value"], 10)
    return "failing" if code == 0 and out.strip() not in ("", "success") else "ok"


def fix_updater():
    """Switch the nightly updater back on (asks for the PC password)."""
    return run(["systemctl", "enable", "--now", UPDATER], 120)[0] == 0

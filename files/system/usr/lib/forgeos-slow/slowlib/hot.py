"""Checks 5-6: heat and the power mode (and how long the PC has been on, for the restart check)."""
import glob
import os

from . import PROC, SYS, read, run
from .checks import ok, problem


def temperature():
    """The hottest processor sensor in degrees C, or None."""
    best = None
    for d in glob.glob(os.path.join(SYS, "class", "hwmon", "hwmon*")):
        if read(os.path.join(d, "name")).strip() not in ("coretemp", "k10temp", "zenpower", "cpu_thermal", "acpitz"):
            continue
        files = glob.glob(os.path.join(d, "temp*_input"))
        labels = {f: read(f.replace("_input", "_label")).strip() for f in files}
        if len(files) > 1:  # Tctl (AMD) reads up to 20 degrees too high on purpose: use the real ones
            files = [f for f in files if labels[f] != "Tctl"] or files
        for f in files:
            try:
                t = int(read(f).strip()) / 1000.0
            except ValueError:
                continue
            best = t if best is None or t > best else best
    return best


def slowed_down():
    """True when the processor runs well below its top speed."""
    cur = top = 0
    for d in glob.glob(os.path.join(SYS, "devices", "system", "cpu", "cpu[0-9]*", "cpufreq")):
        try:
            cur += int(read(os.path.join(d, "scaling_cur_freq")))
            top += int(read(os.path.join(d, "cpuinfo_max_freq")))
        except ValueError:
            pass
    return top > 0 and cur < top * 0.7


def heat():
    t = temperature()
    if t is None:
        return []
    if t < 90:
        return [ok("heat", "Temperature: %d degrees C (fine)." % t)]
    text = "Your PC is hot (%d degrees C)" % t
    text += " and slowed itself down to cool off." if slowed_down() else "."
    return [problem("heat", "red" if t >= 95 else "yellow", text + " Check the vents for dust and keep it on a hard,"
                    " flat surface (not a bed or a lap). No button can fix heat.")]


def on_battery():
    for d in glob.glob(os.path.join(SYS, "class", "power_supply", "*")):
        if read(os.path.join(d, "type")).strip() == "Mains":
            return read(os.path.join(d, "online")).strip() == "0"
    return False


def power():
    code, out = run(["powerprofilesctl", "get"], 10)
    mode = out.strip()
    if code != 0 or not mode:
        return []
    if mode != "power-saver":
        return [ok("power", "Power mode: %s." % mode.replace("-", " "))]
    why = " It is running on battery." if on_battery() else ""
    return [problem("power", "yellow", "Power saver mode is on, which slows the PC down to save power." + why,
                    "power balanced", "Switch to Balanced")]


def uptime_days():
    try:
        return float(read(os.path.join(PROC, "uptime")).split()[0]) / 86400
    except (IndexError, ValueError):
        return 0.0

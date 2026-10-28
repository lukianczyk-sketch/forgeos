"""Big text for Family Mode: KDE fonts, the mouse pointer and the taskbar height.

Fonts: kdeglobals keys, written with kwriteconfig6 --notify (GTK apps follow), then the refreshFonts
signal the KDE fonts settings page sends itself (Qt apps follow). Pointer: kcminputrc cursorSize, then
KGlobalSettings notifyChange 5 (= CursorChanged; KWin reloads the pointer on it). No logout needed.
"""
import re

from . import SIZES, run

# (group, key, Plasma's own default size) - plasma-workspace kcms/fonts/fontssettings.kcfg
FONTS = [("General", "font", 10), ("General", "menuFont", 10), ("General", "toolBarFont", 10),
         ("General", "smallestReadableFont", 8), ("WM", "activeFont", 10)]
DEFAULT_FONT = "Noto Sans,%d,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
DEFAULT_CURSOR = 24


def read(file, group, key):
    code, out = run(["kreadconfig6", "--file", file, "--group", group, "--key", key])
    return out.strip() if code == 0 else ""


def write(file, group, key, value):
    """value None = delete the key (back to Plasma's own default)."""
    cmd = ["kwriteconfig6", "--file", file, "--group", group, "--key", key, "--notify"]
    cmd += ["--delete"] if value is None else [value]
    return run(cmd)[0] == 0


def signal(path_member, *args):
    path, member = path_member
    return run(["dbus-send", "--session", "--type=signal", path, member] + list(args))[0] == 0


def bigger_font(value, default, factor):
    """Same font, only the size changed. value '' = Plasma's default font."""
    parts = value.split(",") if value else []
    if len(parts) < 3:
        return DEFAULT_FONT % round(default * factor)
    try:
        points = float(parts[1])
    except ValueError:
        points = -1
    if points > 0:
        parts[1] = str(round(points * factor))
    elif parts[2].strip().lstrip("-").isdigit() and int(parts[2]) > 0:
        parts[2] = str(round(int(parts[2]) * factor))  # a size in pixels instead of points
    else:
        parts[1] = str(round(default * factor))
    return ",".join(parts)


def panel_script(script):
    code, out = run(["dbus-send", "--session", "--print-reply", "--dest=org.kde.plasmashell",
                     "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", "string:" + script])
    if code != 0:
        return None
    m = re.search(r'string "([^"]*)"', out)
    return m.group(1) if m else ""


def panels_now():
    """{panel id: height} of every taskbar/panel, or None when Plasma can't be asked."""
    out = panel_script("print(panels().map(function (p) { return p.id + ':' + p.height; }).join(','))")
    if out is None:
        return None
    found = {}
    for part in out.split(","):
        pid, _, height = part.strip().partition(":")
        if pid.isdigit() and height.isdigit():
            found[pid] = int(height)
    return found


def set_panels(heights):
    if not heights:
        return True
    script = " ".join("panelById(%d).height = %d;" % (int(p), h) for p, h in sorted(heights.items()))
    return panel_script(script) is not None


def capture():
    """Everything big text changes, as it is now (saved before the first change)."""
    return {"fonts": {g + "/" + k: read("kdeglobals", g, k) for g, k, _ in FONTS},
            "cursor": read("kcminputrc", "Mouse", "cursorSize"),
            "panels": panels_now()}


def apply(saved, size):
    """Make it big, always counted from the saved originals (Big -> Bigger never piles up)."""
    factor, cursor, panel = SIZES[size]
    problems = []
    fonts = saved.get("fonts", {})
    ok = all(write("kdeglobals", g, k, bigger_font(fonts.get(g + "/" + k, ""), d, factor))
             for g, k, d in FONTS)
    if not ok or not signal(("/KDEPlatformTheme", "org.kde.KDEPlatformTheme.refreshFonts")):
        problems.append("The bigger words could not be set everywhere.")
    old = saved.get("cursor") or ""
    size_now = max(cursor, int(old) if old.isdigit() else DEFAULT_CURSOR)
    if not (write("kcminputrc", "Mouse", "cursorSize", str(size_now)) and cursor_changed()):
        problems.append("The bigger mouse pointer could not be set.")
    panels = saved.get("panels")
    if panels is None:
        problems.append("The taskbar could not be made taller (Plasma did not answer).")
    elif not set_panels({p: max(h, panel) for p, h in panels.items()}):
        problems.append("The taskbar could not be made taller.")
    return problems


def cursor_changed():
    return signal(("/KGlobalSettings", "org.kde.KGlobalSettings.notifyChange"), "int32:5", "int32:0")


def restore(saved):
    """Put the words, the pointer and the taskbar back exactly as they were."""
    problems = []
    fonts = saved.get("fonts", {})
    ok = all(write("kdeglobals", g, k, fonts.get(g + "/" + k) or None) for g, k, _ in FONTS)
    if not ok or not signal(("/KDEPlatformTheme", "org.kde.KDEPlatformTheme.refreshFonts")):
        problems.append("The words could not be set back to their old size everywhere.")
    if not (write("kcminputrc", "Mouse", "cursorSize", saved.get("cursor") or None) and cursor_changed()):
        problems.append("The mouse pointer could not be set back to its old size.")
    if saved.get("panels") and not set_panels(saved["panels"]):
        problems.append("The taskbar could not be set back to its old height.")
    return problems

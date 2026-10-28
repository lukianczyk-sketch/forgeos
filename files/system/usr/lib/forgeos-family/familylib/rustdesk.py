"""RustDesk for "Call for help": only the helper gets in, and only after you click Accept.

Flathub RustDesk's --option needs an installed copy + root, so the options go into RustDesk2.toml
[options] while RustDesk is NOT running. Keys checked in rustdesk 1.5.0 (config/keys.rs).
"""
import os
import re
import subprocess

try:
    import tomllib  # Python 3.11+ (ForgeOS has 3.14)
except ImportError:  # older Python (test PCs): the simple reader below
    tomllib = None

from . import RUSTDESK, RUSTDESK_DIR, run

TOML = os.path.join(RUSTDESK_DIR, "RustDesk2.toml")
LOCK = {
    "approve-mode": "click",                           # no password: you must click Accept
    "verification-method": "use-temporary-password",   # no permanent password back door
    "enable-file-transfer": "N", "enable-terminal": "N", "enable-tunnel": "N",
    "enable-remote-printer": "N", "enable-camera": "N",
    "allow-remote-config-modification": "N", "enable-lan-discovery": "N", "direct-server": "N",
    "allow-auto-disconnect": "Y", "auto-disconnect-timeout": "30",
}
KEYS = list(LOCK) + ["id-whitelist"]


def wanted(helper_id):
    """The locked-down options; with a helper ID only that ID may even ask to connect."""
    opts = dict(LOCK)
    opts["id-whitelist"] = helper_id or ""
    return opts


def read_text():
    try:
        with open(TOML) as f:
            return f.read()
    except OSError:
        return None


def options(text):
    """The [options] table as {key: value}; None = the file is broken."""
    if tomllib:
        try:
            return {k: str(v) for k, v in tomllib.loads(text or "").get("options", {}).items()}
        except (ValueError, AttributeError):
            return None
    found, inside = {}, False
    for line in (text or "").splitlines():
        line = line.strip()
        if line.startswith("["):
            if not re.fullmatch(r"\[\[?[\w.-]+\]\]?", line):
                return None
            inside = line == "[options]"
        elif inside and line and not line.startswith("#"):
            m = re.match(r"""^["']?([\w.-]+)["']?\s*=\s*(?:'([^']*)'|"((?:[^"\\]|\\.)*)")\s*$""", line)
            if not m:
                return None
            found[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3).replace('\\"', '"')
    return found


def quote(value):
    if "'" not in value and "\n" not in value:
        return "'%s'" % value
    return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def rewrite(text, values):
    """values: {key: new value, or None = take the key out}. Other lines are left as they are."""
    lines = (text or "").splitlines()
    head = next((i for i, l in enumerate(lines) if l.strip() == "[options]"), None)
    if head is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append("[options]")
        head = len(lines) - 1
    end = next((i for i in range(head + 1, len(lines)) if lines[i].lstrip().startswith("[")), len(lines))
    names = "|".join(re.escape(k) for k in values)
    pattern = re.compile(r'^\s*(%s|"(%s)"|\'(%s)\')\s*=' % (names, names, names))
    body = [l for l in lines[head + 1:end] if not pattern.match(l)]
    new = ["%s = %s" % (k, quote(v)) for k, v in values.items() if v is not None]
    return "\n".join(lines[:head + 1] + new + body + lines[end:]) + "\n"


def save_file(text):
    if options(text) is None:
        return False  # never write a file RustDesk could not read
    os.makedirs(RUSTDESK_DIR, exist_ok=True)
    tmp = TOML + ".forgeos-new"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, TOML)
    return True


def running():
    code, out = run(["flatpak", "ps", "--columns=application"])
    return code == 0 and RUSTDESK in out.split()


def stop():
    run(["flatpak", "kill", RUSTDESK])
    return not running()


def lock(saved, helper_id):
    """Write the safe options; the old ones go into saved["rustdesk"] the first time only."""
    if running() and not stop():
        return False
    text = read_text()
    now = options(text)
    if now is None:
        return False
    if "rustdesk" not in saved:
        saved["rustdesk"] = {k: now.get(k) for k in KEYS}
        saved["rustdesk_file"] = text is not None
    return save_file(rewrite(text, wanted(helper_id)))


def unlock(saved):
    old = saved.get("rustdesk")
    if old is None:
        return True
    if running() and not stop():
        return False
    text = read_text()
    if text is None:
        return True
    text = rewrite(text, {k: old.get(k) for k in KEYS})
    if text.strip() == "[options]" and not saved.get("rustdesk_file", True):
        os.remove(TOML)  # there was no settings file before Family Mode
        return True
    return save_file(text)


def start():
    """Open RustDesk in the background (it keeps running after this program ends)."""
    try:
        subprocess.Popen(["flatpak", "run", RUSTDESK], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def get_id():
    """This PC's RustDesk ID as '123 456 789', or '' while RustDesk has none yet."""
    code, out = run(["flatpak", "run", "--command=rustdesk", RUSTDESK, "--get-id"], timeout=15)
    found = re.findall(r"^\s*(\d[\d ]{4,14}\d)\s*$", out, re.M) if code == 0 else []
    digits = found[-1].replace(" ", "") if found else ""
    if not 6 <= len(digits) <= 12:
        return ""
    return " ".join(digits[i:i + 3] for i in range(0, len(digits), 3))

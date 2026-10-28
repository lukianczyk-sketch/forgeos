"""Virus check with ClamAV: the always-ready checker (clamd) when this PC runs it, else clamscan.

Files are streamed to clamd (--stream), so the checker never opens your files itself.
"""
import os
import re
import time

from . import BIGGEST, CLAMD_CONF, ENV, run

SCAN_TIME = int(ENV("FORGEOS_GUARD_SCAN_TIME") or 600)


def socket_path():
    """The always-ready checker's socket from its settings file, or '' if it is not running."""
    try:
        with open(CLAMD_CONF) as f:
            for line in f:
                part = line.split()
                if len(part) == 2 and part[0] == "LocalSocket":
                    return part[1] if os.path.exists(part[1]) else ""
    except OSError:
        pass
    return ""


def fast():
    return bool(socket_path())


def found_lines(out):
    """'PATH: NAME FOUND' lines -> {PATH: NAME}. The virus name has no spaces, so split at the last ': '."""
    hits = {}
    for line in out.splitlines():
        if line.endswith(" FOUND") and ": " in line:
            where, _, name = line[:-6].rpartition(": ")
            hits[where] = name
    return hits


def clamscan_cmd():
    cmd = ["clamscan", "--no-summary", "--infected", "--max-filesize=400M", "--max-scansize=1000M"]
    if ENV("FORGEOS_GUARD_CLAMSCAN_DB"):
        cmd.append("--database=" + ENV("FORGEOS_GUARD_CLAMSCAN_DB"))
    return cmd


def scan_files(paths):
    """{path: virus name, or '' if clean, or None if it could not be checked}."""
    result = {p: None for p in paths}
    todo = []
    for p in paths:
        try:
            if os.path.getsize(p) > BIGGEST:
                continue  # too big: stays None
        except OSError:
            continue
        todo.append(p)
    if not todo:
        return result
    if fast():
        left = []
        for p in todo:  # one at a time: a strange name can't confuse the answer
            code, out = run(["clamdscan", "--config-file=" + CLAMD_CONF, "--stream", "--no-summary", p], SCAN_TIME)
            if code in (0, 1):
                result[p] = (found_lines(out).get(p, "Unknown.Virus") if code == 1 else "")
            else:
                left.append(p)  # the checker is busy or stopped: use clamscan for these
        todo = left
    if todo:
        code, out = run(clamscan_cmd() + ["--"] + todo, SCAN_TIME)
        if code in (0, 1):
            hits = found_lines(out)
            for p in todo:
                result[p] = hits.get(p, "")
    return result


def scan_bytes(data):
    """Virus name, '' if clean, None if it could not be checked (for email attachments, never saved to disk)."""
    if len(data) > BIGGEST:
        return None
    if fast():
        code, out = run(["clamdscan", "--config-file=" + CLAMD_CONF, "--stream", "--no-summary", "-"], SCAN_TIME, data)
        if code in (0, 1):
            return (found_lines(out).get("stream", "Unknown.Virus") if code == 1 else "")
    code, out = run(clamscan_cmd() + ["-"], SCAN_TIME, data)
    if code in (0, 1):
        return (found_lines(out).get("stdin", "Unknown.Virus") if code == 1 else "")
    return None


def db_date():
    """When the virus list was last updated (newest file in ClamAV's folder), or ''."""
    folder = ENV("FORGEOS_GUARD_CLAMSCAN_DB") or "/var/lib/clamav"
    newest = 0
    try:
        for name in os.listdir(folder):
            if re.search(r"\.(cvd|cld|ndb|hdb)$", name):
                newest = max(newest, os.path.getmtime(os.path.join(folder, name)))
    except OSError:
        return ""
    if not newest:
        return ""
    return time.strftime("%Y-%m-%d", time.localtime(newest))

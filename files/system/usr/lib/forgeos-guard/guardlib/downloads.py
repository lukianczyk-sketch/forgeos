"""Download Guard: virus-check every new file in Downloads and on the Desktop.

A file with a virus is locked away (quarantine); a Windows program or a fake double ending gets a warning.
"""
import os

from . import ENV, HOME, QUAR_DIR, log_event, risky_name, run
from . import alerts, quarantine, scan


def user_dir(kind, fallback):
    code, out = run(["xdg-user-dir", kind], 5)
    path = out.strip() if code == 0 else ""
    return path if path and os.path.realpath(path) != os.path.realpath(HOME) else os.path.join(HOME, fallback)


def download_dirs():
    if ENV("FORGEOS_GUARD_DIRS"):
        return [d for d in ENV("FORGEOS_GUARD_DIRS").split(":") if d]
    return [user_dir("DOWNLOAD", "Downloads"), user_dir("DESKTOP", "Desktop")]


def handle_downloads(paths):
    """Virus-check new files; lock away a virus; warn about risky programs."""
    paths = [p for p in paths if os.path.isfile(p) and not p.startswith(QUAR_DIR + os.sep)]
    for path, virus in scan.scan_files(paths).items():
        name = os.path.basename(path)
        if virus:
            qid = quarantine.lock_away(path, virus)
            log_event("virus", "download", path, virus, qid or "could not lock it away")
            alerts.virus("download", name, virus)
        elif virus is None:
            log_event("unchecked", "download", path, "too big or the virus checker could not run")
        else:
            why = risky_name(name)
            if why:
                alerts.risky(name, why, log_event("risky", "download", path, why))

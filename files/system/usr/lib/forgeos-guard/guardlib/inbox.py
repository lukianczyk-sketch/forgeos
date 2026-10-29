"""Find Thunderbird's mail folders and read only the NEW emails in them (read-only).

mbox files: we remember how far we read (bytes) per file. Maildir: one file per email.
Each email is checked once: we remember a short fingerprint of the last 3000 emails.
"""
import glob
import hashlib
import json
import os
import re

from . import ENV, HOME, MAIL_STATE, private_dir, STATE_DIR

NOT_MBOX = re.compile(r"\.(msf|dat|json|sqlite|sqlite-wal|sqlite-shm|html?|txt|log|lz4|mozlz4|bak|tmp)$", re.I)
CATCH_UP = 5 * 1024 * 1024  # after Thunderbird tidies (compacts) a file, look again at its last 5 MB
SEEN_MAX = 3000


def roots():
    """Every Thunderbird mail folder: <profile>/Mail and <profile>/ImapMail (Flatpak and normal)."""
    bases = (ENV("FORGEOS_GUARD_TB") or "").split(":") + [
        os.path.join(HOME, ".var", "app", "org.mozilla.thunderbird", ".thunderbird"), os.path.join(HOME, ".thunderbird")]
    found = []
    for base in bases:
        if base:
            for sub in ("Mail", "ImapMail"):
                found += [p for p in sorted(glob.glob(os.path.join(glob.escape(base), "*", sub))) if os.path.isdir(p)]
    return found


def in_maildir(path):
    return os.path.basename(os.path.dirname(path)) in ("cur", "new")


def is_mbox(path):
    if in_maildir(path) or NOT_MBOX.search(path) or not os.path.isfile(path):
        return False
    try:
        with open(path, "rb") as f:
            start = f.read(5)
    except OSError:
        return False
    return start in (b"From ", b"")


def fingerprint(data):
    m = re.search(rb"(?im)^message-id:\s*(\S+)", data[:65536])
    return hashlib.sha1(m.group(1) if m else data[:4096]).hexdigest()[:16]


class Inbox:
    def __init__(self):
        self.state = {"files": {}, "seen": []}
        try:
            with open(MAIL_STATE) as f:
                data = json.load(f)
            if isinstance(data.get("files"), dict) and isinstance(data.get("seen"), list):
                self.state = data
        except (OSError, ValueError, AttributeError):
            pass
        self.seen = set(self.state["seen"])

    def save(self):
        private_dir(STATE_DIR)
        self.state["seen"] = self.state["seen"][-SEEN_MAX:]
        with open(MAIL_STATE + ".new", "w") as f:
            json.dump(self.state, f)
        os.replace(MAIL_STATE + ".new", MAIL_STATE)

    def first(self, data):
        """True the first time we see this email."""
        key = fingerprint(data)
        if key in self.seen:
            return False
        self.seen.add(key)
        self.state["seen"].append(key)
        if len(self.state["seen"]) > 2 * SEEN_MAX:
            self.state["seen"] = self.state["seen"][-SEEN_MAX:]
            self.seen = set(self.state["seen"])
        return True

    def remember_end(self, path):
        """A mailbox we have not met yet: start at its end (old mail is not checked again)."""
        if path not in self.state["files"] and is_mbox(path):
            st = os.stat(path)
            self.state["files"][path] = [st.st_ino, st.st_size]

    def new_mail(self, path):
        """[email bytes] that arrived in this file since last time."""
        if in_maildir(path):
            try:
                with open(path, "rb") as f:
                    data = f.read()
            except OSError:
                return []
            return [data] if self.first(data) else []
        if not is_mbox(path):
            return []
        st = os.stat(path)
        known = self.state["files"].get(path)
        if known is None:
            self.state["files"][path] = [st.st_ino, st.st_size]
            return []
        ino, done = known
        tidied = ino != st.st_ino or st.st_size < done
        start = max(0, st.st_size - CATCH_UP) if tidied else done
        with open(path, "rb") as f:
            f.seek(start)
            data = f.read(st.st_size - start)
        self.state["files"][path] = [st.st_ino, st.st_size]
        if start and tidied:
            cut = data.find(b"\nFrom ")
            data = data[cut + 1:] if cut >= 0 else b""
        found = []
        for one in re.split(rb"\n(?=From )", data):
            one = re.sub(rb"^From [^\n]*\n", b"", one, count=1)
            if one.strip() and self.first(one):
                found.append(one)
        return found

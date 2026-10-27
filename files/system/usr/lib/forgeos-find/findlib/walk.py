"""ForgeOS Find Anything (Job 11): go through the user's folders and keep the search list up to date."""
import fcntl
import os
import stat
import time

from findlib import extract

MAX_FILES = 50000
# Never searched: snapshots, program code, and game folders (thousands of game files, no papers).
SKIP_NAMES = {".snapshots", "node_modules", "__pycache__", "site-packages", "Games", "SteamLibrary"}


def config_dir():
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "forgeos")


def skip_file():
    return os.path.join(config_dir(), "find-skip.txt")


def roots():
    """Folders to search: the home folder, or FORGEOS_FIND_ROOTS (a ':' list, for tests)."""
    env = os.environ.get("FORGEOS_FIND_ROOTS")
    found = env.split(":") if env else [os.path.expanduser("~")]
    return [os.path.abspath(r) for r in found if r]


def skipped():
    """Folders and files the user asked to leave out (one per line, # = note)."""
    out = set()
    try:
        with open(skip_file(), encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    out.add(os.path.abspath(os.path.expanduser(line)).rstrip("/"))
    except OSError:
        pass
    return out


def files(limit=MAX_FILES):
    """Every normal file to look at: (path, stat). Hidden things and links are never followed."""
    skip = skipped()
    count = 0
    for root in roots():
        if root in skip:
            continue
        for folder, dirs, names in os.walk(root, followlinks=False):
            dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d not in SKIP_NAMES
                             and os.path.join(folder, d) not in skip)
            for name in sorted(names):
                path = os.path.join(folder, name)
                if name.startswith(".") or path in skip:
                    continue
                try:
                    st = os.lstat(path)
                except OSError:
                    continue
                if not stat.S_ISREG(st.st_mode):
                    continue
                yield path, st
                count += 1
                if count >= limit:
                    return


def search_name(path):
    """The file name plus its two folder names, so "Taxes/2023/form.pdf" is found by "tax 2023"."""
    parts = path.split(os.sep)
    return " ".join([parts[-1]] + parts[-3:-1])


def run_index(store, full=False, say=print):
    """Read new and changed files, drop deleted ones. Returns how many files were read."""
    lock = os.fdopen(os.open(store.path + ".lock", os.O_WRONLY | os.O_CREAT, 0o600), "w")  # locked while reading
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        say("The search list is already being updated. Try again in a few minutes.")
        return 0
    if full:
        store.clear()
    known = store.known()
    seen, notes, read = set(), set(), 0
    for path, st in files():
        seen.add(path)
        if known.get(path) == (int(st.st_mtime), st.st_size):
            continue
        kind, text, note = extract.extract(path, st.st_size)
        if note:
            notes.add(note)
        store.put(path, int(st.st_mtime), st.st_size, kind, search_name(path), text)
        read += 1
        if read % 200 == 0:
            store.commit()
            say("Read %d files..." % read)
    gone = [p for p in known if p not in seen]
    for path in gone:
        store.drop(path)
    store.set("last_run", int(time.time()))
    if read or full:  # keep the old notes when no file was read this time
        store.set("notes", "; ".join(sorted(notes)))
    store.commit()
    lock.close()
    say("Search list updated: %d files read, %d removed, %d in the list." % (read, len(gone), store.count()))
    return read

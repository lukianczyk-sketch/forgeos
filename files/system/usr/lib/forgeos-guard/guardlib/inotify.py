"""Linux inotify through ctypes (no extra package): the kernel tells us when a file is written or moved in."""
import ctypes
import ctypes.util
import os
import struct

CLOSE_WRITE, MOVED_TO, CREATE, MODIFY = 0x8, 0x80, 0x100, 0x2
DELETE_SELF, MOVE_SELF, IGNORED, OVERFLOW, ISDIR = 0x400, 0x800, 0x8000, 0x4000, 0x40000000
ONLYDIR, NONBLOCK, CLOEXEC = 0x1000000, 0o4000, 0o2000000
HEAD = struct.Struct("iIII")


class Inotify:
    def __init__(self):
        self.libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
        self.fd = self.libc.inotify_init1(NONBLOCK | CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "inotify is not available")
        self.paths = {}  # watch number -> folder

    def watch(self, folder, mask):
        """Watch one folder. Returns False if it can't be watched (gone, no permission, too many watches)."""
        wd = self.libc.inotify_add_watch(self.fd, os.fsencode(folder), mask | ONLYDIR)
        if wd < 0:
            return False
        self.paths[wd] = folder
        return True

    def watching(self, folder):
        return folder in self.paths.values()

    def read(self):
        """[(folder, name, mask)] for everything that happened since the last read. ('', '', OVERFLOW) = missed some."""
        try:
            data = os.read(self.fd, 65536)
        except BlockingIOError:
            return []
        found, at = [], 0
        while at + HEAD.size <= len(data):
            wd, mask, _cookie, size = HEAD.unpack_from(data, at)
            name = data[at + HEAD.size:at + HEAD.size + size].split(b"\0", 1)[0]
            at += HEAD.size + size
            if mask & OVERFLOW:
                found.append(("", "", OVERFLOW))
                continue
            folder = self.paths.get(wd)
            if mask & IGNORED:
                self.paths.pop(wd, None)
                continue
            if folder is not None:
                found.append((folder, os.fsdecode(name), mask))
        return found

    def close(self):
        os.close(self.fd)

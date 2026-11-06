"""The kernel's file watchers through ctypes (no extra package).

fanotify (root only): which program (pid) finished writing which file, for a whole file system.
The event comes with an open copy of the file, so the first 64 KB are read right away.
inotify: a bait file was deleted or renamed (fanotify without file ids can't see that).
"""
import ctypes
import ctypes.util
import os
import struct

FAN_CLOSE_WRITE, FAN_Q_OVERFLOW = 0x8, 0x4000
FAN_CLASS_NOTIF, FAN_CLOEXEC, FAN_NONBLOCK = 0x0, 0x1, 0x2
FAN_MARK_ADD, FAN_MARK_MOUNT, FAN_MARK_FILESYSTEM, AT_FDCWD = 0x1, 0x10, 0x100, -100
O_LARGEFILE = 0o100000
META = struct.Struct("IBBHQii")
IN_DELETE, IN_MOVED_FROM, IN_Q_OVERFLOW, IN_IGNORED = 0x200, 0x40, 0x4000, 0x8000
IN_ONLYDIR, IN_NONBLOCK, IN_CLOEXEC = 0x1000000, 0o4000, 0o2000000
INHEAD = struct.Struct("iIII")
HEAD = 65536
_LIBC = []


def libc():
    if not _LIBC:
        lib = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
        lib.fanotify_mark.argtypes = [ctypes.c_int, ctypes.c_uint, ctypes.c_uint64, ctypes.c_int, ctypes.c_char_p]
        _LIBC.append(lib)
    return _LIBC[0]


class Fanotify:
    def __init__(self):
        self.fd = libc().fanotify_init(FAN_CLASS_NOTIF | FAN_CLOEXEC | FAN_NONBLOCK,
                                       os.O_RDONLY | O_LARGEFILE | os.O_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "fanotify is not available (root only)")
        self.marked = set()

    def mark(self, path):
        """Watch every file write on the file system that holds `path` (or else its mount). False if it can't."""
        if path in self.marked:
            return True
        for how in (FAN_MARK_FILESYSTEM, FAN_MARK_MOUNT):
            if libc().fanotify_mark(self.fd, FAN_MARK_ADD | how, FAN_CLOSE_WRITE, AT_FDCWD, os.fsencode(path)) == 0:
                self.marked.add(path)
                return True
        return False

    def read(self, want=None):
        """[(pid, path, first 64 KB or None)]; (0, '', None) = the kernel dropped some events.
        want(path) False = not one of ours: skipped without reading it."""
        try:
            data = os.read(self.fd, 4096 * META.size)
        except BlockingIOError:
            return []
        found, at = [], 0
        while at + META.size <= len(data):
            size, _ver, _res, _mlen, mask, fd, pid = META.unpack_from(data, at)
            at += max(size, META.size)
            if mask & FAN_Q_OVERFLOW or fd < 0:
                found.append((0, "", None))
                continue
            try:
                path = os.readlink("/proc/self/fd/%d" % fd)
                head = os.pread(fd, HEAD, 0) if want is None or want(path) else None
            except OSError:
                path, head = "", None
            finally:
                os.close(fd)
            if path and (want is None or head is not None):
                found.append((pid, path, head))
        return found


class Inotify:
    def __init__(self):
        self.fd = libc().inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "inotify is not available")
        self.paths = {}

    def watch(self, folder):
        """Tell us when a file in `folder` is deleted or renamed away."""
        if folder in self.paths.values():
            return True
        wd = libc().inotify_add_watch(self.fd, os.fsencode(folder), IN_DELETE | IN_MOVED_FROM | IN_ONLYDIR)
        if wd >= 0:
            self.paths[wd] = folder
        return wd >= 0

    def read(self):
        """[path] of files that were deleted or renamed away; '' = missed some."""
        try:
            data = os.read(self.fd, 65536)
        except BlockingIOError:
            return []
        found, at = [], 0
        while at + INHEAD.size <= len(data):
            wd, mask, _cookie, size = INHEAD.unpack_from(data, at)
            name = data[at + INHEAD.size:at + INHEAD.size + size].split(b"\0", 1)[0]
            at += INHEAD.size + size
            if mask & IN_Q_OVERFLOW:
                found.append("")
            elif mask & IN_IGNORED:
                self.paths.pop(wd, None)
            elif wd in self.paths:
                found.append(os.path.join(self.paths[wd], os.fsdecode(name)))
        return found

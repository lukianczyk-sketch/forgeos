"""The file system's own error counts (btrfs, the ForgeOS home folder): read, write and damaged-data
errors per drive, and data the monthly scrub could not repair. LUKS (encrypted) layers are followed down
to the real drive.
"""
import re

from . import FILESYSTEMS, run, run_json

STAT = re.compile(r"^\[(/dev/[^\]]+)\]\.(\w+)\s+(\d+)\s*$")
COUNTED = ("read_io_errs", "write_io_errs", "flush_io_errs", "corruption_errs")


def disk_of(part):
    """The whole drive under a partition or an encrypted layer (lsblk walks down the tree)."""
    code, data = run_json(["lsblk", "-J", "-p", "-s", "-o", "PATH,TYPE", part], 30)

    def walk(nodes):
        for n in nodes or []:
            if n.get("type") == "disk":
                return n.get("path")
            hit = walk(n.get("children"))
            if hit:
                return hit
        return None
    return walk((data or {}).get("blockdevices")) if code == 0 else None


def errors():
    """{drive: {"errors": N, "unfixed": N}} for every drive under the checked btrfs file systems."""
    found = {}
    for fs in FILESYSTEMS:
        code, out = run(["btrfs", "device", "stats", fs], 30)
        parts = {}
        for line in out.splitlines() if code in (0, 64) else []:
            m = STAT.match(line.strip())
            if m and m.group(2) in COUNTED:
                parts[m.group(1)] = parts.get(m.group(1), 0) + int(m.group(3))
        unfixed = 0
        code, out = run(["btrfs", "scrub", "status", "-R", fs], 30)
        for line in out.splitlines() if code == 0 else []:
            k, _, v = line.strip().partition(":")
            if k.strip() == "uncorrectable_errs" and v.strip().isdigit():
                unfixed += int(v.strip())
        for part, count in parts.items():
            disk = disk_of(part) or part
            row = found.setdefault(disk, {"errors": 0, "unfixed": 0})
            row["errors"] += count
            row["unfixed"] = max(row["unfixed"], unfixed)
    return found

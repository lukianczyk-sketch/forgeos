"""Runs 'forgeos-helper watch-tick' for the tests (Job 13c) with a pretend drive and clock.

Usage: python3 tests/helper-watch-run.py WORK-DIR [COMMAND...]   (default command: watch-tick)
WORK-DIR/disk-used = how full the drive is, in percent (else 50). WORK-DIR/now-plus = seconds to add
to the clock (to test "once a day" and "3 days" without waiting).
"""
import os
import sys
import time

W = sys.argv[1]
sys.path.insert(0, os.environ["FORGEOS_HELPER_LIB"])


def read(name, default):
    try:
        with open(os.path.join(W, name), encoding="utf-8") as f:
            return f.read().strip() or default
    except OSError:
        return default


class Disk:
    f_blocks = 1000

    def __init__(self, used):
        self.f_bavail = 1000 - int(used * 10)


used = float(read("disk-used", "50"))
os.statvfs = lambda path: Disk(used)
shift = float(read("now-plus", "0"))
real_time = time.time
time.time = lambda: real_time() + shift
from helperlib import cli  # noqa: E402

sys.exit(cli.main(sys.argv[2:] or ["watch-tick"]))

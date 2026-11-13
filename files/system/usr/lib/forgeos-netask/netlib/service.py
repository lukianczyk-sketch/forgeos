"""forgeos-netask.service (root): the OpenSnitch socket, the request socket, and the after-game list."""
import glob
import os
import re
import signal
import sys
import threading

from . import TEST, VAR
from . import later, requests, server


def main():
    if os.geteuid() != 0 and not TEST:
        print("forgeos-netask-service must run as root (it is a system service).", file=sys.stderr)
        return 2
    os.makedirs(VAR, mode=0o700, exist_ok=True)
    signal.signal(signal.SIGTERM, lambda *_: server.STOP.set())
    signal.signal(signal.SIGINT, lambda *_: server.STOP.set())
    ui = server.serve()
    req = requests.serve()
    print("forgeos-netask: ready", flush=True)
    lists = None
    while not server.STOP.wait(60 if not TEST else 1):
        if lists is None or not lists.is_alive():   # the after-game lists run beside, so stopping is never slow
            lists = threading.Thread(target=after_games, daemon=True)
            lists.start()
    ui.stop(2)
    req.shutdown()
    return 0


def after_games():
    for f in glob.glob(os.path.join(VAR, "apps-*.json")):
        m = re.search(r"apps-([0-9]+)\.json$", f)
        if m:
            try:
                later.after_games(int(m.group(1)))
            except Exception as e:  # noqa: BLE001 - one person's list never stops the service
                print("forgeos-netask: after-game list: %s" % e, file=sys.stderr)

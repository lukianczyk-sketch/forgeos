"""Requests from the "Who Uses the Internet" window, Forge Helper and the forgeos-netask command.

They come over a local socket. The service knows who asks from the socket itself (a user id no program can
fake) and shows only that person's apps. Anything that lets MORE through (Allow, Lock down off, turning it
off) is confirmed by a question the service itself puts on the screen, so no program can allow itself.
"""
import json
import os
import socket
import socketserver
import struct
import threading

from . import REQ_SOCK, TEST, clean, day, now, run
from . import history, later, store

def peer_uid(sock):
    if TEST:
        return os.getuid()
    creds = sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    return struct.unpack("3i", creds)[1]


def engine_on():
    return run(["systemctl", "is-active", "opensnitch.service"], 20)[1].strip() == "active"


def entry_who(uid, key):
    e = store.apps(uid).get(key)
    return later.who_of(uid, key, e) if e else None


def answer(uid, req):
    do = req.get("do")
    if do == "status":
        return {"ok": True, "on": engine_on(), "lockdown": store.settings()["lockdown"]}
    if do == "list":
        apps = [{"key": k, "name": e.get("name", "?"), "answer": e.get("answer", "ask"), "kind": e.get("kind", "app"),
                 "red": e.get("red", ""), "later": bool(e.get("later"))} for k, e in store.apps(uid).items()]
        return {"ok": True, "apps": sorted(apps, key=lambda a: a["name"].lower())}
    if do == "today":
        lg = history.log(uid)
        return {"ok": True, "today": lg.get("days", {}).get(day(), {})}
    if do == "blocked":
        minutes = min(max(int(req.get("minutes", 60)), 1), 43200)
        rows = [{"when": b[0], "key": b[1], "name": b[2], "host": b[3], "why": b[4]}
                for b in history.log(uid).get("blocked", []) if b[0] >= now() - minutes * 60]
        return {"ok": True, "blocked": rows[::-1][:100]}
    if do == "set":
        w = entry_who(uid, str(req.get("key", "")))
        if not w:
            return {"ok": False, "say": "That program has not tried to use the internet on this PC yet."}
        what = req.get("answer")
        if what == "block":
            later.block_saved(w)
            return {"ok": True, "say": "%s is blocked from the internet." % w["name"]}
        if what == "ask":
            if w.get("answer") == "block" and not later.confirm(uid, "Let %s ask for the internet again?" % w["name"]):
                return {"ok": False, "say": "Nothing changed. %s stays blocked." % w["name"]}
            later.forget(w)
            return {"ok": True, "say": "The PC will ask you next time %s tries." % w["name"]}
        if what == "allow":
            if not later.allowable(w):
                why = ("is " + w["red"]) if w.get("red") else "is a remote-control app" if w.get("remote") \
                    else "is a typed command or a terminal tool"
                return {"ok": False, "say": "%s %s, so it can't be allowed for good from here. Nothing changed."
                        % (w["name"], why)}
            if not later.confirm(uid, "Allow %s to use the internet from now on?" % w["name"]):
                return {"ok": False, "say": "Nothing changed."}
            later.allow_saved(w)
            return {"ok": True, "say": "%s may use the internet now." % w["name"]}
        return {"ok": False, "say": "allow, block or ask"}
    if do == "lockdown":
        on = req.get("on") is True
        if not on and not later.confirm(uid, "Turn off Lock down? New programs will be asked again."):
            return {"ok": False, "say": "Nothing changed. Lock down is still on."}
        store.save_settings(lockdown=on)
        return {"ok": True, "say": "Lock down is on: new programs are blocked without asking." if on
                else "Lock down is off: new programs are asked again."}
    if do == "power":
        on = req.get("on") is True
        if not on and not later.confirm(uid, "Turn off Ask Before Connecting? Every program could then use the "
                                       "internet without asking. It is safer to leave it on."):
            return {"ok": False, "say": "Nothing changed. Ask Before Connecting is still on."}
        code = run(["systemctl", "enable" if on else "disable", "--now", "opensnitch.service"], 60)[0]
        if code != 0:
            return {"ok": False, "say": "That did not work."}
        return {"ok": True, "say": "Ask Before Connecting is on." if on else "Ask Before Connecting is off."}
    return {"ok": False, "say": "Unknown request."}


SLOTS = threading.BoundedSemaphore(16)   # at most 16 requests at once; idle ones are dropped after 10 s


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        if not SLOTS.acquire(blocking=False):
            return
        try:
            self.connection.settimeout(10)
            self.serve_one()
        finally:
            SLOTS.release()

    def serve_one(self):
        try:
            uid = peer_uid(self.connection)
            line = self.rfile.readline(4096)
            req = json.loads(line.decode("utf-8")) if line.strip() else {}
            out = answer(uid, req) if isinstance(req, dict) else {"ok": False, "say": "Bad request."}
        except (ValueError, OSError, TypeError) as e:
            out = {"ok": False, "say": "Bad request: %s" % clean(e, 80)}
        self.connection.settimeout(None)
        try:
            self.wfile.write((json.dumps(out) + "\n").encode("utf-8"))
        except OSError:
            pass


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def serve():
    folder = os.path.dirname(REQ_SOCK)
    os.makedirs(folder, mode=0o755, exist_ok=True)
    os.chmod(folder, 0o755)
    if os.path.exists(REQ_SOCK):
        os.unlink(REQ_SOCK)
    srv = Server(REQ_SOCK, Handler)
    os.chmod(REQ_SOCK, 0o666)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv

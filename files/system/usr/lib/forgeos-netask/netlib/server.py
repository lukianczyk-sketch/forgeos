"""The service OpenSnitch talks to: its standard "UI" protocol (gRPC) on a socket only root can open.

OpenSnitch connects to us, sends a Ping every second (with what went online, for Today's counts) and asks
AskRule for each new connection no rule covers. While we answer one question OpenSnitch blocks other new
programs for that try (they are asked next time). If this service is not running, OpenSnitch still applies
every saved answer and blocks programs it does not know (DefaultAction deny).
"""
import os
import sys
import threading
import time
from concurrent import futures

from . import ENV, LOCK, PREFIX, UI_SOCK, clean, store
from . import decide, history

STOP = threading.Event()
_SEEN = {"last": 0}


def proto():
    """The Python form of OpenSnitch's ui.proto (made at image build time)."""
    sys.path.insert(0, ENV("FORGEOS_NETASK_PROTO") or "/usr/lib/forgeos-netask/proto")
    import ui_pb2
    import ui_pb2_grpc
    return ui_pb2, ui_pb2_grpc


def conn(m):
    """A Connection message as a plain dict."""
    tree = list(m.process_tree)[1:]   # [0] is the program itself, then its parents (nearest first)
    return {"pid": m.process_id, "uid": m.user_id, "path": m.process_path, "args": list(m.process_args),
            "cwd": m.process_cwd, "md5": m.process_checksums.get("process.hash.md5", ""),
            "tree": [t.key for t in tree], "tree_pids": [t.value for t in tree],
            "host": m.dst_host, "ip": m.dst_ip, "port": m.dst_port}


def to_rule(pb, action, duration, w):
    if duration == "always":
        r = store.rule(w, action, "always")
        ops = [pb.Operator(type=o["type"], operand=o["operand"], data=o["data"], sensitive=False)
               for o in r["operator"]["list"]]
        op = pb.Operator(type="list", operand="list", data="", sensitive=False, list=ops)
        return pb.Rule(name=r["name"], description=r["description"], enabled=True, precedence=False, nolog=False,
                       action=action, duration="always", operator=op, created=int(time.time()))
    op = pb.Operator(type="simple", operand="process.path", data=w.get("path") or "unknown", sensitive=False)
    return pb.Rule(name="forgeos-netask-once", description="ForgeOS Ask Before Connecting (just this time)",
                   enabled=True, precedence=False, nolog=False, action=action, duration="once", operator=op,
                   created=int(time.time()))


def take_events(stats):
    """Today's counts and the blocked list from the events in a Ping (each event counted once)."""
    names = {}
    newest = _SEEN["last"]
    for ev in sorted(stats.events, key=lambda e: e.unixnano):
        if ev.unixnano <= _SEEN["last"]:
            continue
        newest = max(newest, ev.unixnano)
        c = ev.connection
        uid = c.user_id
        if uid not in names:
            names[uid] = {e.get("path"): (k, e.get("name")) for k, e in store.apps(uid).items() if e.get("path")}
        key, name = names[uid].get(c.process_path) or ("path:" + c.process_path, "")
        name = name or clean(os.path.basename(c.process_path), 60) or "A program"
        if ev.rule.action == "allow":
            history.count(uid, name)
        elif ev.rule.name.startswith(PREFIX):
            history.blocked(uid, key, name, c.dst_host or c.dst_ip, "you blocked it")
    _SEEN["last"] = newest


def servicer(pb, pbg):
    class UI(pbg.UIServicer):
        def Ping(self, request, context):
            try:
                if request.HasField("stats"):
                    with LOCK:
                        take_events(request.stats)
            except Exception as e:  # noqa: BLE001 - counts must never stop the answers
                print("forgeos-netask: counts: %s" % e, file=sys.stderr)
            return pb.PingReply(id=request.id)

        def AskRule(self, request, context):
            try:
                c = conn(request)
                action, duration, w = decide.handle(c)
            except Exception as e:  # noqa: BLE001 - a broken check = blocked for this try, never allowed
                print("forgeos-netask: ask failed: %s" % e, file=sys.stderr)
                return to_rule(pb, "deny", "once", {"path": request.process_path})
            return to_rule(pb, action, duration, w)

        def Subscribe(self, request, context):
            return pb.ClientConfig(id=request.id, name="ForgeOS Ask Before Connecting", version=request.version,
                                   isFirewallRunning=request.isFirewallRunning, config=request.config,
                                   logLevel=request.logLevel)

        def Notifications(self, request_iterator, context):
            def drain():
                try:
                    for _reply in request_iterator:
                        pass
                except Exception:  # noqa: BLE001 - the daemon went away; the stream just ends
                    pass
            threading.Thread(target=drain, daemon=True).start()
            while not STOP.wait(1):
                if not context.is_active():
                    return
            return
            yield  # noqa: unreachable - makes this a stream that stays open and never sends

        def PostAlert(self, request, context):
            return pb.MsgResponse(id=request.id)
    return UI()


def serve():
    """Listen on the socket until stopped. The socket's folder is root's only (0700)."""
    import grpc
    pb, pbg = proto()
    folder = os.path.dirname(UI_SOCK)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    os.chmod(folder, 0o700)
    if os.path.exists(UI_SOCK):
        os.unlink(UI_SOCK)
    srv = grpc.server(futures.ThreadPoolExecutor(max_workers=8))
    pbg.add_UIServicer_to_server(servicer(pb, pbg), srv)
    srv.add_insecure_port("unix:" + UI_SOCK)
    srv.start()
    return srv


#!/usr/bin/env python3
"""A pretend OpenSnitch daemon for the Ask Before Connecting tests (Job 24). It speaks OpenSnitch's real UI
protocol (Python made from the real ui.proto) to our service, exactly like opensnitchd does:
  netask-fake-daemon.py PROTO_DIR SOCK subscribe            -> prints the ClientConfig name we got back
  netask-fake-daemon.py PROTO_DIR SOCK ask JSON             -> prints: action duration name, then the operator as JSON
  netask-fake-daemon.py PROTO_DIR SOCK ping JSON            -> sends a Ping with events, prints the reply id
  netask-fake-daemon.py PROTO_DIR SOCK notify               -> opens the Notifications stream, prints "open" if it stays open
JSON for ask: {"pid", "uid", "path", "args", "cwd", "md5", "tree": [[path, pid], ...], "host", "ip", "port"}
JSON for ping: {"events": [{"uid", "path", "host", "action", "rule", "nano"}, ...]}
"""
import json
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import grpc  # noqa: E402
import ui_pb2  # noqa: E402
import ui_pb2_grpc  # noqa: E402


def operator_dict(op):
    return {"type": op.type, "operand": op.operand, "data": op.data, "list": [operator_dict(o) for o in op.list]}


def main():
    sock, cmd = sys.argv[2], sys.argv[3]
    ch = grpc.insecure_channel("unix:" + sock)
    ui = ui_pb2_grpc.UIStub(ch)
    if cmd == "subscribe":
        cfg = ui.Subscribe(ui_pb2.ClientConfig(id=7, name="opensnitchd", version="1.8.0",
                                               config='{"DefaultAction": "deny"}'), timeout=10)
        print(cfg.name, cfg.id, cfg.config)
    elif cmd == "ask":
        c = json.loads(sys.argv[4])
        tree = [ui_pb2.StringInt(key=c["path"], value=c.get("pid", 0))]
        tree += [ui_pb2.StringInt(key=p, value=pid) for p, pid in c.get("tree", [])]
        sums = {"process.hash.md5": c["md5"]} if c.get("md5") else {}
        m = ui_pb2.Connection(protocol="tcp", src_ip="10.0.0.5", src_port=50000, dst_ip=c.get("ip", "93.184.216.34"),
                              dst_host=c.get("host", "example.com"), dst_port=c.get("port", 443),
                              user_id=c.get("uid", 1000), process_id=c.get("pid", 0), process_path=c["path"],
                              process_cwd=c.get("cwd", "/"), process_args=c.get("args", [c["path"]]),
                              process_checksums=sums, process_tree=tree)
        r = ui.AskRule(m, timeout=float(c.get("wait", 120)))
        print(r.action, r.duration, r.name)
        print(json.dumps(operator_dict(r.operator)))
        if r.duration == "always" and os.environ.get("FORGEOS_NETASK_RULES"):
            # like opensnitchd: an "always" answer is saved as RULES/<name>.json
            with open(os.path.join(os.environ["FORGEOS_NETASK_RULES"], r.name + ".json"), "w") as f:
                json.dump({"name": r.name, "action": r.action, "duration": r.duration, "enabled": r.enabled,
                           "operator": operator_dict(r.operator)}, f, indent=2)
    elif cmd == "ping":
        p = json.loads(sys.argv[4])
        events = []
        for e in p.get("events", []):
            conn = ui_pb2.Connection(protocol="tcp", dst_host=e.get("host", ""), dst_ip="1.2.3.4", dst_port=443,
                                     user_id=e["uid"], process_path=e["path"], process_id=1)
            events.append(ui_pb2.Event(time="now", connection=conn, unixnano=e["nano"],
                                       rule=ui_pb2.Rule(name=e.get("rule", "x"), action=e.get("action", "allow"))))
        rep = ui.Ping(ui_pb2.PingRequest(id=42, stats=ui_pb2.Statistics(daemon_version="1.8.0", events=events)),
                      timeout=10)
        print(rep.id)
    elif cmd == "notify":
        def replies():
            yield ui_pb2.NotificationReply(id=0, code=ui_pb2.OK)
            import time
            time.sleep(3)
        it = ui.Notifications(replies(), timeout=2.5)
        try:
            for _n in it:
                pass
            print("closed")
        except grpc.RpcError as e:
            print("open" if e.code() == grpc.StatusCode.DEADLINE_EXCEEDED else "error %s" % e.code())


if __name__ == "__main__":
    main()

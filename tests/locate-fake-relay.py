"""A pretend ntfy relay + pretend location services for the Find My PC tests (Job 19), on 127.0.0.1.
  POST /TOPIC -> keeps the message (like ntfy: id, time, event, topic, message)
  GET  /TOPIC/json?poll=1&since=ID|UNIXTIME|12h -> the messages after that, one JSON per line
  POST /geo -> a place when 2+ Wi-Fi networks are sent (the body is kept in geo.log)
  GET  /ip  -> a public address and a city
A file "busy" in the work folder = every relay answer is 429 (too many). "down" = 503 for everything.
Usage: python3 locate-fake-relay.py WORKDIR (writes WORKDIR/relay.port, logs to WORKDIR/relay.log)
"""
import json
import os
import sys
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

WORK = sys.argv[1]
MSGS = []


def clock():
    """The tests' clock: WORKDIR/now (the same as FORGEOS_LOC_NOW), else the real time."""
    try:
        with open(os.path.join(WORK, "now")) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return int(time.time())


def log(line):
    with open(os.path.join(WORK, "relay.log"), "a") as f:
        f.write(line + "\n")


class H(BaseHTTPRequestHandler):
    def log_message(self, *_a):
        pass

    def reply(self, code, body=""):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def blocked(self):
        if os.path.exists(os.path.join(WORK, "down")):
            self.reply(503)
            return True
        if os.path.exists(os.path.join(WORK, "busy")) and not self.path.startswith(("/geo", "/ip", "/_")):
            self.reply(429)
            return True
        return False

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        if self.blocked():
            return
        path = urllib.parse.urlparse(self.path).path.strip("/")
        if path == "geo":
            with open(os.path.join(WORK, "geo.log"), "a") as f:
                f.write(body + "\n")
            aps = json.loads(body).get("wifiAccessPoints", [])
            if len(aps) >= 2:
                return self.reply(200, json.dumps({"location": {"lat": 35.132201, "lng": -118.448997}, "accuracy": 42.5}))
            return self.reply(404, json.dumps({"error": "not found"}))
        m = {"id": "m%04d" % (len(MSGS) + 1), "time": clock(),
             "event": "message", "topic": path, "message": body}
        if self.headers.get("Title"):
            m["title"] = self.headers["Title"]
        MSGS.append(m)
        log("POST %s %d" % (path, len(body)))
        self.reply(200, json.dumps(m))

    def do_GET(self):
        if self.blocked():
            return
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        parts = u.path.strip("/").split("/")
        if u.path == "/ip":
            return self.reply(200, json.dumps({"ip": "203.0.113.9", "city": "Tehachapi", "region": "California",
                                               "country": "US", "loc": "35.1322,-118.4490"}))
        if u.path == "/_all":
            return self.reply(200, "\n".join(json.dumps(m) for m in MSGS))
        if len(parts) == 2 and parts[1] == "json" and q.get("poll") == ["1"]:
            since = q.get("since", ["all"])[0]
            log("POLL %s %s" % (parts[0], since))
            mine = [m for m in MSGS if m["topic"] == parts[0]]
            ids = [m["id"] for m in mine]
            if since in ids:
                mine = mine[ids.index(since) + 1:]
            elif since.isdigit():
                mine = [m for m in mine if m["time"] >= int(since)]
            return self.reply(200, "".join(json.dumps(m) + "\n" for m in mine))
        self.reply(404)


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(os.path.join(WORK, "relay.port.new"), "w") as f:
    f.write(str(srv.server_address[1]))
os.replace(os.path.join(WORK, "relay.port.new"), os.path.join(WORK, "relay.port"))
srv.serve_forever()

"""Fake Ollama for the Find Anything tests (Job 11): a tiny web server on this PC only.

Usage: python3 tests/find-fake-ollama.py WORK-DIR   (writes the port it uses to WORK-DIR/ai-port)
/api/tags answers WORK-DIR/ai-tags; /api/chat answers WORK-DIR/ai-answer after WORK-DIR/ai-sleep
seconds and keeps the request in WORK-DIR/ai-body.json.
"""
import http.server
import json
import os
import sys
import time

W = sys.argv[1]


def read(name, default=""):
    try:
        with open(os.path.join(W, name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return default


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, text):
        data = text.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.reply(read("ai-tags", '{"models":[]}'))

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        with open(os.path.join(W, "ai-body.json"), "wb") as f:
            f.write(body)
        time.sleep(float(read("ai-sleep", "0") or 0))
        self.reply(json.dumps({"message": {"role": "assistant", "content": read("ai-answer")}}))


s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(os.path.join(W, "ai-port"), "w", encoding="utf-8") as f:
    f.write(str(s.server_address[1]))
s.serve_forever()

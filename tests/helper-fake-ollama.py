"""Fake Ollama for the Forge Helper tests (Job 13c): a tiny web server on this PC only.

Usage: python3 tests/helper-fake-ollama.py WORK-DIR   (writes its port to WORK-DIR/ai-port)
/api/tags answers WORK-DIR/ai-tags. /api/chat keeps every request in WORK-DIR/ai-bodies.jsonl and
answers by the kind of question (seen from the JSON schema it was sent):
  router (has "tool")  -> WORK-DIR/ai-route, else a pick from WORK-DIR/ai-map, else just_answer
  help card ("card")   -> WORK-DIR/ai-help, else the first card
  chat ("sure")        -> WORK-DIR/ai-just, else a short sure answer
  warm-up (no schema)  -> {}
A model named in WORK-DIR/ai-bad (one per line) answers "not json". WORK-DIR/ai-sleep = seconds to wait.
"""
import http.server
import json
import os
import re
import sys
import time

W = sys.argv[1]


def read(name, default=""):
    try:
        with open(os.path.join(W, name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return default


def question(body):
    text = body["messages"][-1]["content"]
    parts = re.findall(r"<<<\n(.*?)\n>>>", text, re.S)
    return parts[-1] if parts else text


def route(body):
    if read("ai-route"):
        return read("ai-route")
    q = question(body)
    for rx, tool, text, fix in json.loads(read("ai-map", "[]")):
        if re.search(rx, q, re.I):
            return json.dumps({"tool": tool, "text": text, "fix": fix})
    return json.dumps({"tool": "just_answer", "text": "", "fix": "none"})


def answer(body):
    fmt = body.get("format")
    if not fmt:
        return "{}"
    if body["model"] in read("ai-bad").split():
        return "not json"
    props = fmt.get("properties", {})
    if "tool" in props:
        return route(body)
    if "card" in props:
        return read("ai-help") or json.dumps({"answer": "Use the card.", "card": props["card"]["enum"][0]})
    return read("ai-just") or json.dumps({"answer": "I am Forge Helper, the helper on this PC.", "sure": True})


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, text):
        data = text.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except OSError:
            pass  # the helper stopped waiting (timeout test)

    def do_GET(self):
        self.reply(read("ai-tags", '{"models":[]}'))

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(os.path.join(W, "ai-bodies.jsonl"), "a", encoding="utf-8") as f:
            f.write(json.dumps(body) + "\n")
        time.sleep(float(read("ai-sleep", "0") or 0))
        self.reply(json.dumps({"message": {"role": "assistant", "content": answer(body)}}))


s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(os.path.join(W, "ai-port"), "w", encoding="utf-8") as f:
    f.write(str(s.server_address[1]))
s.serve_forever()

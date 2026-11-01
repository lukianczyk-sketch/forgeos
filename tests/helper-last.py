"""What Forge Helper sent to the fake AI (Job 13c tests): one fact per line.

Usage: python3 tests/helper-last.py WORK-DIR/ai-bodies.jsonl N   (N = 1 for the last request)
"""
import json
import sys

b = json.loads(open(sys.argv[1], encoding="utf-8").read().splitlines()[-int(sys.argv[2])])
opts = b.get("options", {})
print("model=%s stream=%s temperature=%s keep=%s" % (b["model"], b.get("stream"), opts.get("temperature"), b.get("keep_alive")))
props = (b.get("format") or {}).get("properties", {})
for k in sorted(props):
    print("enum %s=%s" % (k, " ".join(props[k].get("enum", []))))
for m in b.get("messages", []):
    print("%s=%s" % (m["role"], m["content"].replace("\n", " | ")))

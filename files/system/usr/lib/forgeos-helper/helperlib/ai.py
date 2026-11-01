"""Talk to the private AI on this PC (Ollama on 127.0.0.1 only, never through a proxy).

Two brains: a small QUICK one picks the tool, the MAIN one writes harder answers.
Every request: temperature 0 and a JSON schema, so the AI can only answer in the allowed shape.
"""
import json
import os
import urllib.request

from . import config_dir, read_lines

QUICK_DEFAULT = "gemma4:e2b"


def ollama():
    return os.environ.get("FORGEOS_OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")


def no_proxy_open(req, timeout):
    return urllib.request.build_opener(urllib.request.ProxyHandler({})).open(req, timeout=timeout)


def downloaded():
    """Names of the models downloaded on this PC ([] when Ollama is not running)."""
    try:
        with no_proxy_open(ollama() + "/api/tags", 5) as r:
            return [m.get("name") for m in json.load(r).get("models", []) if m.get("name")]
    except (OSError, ValueError, AttributeError, TypeError):
        return []


def saved(name):
    lines = read_lines(os.path.join(config_dir(), name))
    return lines[0] if lines else ""


def main_model(names=None):
    """The helper's best model (picked by 'forgeos-helper models'), else AI Setup's pick, else the first."""
    names = downloaded() if names is None else names
    forced = os.environ.get("FORGEOS_HELPER_MODEL", "")
    if forced:
        return forced if forced in names else None
    for m in (saved("helper-model"), saved("ai-model")):
        if m and m in names:
            return m
    return names[0] if names else None


def quick_model(names=None):
    """The small fast model for picking tools; the main model when no small one is downloaded."""
    names = downloaded() if names is None else names
    if os.environ.get("FORGEOS_HELPER_MODEL"):
        return main_model(names)
    for m in (saved("ai-quick-model"), QUICK_DEFAULT):
        if m and m in names:
            return m
    return main_model(names)


def chat(model, system, user, schema, wait=None):
    """Ask MODEL. Returns the JSON answer as a dict, or None (no AI, too slow, or a bad answer)."""
    if not model:
        return None
    body = {"model": model, "stream": False, "keep_alive": "30m", "options": {"temperature": 0},
            "format": schema, "messages": [{"role": "system", "content": system},
                                           {"role": "user", "content": user}]}
    req = urllib.request.Request(ollama() + "/api/chat", data=json.dumps(body).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    wait = float(wait or os.environ.get("FORGEOS_HELPER_AI_WAIT", "90"))
    try:
        with no_proxy_open(req, wait) as r:
            out = json.loads(json.load(r)["message"]["content"])
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return None
    return out if isinstance(out, dict) else None


def warm(model):
    """Load MODEL into memory for 30 minutes (an empty request), so the first answer is fast."""
    if not model:
        return False
    body = {"model": model, "keep_alive": "30m", "messages": []}
    req = urllib.request.Request(ollama() + "/api/chat", data=json.dumps(body).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    try:
        with no_proxy_open(req, 300) as r:
            r.read()
        return True
    except OSError:
        return False

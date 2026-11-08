"""The root watcher (forgeos-locate.service). Runs at the sign-in screen too, so a PC that was stolen asleep
reports as soon as it wakes with internet.
Normal days: look for a message from your phone every 10 minutes (every 15 seconds just after setup or a
command). Sends NOTHING unless your phone asked. Lost: look every minute; a locked report every 10 minutes
(every 20 after 2 hours), a plain "checked in" bell once an hour, a photo every 3 hours if you turned it on.
"""
import base64
import glob
import os
import time
import traceback

from . import (BACKOFF, FAST_EVERY, FAST_FOR, LOST_EVERY, NORMAL_EVERY, PHOTO_EVERY, POKE, REPORT_FIRST,
               REPORT_LATER, TRAIL, now, run, save_json)
from . import commands, relay, seal, where

CHUNK = 2400        # photo pieces: each locked message stays under the relay's 4,096-byte text limit
PHOTO_MAX = 12288   # 12 KB = at most 7 pieces


def send(key, obj):
    return relay.post(seal.topic(key, "rep"), seal.seal(key, "rep", obj))


def join_open_wifi(st):
    """Lost and no internet: try the strongest open (no password) Wi-Fi, once every 10 minutes."""
    t = now()
    if t - st.get("tried_wifi", 0) < 600:
        return False
    st["tried_wifi"] = t
    for ap in sorted((a for a in where.wifi() if a["open"] and a["ssid"]), key=lambda a: -a["signal"])[:1]:
        if run(["nmcli", "device", "wifi", "connect", ap["ssid"], "name", commands.WIFI_NAME], 60)[0] == 0:
            st["joined"] = True
            return True
    return False


def send_photo(key):
    data = where.photo()
    if not data or len(data) > PHOTO_MAX:
        return 0
    text = base64.b64encode(data).decode()
    parts = [text[i:i + CHUNK] for i in range(0, len(text), CHUNK)]
    pid = int(now())
    for i, part in enumerate(parts):
        if send(key, {"k": "photo", "id": pid, "i": i, "n": len(parts), "d": part}) != 200:
            return 0
    return len(parts)


def lost_tick(key, st):
    """While lost: the report (and bell, photo) that is due."""
    t = now()
    if t < st.get("next_report", 0):
        return
    rep = where.report()
    code = send(key, rep)
    if code not in (200, relay.TOO_MANY) and join_open_wifi(st):
        rep = where.report()
        code = send(key, rep)
    if code == relay.TOO_MANY:
        st["backoff_until"] = t + BACKOFF
    if code != 200:
        return
    tr = commands.trail()[-199:] + [rep]
    save_json(TRAIL, tr, 0o600)
    first_hours = t - st.get("lost", t) < 2 * 3600
    st["next_report"] = t + (REPORT_FIRST if first_hours else REPORT_LATER)
    if t >= st.get("next_bell", 0):
        relay.post(seal.topic(key, "bell"), "Your PC checked in. Open Find My PC on your phone to see where.",
                   "Find My PC")
        st["next_bell"] = t + 3600
    if commands.key_info().get("photo") and t >= st.get("next_photo", 0):
        st["next_photo"] = t + PHOTO_EVERY
        send_photo(key)


def poked():
    """The newest "check now" from the window (Test it): any signed-in person may ask for 15 fast minutes."""
    newest = 0.0
    for f in glob.glob(POKE):
        try:
            newest = max(newest, os.path.getmtime(f))
        except OSError:
            pass
    return newest


def answer(key, st, obj, text):
    send(key, {"k": "ack", "t": int(now()), "c": obj["c"], "text": text, "lost": bool(st.get("lost"))})


def handle(key, st, obj):
    """One command. The state is saved BEFORE anything happens, so a crash can never run it twice."""
    why = commands.check(st, obj)
    if why == "clock":
        answer(key, st, obj, "Not done: your phone's clock is ahead. Set it to automatic date and time.")
    if why:
        return False
    st["last_t"] = obj["t"]
    commands.save_state(st)
    text, off = commands.do(st, obj)
    answer(key, st, obj, text)
    print("COMMAND\t%s\t%s" % (obj["c"], text.encode("ascii", "replace").decode()), flush=True)
    return off


def tick():
    """One round. Returns how many seconds to wait before the next one."""
    k = commands.key_info()
    st = commands.state()
    if not k:
        commands.write_status(st)
        return NORMAL_EVERY
    key, t = k["key"], now()
    off = False
    poke = poked()
    if poke > st.get("poke", 0):
        st["poke"], st["fast_until"] = poke, t + FAST_FOR
    if t >= st.get("backoff_until", 0):
        status, msgs = relay.poll(seal.topic(key, "cmd"), st.get("since") or str(int(t - 3600)))
        if status == relay.TOO_MANY:
            st["backoff_until"] = t + BACKOFF
        elif status == 200:
            st["checked"] = t
        for mid, _when, text in msgs:
            if mid:
                st["since"] = mid
            obj = seal.unseal(key, "cmd", text)
            if obj:
                try:
                    off = handle(key, st, obj)
                except Exception:  # noqa: BLE001 - one bad command must never stop Find My PC
                    traceback.print_exc()
            if off:
                break
        if st.get("lost") and t >= st.get("backoff_until", 0):
            lost_tick(key, st)
    commands.save_state(st)
    commands.write_status(st)
    if off:
        commands.power_off()
    if st.get("lost"):
        return LOST_EVERY
    return FAST_EVERY if t < st.get("fast_until", 0) else NORMAL_EVERY


def main(once=False):
    while True:
        try:
            wait = tick()
        except Exception:  # noqa: BLE001 - keep going; try again in a minute
            traceback.print_exc()
            wait = LOST_EVERY
        if once:
            return 0
        end, start_poke = time.monotonic() + wait, poked()
        while time.monotonic() < end and poked() <= start_poke:
            time.sleep(min(5, max(0.1, end - time.monotonic())))

"""Draw mode: our D-Bus service tells the KWin overlay where to point; a small kdialog panel has big
Back / Next / Stop buttons (Esc = Stop). The screen is read in a helper thread so the arrow never freezes.
"""
import threading

from . import NAME, PATH, TICK, now, size, start, stranger
from . import screen
from .session import TITLE, end_text, open_place, overlay, own, panel, state

class Show:
    def __init__(self, walk, guide, card=None):
        self.walk, self.guide, self.card = walk, guide, card
        self.view, self.avoid, self.big = walk.view("look"), [], size()
        self.panel = self.key = self.loop = None
        self.busy, self.presses, self.result, self.errors = False, [], 1, 0

    # --- D-Bus: the overlay asks every 250 ms -------------------------------------------------------
    def state(self, text):
        self.avoid = own(text)
        return state(self.view, self.big)

    # --- the screen is read in a thread; presses are done there too (the AI can take a while) -----------
    def tick(self):
        if not self.busy:
            self.busy = True
            threading.Thread(target=self.look, daemon=True).start()
        return True

    def look(self):
        strange, v = stranger(), None
        try:
            if not strange:
                for p, step in self.presses[:]:
                    self.presses.remove((p, step))
                    if step in (None, self.walk.i + 1):  # a press for a step already passed is ignored
                        self.press(p)
                v = self.walk.tick(screen.look(), self.avoid, now())
                self.errors = 0
        except Exception:  # noqa: BLE001 - one bad look must never freeze the walk; 5 in a row = stop
            self.errors += 1
            v = self.walk.view("end") if self.errors >= 5 else None
            if self.errors >= 5:
                self.walk.end = "stuck"
        from gi.repository import GLib
        GLib.idle_add(self.apply, v, strange)

    def press(self, p):
        t = now()
        if p == "next":
            self.walk.go(1, t)
        elif p == "back":
            self.walk.go(-1, t)
        elif p == "again":
            self.walk.again(t)
        elif p == "start":
            open_place(self.guide)
            self.walk.i = 0
            self.walk.again(t)
        else:
            self.walk.end = "stopped"

    def apply(self, v, strange):
        self.busy = False
        if strange:
            return self.finish("stranger")
        if v is None:
            return False
        self.view = v
        if self.walk.end:
            return self.finish(self.walk.end)
        self.show_panel()
        return False

    # --- the step panel ----------------------------------------------------------------------------
    def show_panel(self):
        v = self.view
        key = (v["step"], v["mode"] == "lost")  # a new panel only for a new step (no flicker, no focus grab)
        if key == self.key and self.panel:
            return
        self.close_panel()
        self.key = key
        self.panel = start(panel(v, self.guide, self.card))

    def close_panel(self):
        if self.panel and self.panel.poll() is None:
            self.panel.terminate()
        self.panel = None

    def watch_panel(self):
        if self.panel and self.panel.poll() is not None:
            code, lost = self.panel.returncode, self.view["mode"] == "lost"
            self.panel = self.key = None
            if code in (0, 1, 2):
                p = {0: "again" if lost else "next", 1: "start" if lost else "back", 2: "stop"}[code]
                self.presses.append((p, None if p == "stop" else self.view["step"]))
                self.tick()
        return True

    # --- the end ---------------------------------------------------------------------------------
    def finish(self, why):
        self.close_panel()
        overlay(False)
        if why != "stopped":
            start(["kdialog", "--title", TITLE, "--msgbox", end_text(why, self.guide, self.card)])
        self.result = 0 if why == "done" else 1
        if self.loop:
            self.loop.quit()
        return False


def draw(walk, guide, card=None):
    """Run the walk with the arrow on the screen. Exit 0 done, 1 not finished."""
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    show = Show(walk, guide, card)
    name = None
    for n in range(40):  # one walk at a time: end the old one, wait up to 10 s for it to go
        try:
            name = dbus.service.BusName(NAME, bus, do_not_queue=True)
            break
        except dbus.exceptions.NameExistsException:
            if n == 0:
                bus.get_object(NAME, PATH).Stop(dbus_interface=NAME, timeout=10)
            GLib.usleep(250000)
    if name is None:
        print("Another Show Me How is still running. Try again in a moment.")
        return 1

    class Service(dbus.service.Object):
        @dbus.service.method(NAME, in_signature="s", out_signature="s")
        def State(self, text):
            return show.state(str(text))

        @dbus.service.method(NAME, in_signature="", out_signature="")
        def Stop(self):
            show.presses.append(("stop", None))
            show.tick()

    service = Service(bus, PATH)
    open_place(guide)
    if not overlay(True):
        print("The arrow could not be drawn (KWin did not load the overlay); the steps are shown in the panel.")
    show.loop = GLib.MainLoop()
    GLib.timeout_add(1500, lambda: show.tick() and False)
    GLib.timeout_add(int(TICK * 1000), show.tick)
    GLib.timeout_add(200, show.watch_panel)
    show.loop.run()
    del service, name
    return show.result

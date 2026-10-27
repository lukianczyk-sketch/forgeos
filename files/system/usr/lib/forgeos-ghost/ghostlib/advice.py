"""Plain-English "what is it / what do I do now" for every kind of find, and the room checklist."""

UNSAFE = ("If you feel unsafe: call 911 if you are in danger. National Domestic Violence Hotline "
          "(free, 24/7): 1-800-799-7233. Keep the tracker as evidence - write down the time and place.")
TRACKER = (
    "What to do now:\n"
    "1. Don't panic - it may be someone's lost item. Choose \"Hunt it\" and walk around; the meter "
    "gets hotter as you get closer. Check bags, jacket pockets, car (under seats, bumpers, wheel wells), "
    "motorcycle saddlebags and under the seat.\n"
    "2. Found it? %s\n"
    "3. To stop it reporting where you are, take the battery out.\n\n" + UNSAFE)
HOW = {
    "airtag": "Hold the top of an iPhone, or an Android phone with NFC, to the white side: it shows the "
              "serial number, and the last 4 digits of the owner's phone if they marked it lost. Battery: "
              "press the shiny metal cover and turn it to the left.",
    "findmy": "Hold an iPhone near it, or use the iPhone Find My app, Items tab, \"Identify Found Item\".",
    "airpods": "AirPods away from their owner are usually just lost. If they keep showing up with you, "
               "an iPhone near them can show their serial number.",
    "apple": "This is someone's iPhone, iPad or Mac in lost mode. If it is hidden near you, take it to police.",
    "galaxy": "This is a lost Samsung phone or watch. If it is hidden near you, take it to police.",
    "smarttag": "A Samsung phone (SmartThings app, \"Unknown tag search\") can identify it. Battery: open "
                "the back with a coin.",
    "google": "An Android phone (Settings, Safety & emergency, Unknown tracker alerts, Scan now) can show "
              "its details and make it ring.",
    "dult": "An Android phone (Settings, Safety & emergency, Unknown tracker alerts, Scan now) or an "
            "iPhone can identify it.",
    "tile": "Tile's free app has \"Scan and Secure\" to identify it. Battery: open the back with a coin.",
    "chipolo": "Look for a small round or card-shaped tag. Most have a battery cover you can twist off.",
    "pebblebee": "Look for a small clip, card or tag. An Android phone's Unknown tracker scan can identify it.",
}
CAMERA = (
    "A device on this network acts like a camera (%s).\n\n"
    "At home: if it is your own camera, video doorbell or baby monitor, choose \"It's mine\".\n"
    "In a rental, hotel or someone else's place: cameras are often hidden in smoke detectors, clocks, "
    "USB chargers, outlets, TV boxes and air fresheners. Airbnb does not allow any cameras inside its "
    "listings. Unplug it or cover it, take photos, tell the host and the booking company, and call "
    "police if it is in a bedroom or bathroom.\n\n"
    "To find it: log in to the router and look for this address, or unplug gadgets one by one and "
    "sweep again until it disappears.")
HOTSPOT = (
    "Cheap hidden cameras make their own little Wi-Fi network so a phone can set them up. One is "
    "nearby. Choose \"Hunt it\" and walk around: the meter gets hotter as you get closer. It is often "
    "inside a clock, charger, smoke detector, picture frame or air freshener. " + UNSAFE)
GADGET = (
    "A small smart gadget joined this network. Most are plugs, bulbs or sensors, but cheap hidden "
    "cameras use the same chips. If you don't know what it is, unplug gadgets one by one and sweep "
    "again to find which one it is. If it's yours, choose \"It's mine\".")
NEW = (
    "A device you have not marked as yours is on this network. At home, choose \"It's mine\" for "
    "everything you know (or \"These are all mine\"), so only new devices show up next time. A device "
    "you don't recognize could be a neighbor using your Wi-Fi: change the Wi-Fi password.")
ROOMS = """Room-by-room camera check (5 minutes per room)

Tip: turn off the lights and slowly sweep a phone flashlight across the room while looking along
the beam. A camera lens throws back a tiny bright dot (blue or purple).

Bedroom: smoke detector, alarm clock, lamp, TV and TV box, picture frames, air vents, wall outlets
and USB chargers, tissue box, stuffed animals, anything pointing at the bed.
Bathroom: everything pointing at the shower or toilet - air freshener, towel hooks, outlets,
mirror, ceiling fan, vents.
Living room: smoke detector, books and shelves, plants, speakers, power strips, wall clock.
Hotel / rental extras: anything plugged in that has no clear job, gadgets with tape over them,
small holes in walls or ceilings, new screws where none are needed.
Car: OBD port under the dashboard (plug-in trackers), under seats, bumpers, wheel wells, trunk,
under the spare tire. Motorcycle: saddlebags, under the seat, behind the plate.
On you: bag lining, jacket pockets, purse, gifts you were given recently.

Found something? Don't touch it with bare hands if you may need it as evidence; take photos first.
"""


def text(item):
    kind = item.get("kind", "")
    if kind in HOW:
        what = TRACKER % HOW[kind]
        if item.get("level") == "red":
            what = "It has been near you in more than one place over time.\n\n" + what
        return what
    if kind == "camera":
        return CAMERA % (item.get("detail") or "camera maker")
    if kind == "hotspot":
        return HOTSPOT
    if kind in ("gadget", "chip"):
        return GADGET
    if kind == "router":
        return "This is the box that gives you Wi-Fi and internet. Nothing to do."
    return NEW

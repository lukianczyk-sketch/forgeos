"""A real Flatpak app (its file is inside the installed app): known by its app id. Trusted only when it is one
of ForgeOS's apps installed for the whole PC, running its own program (or the runtime's interpreter running the
app's own script), started normally. Anything else run inside the app's sandbox is asked about separately.
"""
from .names import INTERP, TOOLS, args_red, desktop_name, script_of
from .proc import tampered
from .trust import family_helper_on, remote_app, trusted_apps


def flatpak_app(me, c, fid, real):
    pid, uid, path = c.get("pid", 0), c.get("uid", 0), c.get("path", "")
    args, cwd = c.get("args") or [path], c.get("cwd", "")
    base = path.rsplit("/", 1)[-1]
    user = real == "user"   # installed in the person's home (a folder they can write): never mixed with the PC's
    key = ("flatpak-user:" if user else "flatpak:") + fid
    name = (desktop_name(flatpak_id=fid) if not user else "") or fid.split(".")[-1]
    me.update(kind="flatpak", key=key, name=name, flatpak=fid)
    own = path.startswith("/app/")
    if INTERP.match(base) or TOOLS.match(base):
        kind, script = script_of(args, cwd) if INTERP.match(base) else ("", "")
        own = kind == "file" and script.startswith("/app/")
        me["rule_ok"] = False   # the runtime's programs are shared by many apps: decided each time
        if not own:
            me.update(kind="tool", key="%s:%s" % (key, script or "cmd:" + base),
                      name="%s (a command inside %s)" % (base, name))
    red = args_red(args, cwd, uid)
    if red or tampered(pid):
        own = False
        me.update(key=key + ":unusual", name=name + " (started in an unusual way)", red=red, rule_ok=False)
    me["trusted"] = own and not user and fid in trusted_apps()
    me["remote"] = remote_app([fid, base])
    if me["remote"] and fid == "com.rustdesk.RustDesk" and me["trusted"] is False and own and not user \
            and family_helper_on(uid):
        me["remote"], me["trusted"] = None, True
    elif me["remote"]:
        me["trusted"] = False
    return me

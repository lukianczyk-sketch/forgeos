"""Builds the pretend /proc and /sys for the Why Is It Slow? tests (Job 20).

  proc DIR PID key=value...   a program: comm uid rss(MB) cpu(% of one core now) exe cgroup cmdline(words)
  mem DIR TOTAL-GB FREE-GB    /proc/meminfo
  pressure DIR KIND SOME10 SOME60 FULL10   /proc/pressure/KIND
  uptime DIR DAYS             /proc/uptime
  temp DIR NAME DEGREES       a temperature sensor in /sys/class/hwmon
  freq DIR CUR-MHZ MAX-MHZ    processor speed now / top speed (2 cores)
"""
import os
import sys

HZ = os.sysconf("SC_CLK_TCK")
cmd, d = sys.argv[1], sys.argv[2]


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


if cmd == "proc":
    pid = sys.argv[3]
    kv = dict(a.split("=", 1) for a in sys.argv[4:])
    base = os.path.join(d, pid)
    comm = kv.get("comm", "prog")
    rest = "S 1 1 1 0 -1 0 0 0 0 0 %d 0 0 0 20 0 1 0 100 0 0"
    write(os.path.join(base, "stat"), "%s (%s) %s\n" % (pid, comm, rest % 1000))
    ticks = 1000 + int(float(kv.get("cpu", "0")) * HZ / 100)
    write(os.path.join(base, "stat.next"), "%s (%s) %s\n" % (pid, comm, rest % ticks))
    write(os.path.join(base, "status"), "Name:\t%s\nUid:\t%s\t%s\t%s\t%s\nVmRSS:\t%d kB\n"
          % (comm, kv.get("uid", "1000"), kv.get("uid", "1000"), kv.get("uid", "1000"), kv.get("uid", "1000"),
             int(float(kv.get("rss", "50")) * 1024)))
    write(os.path.join(base, "cgroup"), "0::%s\n" % kv.get("cgroup", "/user.slice/user-1000.slice/session-2.scope"))
    write(os.path.join(base, "cmdline"), "\0".join(kv.get("cmdline", comm).split()) + "\0")
    link = os.path.join(base, "exe")
    if os.path.lexists(link):
        os.remove(link)
    os.symlink(kv.get("exe", "/usr/bin/" + comm), link)
elif cmd == "mem":
    write(os.path.join(d, "meminfo"), "MemTotal: %d kB\nMemFree: 1000 kB\nMemAvailable: %d kB\n"
          % (float(sys.argv[3]) * 1024 ** 2, float(sys.argv[4]) * 1024 ** 2))
elif cmd == "pressure":
    s10, s60, f10 = sys.argv[4:7]
    write(os.path.join(d, "pressure", sys.argv[3]), "some avg10=%s avg60=%s avg300=0.00 total=1\n"
          "full avg10=%s avg60=0.00 avg300=0.00 total=1\n" % (s10, s60, f10))
elif cmd == "uptime":
    write(os.path.join(d, "uptime"), "%d.00 100.00\n" % (float(sys.argv[3]) * 86400))
elif cmd == "temp":
    write(os.path.join(d, "class", "hwmon", "hwmon0", "name"), sys.argv[3] + "\n")
    write(os.path.join(d, "class", "hwmon", "hwmon0", "temp1_input"), "%d\n" % (float(sys.argv[4]) * 1000))
elif cmd == "freq":
    for n in (0, 1):
        f = os.path.join(d, "devices", "system", "cpu", "cpu%d" % n, "cpufreq")
        write(os.path.join(f, "scaling_cur_freq"), "%d\n" % (int(sys.argv[3]) * 1000))
        write(os.path.join(f, "cpuinfo_max_freq"), "%d\n" % (int(sys.argv[4]) * 1000))
else:
    sys.exit("unknown: " + cmd)

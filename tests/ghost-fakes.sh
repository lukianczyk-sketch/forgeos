# shellcheck shell=bash
# Fake tools and a fake world for the GhostFinder tests (Job 12). Sourced by tests/test-ghost*.sh.
# Every fake writes its name and arguments to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home/Documents" "$WORK/cfg" "$WORK/data"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
export WORK HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/cfg" XDG_DATA_HOME="$WORK/data" PATH="$WORK/bin:$PATH"
export FORGEOS_GHOST_LIB="$ROOT/files/system/usr/lib/forgeos-ghost" FORGEOS_GHOST_OUI="$WORK/oui.txt"
export FORGEOS_GHOST_BLE_FAKE="$WORK/ble.json" FORGEOS_GHOST_WAIT=0 FORGEOS_GHOST_STEP=0
ENGINE="$ROOT/files/system/usr/bin/forgeos-ghost"
GUI="$ROOT/files/system/usr/bin/forgeos-ghost-gui"
METER="$ROOT/files/system/usr/libexec/forgeos-ghost-meter"
G() { python3 "$ENGINE" "$@"; }
T=$'\t'  # a tab, for checking the tab-separated lines
# The window runs the engine and the meter through these wrappers (git keeps no exec bits).
printf '#!/usr/bin/env bash\nexec python3 "%s" "$@"\n' "$ENGINE" > "$WORK/bin/fg-engine"
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$METER" > "$WORK/bin/fg-meter"
chmod +x "$WORK/bin/fg-engine" "$WORK/bin/fg-meter"
export FORGEOS_GHOST_ENGINE="$WORK/bin/fg-engine" FORGEOS_GHOST_METER="$WORK/bin/fg-meter"

# The makers list (same layout as /usr/share/hwdata/oui.txt).
printf '%s     (base 16)\t\t%s\n' 001122 "NETGEAR" BCAD28 "Hangzhou Hikvision Digital Technology Co.,Ltd." \
  000C29 "VMware, Inc." 24D7EB "Espressif Inc." 3C2AF4 "Brother Industries, LTD." \
  F01898 "Apple, Inc." 0012AB "Ingenic Semiconductor Co., Ltd" > "$WORK/oui.txt"

# The network: this PC is 127.0.0.1/24 on "fake0"; the router is 127.0.0.254. FAKE_OFFLINE=1 = no network.
cat > "$WORK/neigh.json" <<'EOF'
[{"dst":"127.0.0.254","lladdr":"00:11:22:33:44:01","state":["REACHABLE"]},
 {"dst":"127.0.0.10","lladdr":"bc:ad:28:00:00:10","state":["STALE"]},
 {"dst":"127.0.0.11","lladdr":"00:0c:29:00:00:11","state":["REACHABLE"]},
 {"dst":"127.0.0.12","lladdr":"00:24:8c:00:00:12","state":["REACHABLE"]},
 {"dst":"127.0.0.13","lladdr":"24:d7:eb:00:00:13","state":["DELAY"]},
 {"dst":"127.0.0.14","lladdr":"da:a1:19:00:00:14","state":["REACHABLE"]},
 {"dst":"127.0.0.15","lladdr":"3c:2a:f4:00:00:15","state":["REACHABLE"]},
 {"dst":"127.0.0.16","state":["INCOMPLETE"]},
 {"dst":"127.0.0.17","lladdr":"f0:18:98:00:00:17","state":["STALE"]},
 {"dst":"127.0.0.18","lladdr":"00:12:ab:00:00:18","state":["REACHABLE"]},
 {"dst":"127.0.0.19","lladdr":"00:12:ab:00:00:19","state":["FAILED"]}]
EOF
fake ip '[ "${FAKE_OFFLINE:-0}" = 1 ] && { echo "[]"; exit 0; }
case "$*" in
  "-j route show default") echo "[{\"dst\":\"default\",\"gateway\":\"127.0.0.254\",\"dev\":\"fake0\"}]" ;;
  "-j -4 addr show dev fake0") echo "[{\"ifname\":\"fake0\",\"addr_info\":[{\"family\":\"inet\",\"local\":\"127.0.0.1\",\"prefixlen\":24}]}]" ;;
  "-j -4 neigh show dev fake0") cat "$WORK/neigh.json" ;;
  *) exit 1 ;;
esac'
printf '%s\n' '=;fake0;IPv4;Brother\032HL-L2350DW\032v1\0462\009<i>;_ipp._tcp;local;brother.local;127.0.0.15;631;' \
  '=;fake0;IPv6;Brother\032HL-L2350DW;_ipp._tcp;local;brother.local;fe80::1;631;' \
  '+;fake0;IPv4;Brother\032HL-L2350DW;_ipp._tcp;local' > "$WORK/avahi"
fake avahi-browse 'cat "$WORK/avahi"'

# Wi-Fi this PC can hear. @SIG@ = the spy camera'"'"'s signal: next line of $WORK/wifi-seq, else 55.
printf '%s\n' '*:HomeNet:AA\:BB\:CC\:DD\:EE\:01:80' ':IPC-4F2A91:AA\:BB\:CC\:DD\:EE\:02:@SIG@' \
  ':V380_77:AA\:BB\:CC\:DD\:EE\:03:20' ':Neighbor\: Bob:AA\:BB\:CC\:DD\:EE\:04:30' ':MiniCamera:AA\:BB\:CC\:DD\:EE\:05:12' > "$WORK/wifi"
cp "$WORK/wifi" "$WORK/wifi.home"
fake nmcli '[ "${FAKE_RESCAN_FAIL:-0}" = 1 ] && [ "${!#}" = yes ] && exit 10
s=55; if [ -s "$WORK/wifi-seq" ]; then s="$(head -n 1 "$WORK/wifi-seq")"; sed -i 1d "$WORK/wifi-seq"; fi
sed "s/@SIG@/$s/" "$WORK/wifi"'
fake notify-send 'exit 0'
# ble WORLD...: write the Bluetooth world (see tests/ghost-ble-world.py). BLE_POWER=on|off|none
# (default on), BLE_BLOCKED=1 = it cannot be turned on.
ble() { python3 "$ROOT/tests/ghost-ble-world.py" "$WORK/ble.json" "${BLE_POWER:-on}" "${BLE_BLOCKED:-0}" "$@"; }
AIRTAG="1219$(printf '50%.0s' {1..23})"   # away from owner, AirTag (status 0x50: battery medium)
AIRTAG_NEAR="1202001A"                     # owner nearby: ignored
AIRPODS="1219B0$(printf '00%.0s' {1..22})" # away, AirPods (status 0xB0: battery low)
# world: the Bluetooth world of most tests (heard over 2 seconds).
world() {
  ble "AA:00:00:00:00:01,-70,apple,$AIRTAG;AA:00:00:00:00:02,-50,apple,$AIRTAG_NEAR;AA:00:00:00:00:03,-80,svc:fd5a,0200;AA:00:00:00:00:04,-70,svc:feaa,41AB;AA:00:00:00:00:08,-90,uuid:0000feed-0000-1000-8000-00805f9b34fb;AA:00:00:00:00:09,-60,none" \
      "AA:00:00:00:00:01,-52,apple,$AIRTAG;AA:00:00:00:00:06,-66,svc:0000fcb2-0000-1000-8000-00805f9b34fb,0100"
}
# start_net: start the fake camera network (tests/ghost-fake-net.py) and point GhostFinder at it.
start_net() {
  python3 "$ROOT/tests/ghost-fake-net.py" "$WORK" &
  NET_PID=$!
  trap 'kill "$NET_PID" 2>/dev/null; rm -rf "$WORK"' EXIT
  for _ in $(seq 50); do [ -s "$WORK/rtsp-port" ] && [ -s "$WORK/wsd-port" ] && break; sleep 0.1; done
  FORGEOS_GHOST_PORTS="$(cat "$WORK/rtsp-port"):video stream (RTSP)"
  FORGEOS_GHOST_WSD="127.0.0.1:$(cat "$WORK/wsd-port")"
  export FORGEOS_GHOST_PORTS FORGEOS_GHOST_WSD
}
# item LEVEL ID: what the last sweep output ($OUT) says about one device.
item() { grep -P "^ITEM\t$1\t$2\t" <<< "$OUT" | cut -f5; }
mkdir -p "$WORK/cfg/forgeos"; printf 'F0:18:98:00:00:17\tMy MacBook\n' > "$WORK/cfg/forgeos/ghost-safe.txt"
ble ""

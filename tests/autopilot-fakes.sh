# shellcheck shell=bash
# Fake PC for the Driver & BIOS Autopilot tests (Job 13d). Sourced by tests/test-autopilot*.sh.
# A fake /sys tree (PCI + USB parts, drivers, power, BIOS facts, Secure Boot), fake rpm-ostree, fwupdmgr,
# rpm, systemctl and desktop tools. Fakes log their name and arguments to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/sys" "$WORK/etc" "$WORK/hw"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
export WORK HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/cfg" XDG_STATE_HOME="$WORK/state" PATH="$WORK/bin:$PATH"
export FORGEOS_AP_LIB="$ROOT/files/system/usr/lib/forgeos-autopilot" FORGEOS_AP_SYS="$WORK/sys" FORGEOS_AP_ETC="$WORK/etc"
export FORGEOS_AP_SHARE="$ROOT/files/system/usr/share/forgeos/autopilot" FORGEOS_AP_HWDATA="$WORK/hw" FORGEOS_AP_BOOT_ID=boot-1
export FORGEOS_AP_SCREENS="$ROOT/files/system/usr/libexec/forgeos-autopilot-screens"
ENGINE="$ROOT/files/system/usr/bin/forgeos-autopilot"
GUI="$ROOT/files/system/usr/bin/forgeos-autopilot-gui"
AP() { python3 -B "$ENGINE" "$@"; }
T=$'\t'  # a tab, for checking the tab-separated lines
ST="$WORK/state/forgeos/autopilot/state.json"
LOGF="$WORK/state/forgeos/autopilot/events.log"
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$ENGINE" > "$WORK/bin/ap-engine"
printf '#!/usr/bin/env bash\necho "gui $*" >> "$WORK/calls.log"\n' > "$WORK/bin/ap-gui"
chmod +x "$WORK/bin/ap-engine" "$WORK/bin/ap-gui"
export FORGEOS_AP_ENGINE="$WORK/bin/ap-engine" FORGEOS_AP_GUI="$WORK/bin/ap-gui"

# --- the fake /sys ---
# pci SLOT CLASS VENDOR DEVICE [DRIVER]  (class like 0x030000)
pci() {
  local d="$WORK/sys/bus/pci/devices/$1"
  mkdir -p "$d"; echo "$2" > "$d/class"; echo "0x$3" > "$d/vendor"; echo "0x$4" > "$d/device"; rm -f "$d/driver"
  [ -n "${5:-}" ] && ln -s "../../../bus/pci/drivers/$5" "$d/driver"
  return 0
}
# usb DEVICE IFACE-CLASS VID PID [DRIVER]  (one device with one part, e.g. usb 1-2 0e 046d 0825 uvcvideo)
usb() {
  local p="$WORK/sys/bus/usb/devices/$1" d="$WORK/sys/bus/usb/devices/$1:1.0"
  mkdir -p "$p" "$d"; echo "$3" > "$p/idVendor"; echo "$4" > "$p/idProduct"; echo "$2" > "$d/bInterfaceClass"; rm -f "$d/driver"
  [ -n "${5:-}" ] && ln -s "../../../../bus/usb/drivers/$5" "$d/driver"
  return 0
}
nodriver() { rm -f "$WORK/sys/bus/pci/devices/$1/driver" "$WORK/sys/bus/usb/devices/$1:1.0/driver"; }
# power AC-ONLINE BATTERY%  (power 1 80 = charger in, battery 80%; power - - = desktop)
power() {
  rm -rf "$WORK/sys/class/power_supply"; mkdir -p "$WORK/sys/class/power_supply"
  [ "$1" = - ] && return 0
  mkdir -p "$WORK/sys/class/power_supply/AC" "$WORK/sys/class/power_supply/BAT0"
  echo Mains > "$WORK/sys/class/power_supply/AC/type"; echo "$1" > "$WORK/sys/class/power_supply/AC/online"
  echo Battery > "$WORK/sys/class/power_supply/BAT0/type"; echo "$2" > "$WORK/sys/class/power_supply/BAT0/capacity"
}
# dmi MAKER MODEL VERSION DATE(MM/DD/YYYY)
dmi() {
  local d="$WORK/sys/class/dmi/id"; mkdir -p "$d"
  echo "$1" > "$d/sys_vendor"; echo "$2" > "$d/product_name"; echo "$3" > "$d/bios_version"; echo "$4" > "$d/bios_date"
}
# secureboot 1|0: the EFI variable is 4 attribute bytes, then 1 (on) or 0 (off)
secureboot() {
  mkdir -p "$WORK/sys/firmware/efi/efivars"
  if [ "$1" = 1 ]; then printf '\006\000\000\000\001'; else printf '\006\000\000\000\000'; fi > "$WORK/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
}
nvidia_loaded() { if [ "$1" = yes ]; then mkdir -p "$WORK/sys/module/nvidia"; else rm -rf "$WORK/sys/module/nvidia"; fi; }

# --- free hwdata name lists (a tiny copy in the real format) ---
printf '%s\n' "# pci.ids test copy" "10de  NVIDIA Corporation" $'\t2c58  GB203M [GeForce RTX 5090 Max-Q / Mobile]' $'\t1c8d  GP107M [GeForce GTX 1050 Mobile]' \
  "8086  Intel Corporation" $'\t7d67  Arrow Lake-S [Intel Graphics]' $'\t7e40  Meteor Lake PCH CNVi WiFi' $'\t\t8086 0094  Wi-Fi 6E AX211 160MHz' \
  $'\t7f50  Arrow Lake HD Audio' "14e4  Broadcom Inc. and subsidiaries" $'\t43a0  BCM4360 802.11ac Dual Band Wireless Network Adapter' \
  "C 03  Display controller" $'\t00  VGA compatible controller' > "$WORK/hw/pci.ids"
printf '%s\n' "# usb.ids test copy" "046d  Logitech, Inc." $'\t0825  Webcam C270' "8087  Intel Corp." $'\t0033  AX211 Bluetooth' > "$WORK/hw/usb.ids"

# A normal laptop: Intel graphics + NVIDIA RTX 5090, Wi-Fi, sound, USB webcam + Bluetooth, all with drivers
normal_pc() {
  rm -rf "$WORK/sys/bus"
  pci 0000:00:02.0 0x030000 8086 7d67 i915
  pci 0000:01:00.0 0x030200 10de 2c58 nvidia
  pci 0000:00:14.3 0x028000 8086 7e40 iwlwifi
  pci 0000:00:1f.3 0x040300 8086 7f50 snd_hda_intel
  pci 0000:00:1f.4 0x0c0500 8086 7f23 i801_smbus
  usb 3-1 0e 046d 0825 uvcvideo
  usb 3-10 e0 8087 0033 btusb
  nvidia_loaded yes; secureboot 1; power 1 80; dmi "Acer" "Predator PHN18-72" "V1.05" "03/14/2025"
}

# Fake rpm-ostree, fwupdmgr, rpm, systemctl and desktop tools.
# shellcheck source=tests/autopilot-tools.sh
. "$ROOT/tests/autopilot-tools.sh"

# shellcheck shell=bash
# Fake tools for the Driver & BIOS Autopilot tests (Job 13d), sourced by tests/autopilot-fakes.sh:
# rpm-ostree, rpm, fwupdmgr (answers from JSON files in $WORK), systemctl, notify-send and desktop tools.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
# --- rpm-ostree: status from $WORK/os.json; db diff from $WORK/dbdiff.json (missing = fails) ---
REF_NV="ostree-image-signed:docker://ghcr.io/lukianczyk-sketch/forgeos-nvidia:latest"
REF_PLAIN="ostree-image-signed:docker://ghcr.io/lukianczyk-sketch/forgeos:latest"
# os BOOTED-CHECKSUM [STAGED-CHECKSUM] [IMAGE-REF]
os() {
  local ref="${3:-$REF_NV}" staged=""
  [ -n "${2:-}" ] && staged="{\"checksum\": \"$2\", \"staged\": true, \"booted\": false, \"timestamp\": 200, \"container-image-reference\": \"$ref\"},"
  echo "{\"deployments\": [$staged{\"checksum\": \"$1\", \"booted\": true, \"staged\": false, \"timestamp\": 100, \"container-image-reference\": \"$ref\"}]}" > "$WORK/os.json"
}
fake rpm-ostree 'case "$1 $2" in
  "status --json") cat "$WORK/os.json" ;;
  "db diff") [ -f "$WORK/dbdiff.json" ] && cat "$WORK/dbdiff.json" || exit 1 ;;
  rebase*) exit "$(cat "$WORK/rebase-rc" 2>/dev/null || echo 0)" ;;
  *) exit 1 ;;
esac'
fake rpm '[ "$1" = -qa ] && cat "$WORK/rpm-qa.txt" 2>/dev/null; exit 0'
printf 'kernel\t6.17.1-200.fc44\nnvidia-driver\t580.95-1.fc44\nmesa-dri-drivers\t25.2.4-1.fc44\nbash\t5.3-1.fc44\npipewire\t1.4.8-1.fc44\n' > "$WORK/rpm-qa.txt"
# --- fwupd: devices from $WORK/fw-devices.json, updates from $WORK/fw-updates.json (missing = nothing, exit 2) ---
fake fwupdmgr 'case "$1" in
  get-devices) cat "$WORK/fw-devices.json" 2>/dev/null || echo "{\"Devices\": []}" ;;
  get-updates) [ -f "$WORK/fw-updates.json" ] || { echo "{\"Devices\": []}"; exit 2; }; cat "$WORK/fw-updates.json" ;;
  update) exit "$(cat "$WORK/fw-update-rc" 2>/dev/null || echo 0)" ;;
  get-results) cat "$WORK/fw-results.json" 2>/dev/null || exit 3 ;;
  *) exit 1 ;;
esac'
BIOS_DEV='{"Name": "System Firmware", "DeviceId": "bios1", "Plugin": "uefi_capsule", "Protocols": ["org.uefi.capsule"], "Flags": ["internal", "updatable", "require-ac", "needs-reboot"], "Vendor": "Dell", "Version": "1.18.0"}'
MOUSE_DEV='{"Name": "Unifying Receiver", "DeviceId": "rcv1", "Plugin": "logitech_hidpp", "Protocols": ["com.logitech.unifying"], "Flags": ["updatable"], "Vendor": "Logitech", "Version": "RQR12.10"}'
rel() { echo "{\"Version\": \"$1\", \"Summary\": \"$2\", \"RemoteId\": \"${3:-lvfs}\", \"Flags\": [\"${4:-trusted-payload}\", \"is-upgrade\"], \"Urgency\": \"high\", \"InstallDuration\": 240}"; }
# fw_updates "DEVICE-JSON-WITHOUT-} " RELEASE-JSON ... : writes fw-updates.json with one device per pair
fw_updates() {
  local out="" sep=""
  while [ $# -ge 2 ]; do out+="$sep${1%\}}, \"Releases\": [$2]}"; sep=","; shift 2; done
  echo "{\"Devices\": [$out]}" > "$WORK/fw-updates.json"
}
# --- systemd, desktop ---
fake systemctl 'case "$*" in
  "is-enabled uupd.timer") cat "$WORK/uupd" 2>/dev/null || echo enabled ;;
  *"show uupd.service"*) cat "$WORK/uupd-result" 2>/dev/null || echo success ;;
  *) exit 0 ;;
esac'
# notify-send: with --wait it answers the next line of $WORK/clicks (e.g. "go"); the rest stay for later notes
fake notify-send 'for a in "$@"; do [ "$a" = --wait ] && [ -s "$WORK/clicks" ] && { head -n 1 "$WORK/clicks"; sed -i 1d "$WORK/clicks"; }; done; exit 0'
fake busctl 'case "$*" in *HasInhibit*) [ -f "$WORK/busy" ] && echo "b true" || echo "b false" ;; esac; exit 0'
fake gamemoded 'echo "gamemode is inactive"'
fake pgrep 'exit 1'
fake systemd-detect-virt '[ -f "$WORK/vm" ] && { echo kvm; exit 0; }; echo none; exit 1'
fake forgeos-undo 'exit 0'
fake konsole 'exit 0'
fake xdg-open 'exit 0'
fake kdialog 'exit 0'
# Wait (up to 5 s) until calls.log has N lines matching $1 (notes that don't wait start in the background).
calls_wait() { local i; for i in $(seq 1 20); do [ "$(grep -c -- "$1" "$WORK/calls.log" 2>/dev/null)" -ge "${2:-1}" ] && return 0; sleep 0.25; done; return 1; }

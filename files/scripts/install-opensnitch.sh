#!/usr/bin/env bash
# Runs at image BUILD time (not on users' machines). Ask Before Connecting (Job 24):
# installs OpenSnitch (the free GPL-3.0 program firewall) from its official GitHub release, checked against a
# fixed SHA-256, sets it up for ForgeOS, and turns OpenSnitch's UI protocol into Python for our asker.
set -oue pipefail

# Pinned version and fingerprint (checked 2026-11-11). Never use "latest".
OSN_VERSION="1.8.0"
OSN_FILE="opensnitch-${OSN_VERSION}-1.x86_64.rpm"
OSN_SHA256="e06e9119daf764e56455b61c319e496274c0274bb53bb94a0ff1ab72967fea7d"
OSN_URL="https://github.com/evilsocket/opensnitch/releases/download/v${OSN_VERSION}/${OSN_FILE}"
CONF="${FORGEOS_OSN_ETC:-/etc/opensnitchd}"
SHARE="${FORGEOS_OSN_SHARE:-/usr/share/forgeos/netask}"
PROTO_OUT="${FORGEOS_OSN_PROTO:-/usr/lib/forgeos-netask/proto}"

# configure: ForgeOS's settings in OpenSnitch's own config file (also run by tests/test-netask-files.sh).
#  - DefaultAction deny: a program nobody answered for is blocked, never silently allowed.
#  - our socket in /run/forgeos-netask (root only), not /tmp/osui.sock (any program could pretend to be us there).
#  - checksums on: rules match a program's real file AND its fingerprint, so a fake copy never matches.
configure() {
  local tmp
  tmp="$(mktemp)"
  jq '.DefaultAction = "deny" | .DefaultDuration = "once" | .ProcMonitorMethod = "ebpf"
      | .Server.Address = "unix:///run/forgeos-netask/osui.sock" | .Rules.EnableChecksums = true
      | .Rules.Path = "/etc/opensnitchd/rules/"' "$CONF/default-config.json" > "$tmp"
  jq -e '.DefaultAction == "deny" and .Rules.EnableChecksums == true' "$tmp" > /dev/null
  cat "$tmp" > "$CONF/default-config.json"
  rm -f "$tmp"
  mkdir -p "$CONF/rules"
  install -m 0644 "$SHARE"/rules/*.json "$CONF/rules/"
}

if [ "${1:-}" = configure ]; then
  configure
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
echo "Downloading OpenSnitch ${OSN_VERSION} (${OSN_FILE}) ..."
curl -fL -o "${TMP_DIR}/${OSN_FILE}" "${OSN_URL}"
echo "${OSN_SHA256}  ${TMP_DIR}/${OSN_FILE}" | sha256sum --check
echo "Checksum verified. Installing (with libnetfilter_queue from Fedora) ..."
# No package scripts: they try to start the service inside the image build. forgeos-setup.sh enables it.
dnf install -y --setopt=tsflags=noscripts "${TMP_DIR}/${OSN_FILE}"
/usr/bin/opensnitchd -version || true

configure
echo "OpenSnitch set up: DefaultAction deny, socket /run/forgeos-netask/osui.sock, checksums on, ForgeOS system rule."

# OpenSnitch's UI protocol -> Python (python3-grpcio-tools from Fedora matches Fedora's grpcio and protobuf).
mkdir -p "$PROTO_OUT"
python3 -m grpc_tools.protoc -I "$SHARE" --python_out="$PROTO_OUT" --grpc_python_out="$PROTO_OUT" "$SHARE/ui.proto"
PYTHONDONTWRITEBYTECODE=1 python3 -c "import sys; sys.path.insert(0, '$PROTO_OUT'); import ui_pb2, ui_pb2_grpc; print('UI protocol ready:', ui_pb2.Rule(name='ok').name)"

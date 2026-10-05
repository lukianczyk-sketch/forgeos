#!/usr/bin/env bash
# Runs at image BUILD time (not on users' machines).
set -oue pipefail

chmod 0755 /usr/bin/forgeos-cleansweep /usr/bin/forgeos-cleansweep-gui
mkdir -p /usr/share/forgeos
echo "ForgeOS by RL Forge Works" > /usr/share/forgeos/about

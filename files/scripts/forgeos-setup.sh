#!/usr/bin/env bash
# Runs at image BUILD time (not on users' machines).
set -oue pipefail

chmod 0755 /usr/bin/forgeos-cleansweep /usr/bin/forgeos-cleansweep-gui /usr/bin/forgeos-ai-setup /usr/bin/forgeos-ai-setup-once
mkdir -p /usr/share/forgeos
echo "ForgeOS by RL Forge Works" > /usr/share/forgeos/about
systemctl enable ollama.service

# Clean Sweep (Step 2): keep ClamAV virus signatures fresh — the database lives in
# /var/lib/clamav, which is writable on the live system.
systemctl enable clamav-freshclam.service

# rkhunter baseline must live in /usr: the image's /var is only copied on first install,
# so a /var baseline goes stale after every update and causes false alarms.
mkdir -p /usr/share/forgeos/rkhunter-db
cp -a /var/lib/rkhunter/db/. /usr/share/forgeos/rkhunter-db/
rkhunter --propupd

#!/usr/bin/env bash
# Runs at image BUILD time (not on users' machines).
set -oue pipefail

chmod 0755 /usr/bin/forgeos-cleansweep /usr/bin/forgeos-cleansweep-gui /usr/bin/forgeos-ai-setup /usr/bin/forgeos-ai-setup-once /usr/libexec/forgeos-cleansweep-weekly /usr/libexec/forgeos-password-reminder /usr/libexec/forgeos-undo-setup /usr/bin/forgeos-undo /usr/bin/forgeos-undo-gui /usr/bin/forgeos-panic /usr/libexec/forgeos-panic-helper /usr/bin/forgeos-privacy /usr/bin/forgeos-privacy-block /usr/bin/forgeos-privacy-gui /usr/bin/forgeos-scamshield /usr/libexec/forgeos-scamshield-update /usr/bin/forgeos-scamshield-gui /usr/bin/forgeos-askpc /usr/bin/forgeos-askpc-gui /usr/bin/forgeos-willitrun /usr/bin/forgeos-willitrun-gui /usr/libexec/forgeos-willitrun-update
mkdir -p /usr/share/forgeos
echo "ForgeOS by RL Forge Works" > /usr/share/forgeos/about
systemctl enable ollama.service

# Clean Sweep (Step 2): keep ClamAV virus signatures fresh — the database lives in
# /var/lib/clamav, which is writable on the live system.
systemctl enable clamav-freshclam.service

# Clean Sweep (Step 7c): weekly scan every Sunday 3 AM (catches up after a missed run).
systemctl enable forgeos-cleansweep.timer

# rkhunter baseline must live in /usr: the image's /var is only copied on first install,
# so a /var baseline goes stale after every update and causes false alarms.
mkdir -p /usr/share/forgeos/rkhunter-db
cp -a /var/lib/rkhunter/db/. /usr/share/forgeos/rkhunter-db/
rkhunter --propupd

# Undo Button (Job 5 Step 1): turn on home snapshots on first boot, take one every hour,
# and clean up old ones every hour (drop-in) so free space never drops below 20%.
systemctl enable forgeos-undo-setup.service snapper-timeline.timer snapper-cleanup.timer

# Privacy Report (Job 7): note which apps use the camera, microphone and screen, for every user.
systemctl --global enable forgeos-privacy-watch.service

# Scam Shield (Job 8): download the free lists of known scam websites every day.
systemctl enable forgeos-scamshield-update.timer

# Will It Run? (Job 10): download the free list of games with anti-cheat every day, and keep
# a copy from build day in /usr so the check works before the first daily download.
systemctl enable forgeos-willitrun-update.timer
FORGEOS_WIR_DIR=/usr/share/forgeos/willitrun-base /usr/libexec/forgeos-willitrun-update || echo "Will It Run?: no anti-cheat list at build time (the daily download adds it)."

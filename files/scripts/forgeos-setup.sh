#!/usr/bin/env bash
# Runs at image BUILD time (not on users' machines).
set -oue pipefail

chmod 0755 /usr/bin/forgeos-cleansweep /usr/bin/forgeos-cleansweep-gui /usr/bin/forgeos-ai-setup /usr/bin/forgeos-ai-setup-once /usr/libexec/forgeos-cleansweep-weekly /usr/libexec/forgeos-password-reminder /usr/libexec/forgeos-undo-setup /usr/bin/forgeos-undo /usr/bin/forgeos-undo-gui /usr/bin/forgeos-panic /usr/libexec/forgeos-panic-helper /usr/bin/forgeos-privacy /usr/bin/forgeos-privacy-block /usr/bin/forgeos-privacy-gui /usr/bin/forgeos-scamshield /usr/libexec/forgeos-scamshield-update /usr/bin/forgeos-scamshield-gui /usr/bin/forgeos-askpc /usr/bin/forgeos-askpc-gui /usr/bin/forgeos-willitrun /usr/bin/forgeos-willitrun-gui /usr/libexec/forgeos-willitrun-update /usr/bin/forgeos-find /usr/bin/forgeos-find-gui /usr/bin/forgeos-ghost /usr/bin/forgeos-ghost-gui /usr/libexec/forgeos-ghost-meter /usr/bin/forgeos-family /usr/bin/forgeos-family-gui /usr/libexec/forgeos-family-call /usr/bin/forgeos-guard /usr/bin/forgeos-guard-gui /usr/libexec/forgeos-guard-hosts /usr/bin/forgeos-helper /usr/bin/forgeos-helper-gui /usr/libexec/forgeos-helper-krunner /usr/bin/forgeos-autopilot /usr/bin/forgeos-autopilot-gui /usr/bin/forgeos-switch /usr/bin/forgeos-switch-gui /usr/libexec/forgeos-switch-boot /usr/libexec/forgeos-switch-winsetup /usr/bin/forgeos-movingday /usr/bin/forgeos-movingday-gui /usr/libexec/forgeos-movingday-mount /usr/bin/forgeos-drivehealth /usr/bin/forgeos-drivehealth-gui /usr/libexec/forgeos-drivehealth-check /usr/bin/forgeos-tripwire /usr/bin/forgeos-tripwire-gui /usr/libexec/forgeos-tripwire-helper /usr/libexec/forgeos-tripwire-release
chmod 0755 /usr/bin/forgeos-techguard /usr/bin/forgeos-techguard-gui /usr/libexec/forgeos-techguard-money /usr/libexec/forgeos-techguard-trust
chmod 0755 /usr/bin/forgeos-digitalwill /usr/bin/forgeos-digitalwill-gui /usr/libexec/forgeos-digitalwill-unlock
chmod 0755 /usr/bin/forgeos-locate /usr/bin/forgeos-locate-gui /usr/libexec/forgeos-locate-root
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

# Find Anything (Job 11): keep every user's private search list up to date (10 min after login, then hourly).
systemctl --global enable forgeos-find-index.timer

# GhostFinder (Job 12): background watch for trackers travelling with you, for every user
# (listens 15 seconds every 10 minutes, only while Bluetooth is already on).
systemctl --global enable forgeos-ghost-watch.timer

# Always-On Guard (Job 13b): the always-ready virus checker (only on PCs with about 6 GB of memory or more),
# scam and virus websites blocked for the whole PC (at boot and after every list update), and the guard
# that checks every download and every new email, for every user.
systemctl enable forgeos-clamd.service forgeos-guard-hosts.service forgeos-guard-hosts.path
systemctl --global enable forgeos-guard.service

# Forge Helper (Job 13c): for every user, quietly look for problems every 15 minutes (offers one fix,
# at most 3 notes a day), load the quick AI brain after login, and test the AI models once a week.
systemctl --global enable forgeos-helper-watch.timer forgeos-helper-warm.service forgeos-helper-models.timer

# Driver & BIOS Autopilot (Job 13d): fwupd checks the free LVFS for signed BIOS and device firmware every
# hour, and for every user Autopilot checks drivers, BIOS and firmware 2 minutes after login, then every 6 hours.
systemctl enable fwupd-refresh.timer
systemctl --global enable forgeos-autopilot.timer

# Drive Death Warning (Job 15): read every drive's health 10 minutes after start-up and every day (root, read-only),
# and for every user warn when a drive may be failing, every day until the files are backed up.
systemctl enable forgeos-drivehealth.timer
systemctl --global enable forgeos-drivehealth-notify.timer

# Ransomware Tripwire (Job 16): the root watcher stops any program that scrambles files (bait files + behavior),
# and every user's session shows the big window when it did.
systemctl enable forgeos-tripwire.service
systemctl --global enable forgeos-tripwire-alert.service

# Fake Tech Support Guard (Job 17): every user's session pauses any remote-control app the moment it starts
# and asks first, and locks money websites while someone can see the screen.
systemctl --global enable forgeos-techguard.service

# Digital Will (Job 18): for every user, a gentle reminder when the Emergency Envelope is 6 months old,
# the password safe changed after it was made, or it was started but never made.
systemctl --global enable forgeos-digitalwill-remind.timer

# Find My PC (Job 19): the root watcher looks for a message from your phone (it sends nothing on normal days)
# and reports where the PC is only after your phone marked it lost; every user's session rings and shows the message.
systemctl enable forgeos-locate.service
systemctl --global enable forgeos-locate-alert.service

#!/bin/bash

LOG_FILE="/var/log/first-boot-test-zram.log"

loginctl enable-linger atom # ensure background services (containers esp) run after logout. 

# --- SWAP ---
# Notes: Ideally under Image builder, create /swapfile
# This acts as a backup, but it is redundant

# create 1gb disk swap file 
# 600 so only root user can rw swap
if [ ! -f /swapfile ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=1024
    chmod 600 /swapfile
    mkswap /swapfile
fi

# put in fstab so it persists, with priority -2
if ! grep -q "/swapfile" /etc/fstab; then
    echo '/swapfile none swap sw,pri=-2 0 0' >> /etc/fstab
fi
swapon -a

# --- END SWAP ---

# --- START ZRAM ---
# Notes: zram-generator should already be installed via the imagebuilder, but this again acts as a just in case. 

dnf install -y zram-generator # redundant

# cats at the end of /etc/systemd/zram-generator.conf until it hits the EOF delimiter
# note for myself: <<EOF could be <<LAPTOP or something similar, any word works 
cat <<EOF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = 2048
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

# vm.swappiness 
# https://phoenixnap.com/kb/swappiness
# higher the number the more aggressive swap is, from 0..200 

# vm.watermark_boost_factor = 0
# "controls the level of reclaim when memory is being fragmented"
# https://docs.kernel.org/admin-guide/sysctl/vm.html
# Disabled this because it may stress out the CPU when the kernel keeps trying to shove stuff from regular ram into zram

# vm.watermark_scale_factor
# aggressiveness of kswapd. 
# set higher so the kernel doesnt start trying to clean memory when it doesnt have to, reducing CPU 

# vm.page-cluster = 0
# one page only 2^0=1, zram doesnt have seek time becuase it's ram 

cat <<EOF > /etc/sysctl.d/99-zram.conf
vm.swappiness = 200
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF

sysctl --system

# 5. Apply changes
systemctl daemon-reload
systemctl start /dev/zram0

# 6. Install Cloudflared
curl -fsSl https://pkg.cloudflare.com/cloudflared.repo | tee /etc/yum.repos.d/cloudflared.repo
dnf update -y
dnf install cloudflared -y

# Verification: Log to file AND print to console
{
    echo "Timestamp: $(date)"
    swapon --show
    echo "Zram Status:"
    zramctl
    echo "free -h"
    free -h
} | tee -a "$LOG_FILE" > /dev/console

cat $LOG_FILE | wall
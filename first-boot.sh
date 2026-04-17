#!/bin/bash

LOG_FILE="/var/log/first-boot-test-zram.log"

# --- ZRAM CONFIG VARS ---

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

ZRAM_SIZE="2048" #mb
ZRAM_COMPRESSION_ALGORITHM="zstd"
ZRAM_SWAP_PRIORITY="100"
ZRAM_FS_TYPE="swap"

VM_SWAPPINESS="180"
VM_WATERMARK_BOOST_FACTOR="0"
VM_WATERMARK_SCALE_FACTOR="125"
VM_PAGE_CLUSTER="0"

# --- END ZRAM CONFIG VARS ---

# ensure background services (containers esp) run after logout. 
if id "atom" &>/dev/null; then
    loginctl enable-linger atom
fi

# --- SWAP ---
# Notes: Ideally under Image builder, create /swapfile
# This acts as a backup, but it is redundant

# create 1gb disk swap file 
# 600 so only root user can rw swap
if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
    chmod 600 /swapfile
    mkswap /swapfile
fi

# put in fstab so it persists, with priority -2
# https://superuser.com/questions/173353/how-permanently-change-linux-swap-disk-priority
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
zram-size = ${ZRAM_SIZE}
compression-algorithm = ${ZRAM_COMPRESSION_ALGORITHM}
swap-priority = ${ZRAM_SWAP_PRIORITY}
fs-type = ${ZRAM_FS_TYPE}
EOF

cat <<EOF > /etc/sysctl.d/99-zram.conf
vm.swappiness = ${VM_SWAPPINESS}
vm.watermark_boost_factor = ${VM_WATERMARK_BOOST_FACTOR}
vm.watermark_scale_factor = ${VM_WATERMARK_SCALE_FACTOR}
vm.page-cluster = ${VM_PAGE_CLUSTER}
EOF

sysctl --system # applies kernel params wo reboot 

systemctl daemon-reload
systemctl start /dev/zram0

# https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/
curl -fsSl https://pkg.cloudflare.com/cloudflared.repo | tee /etc/yum.repos.d/cloudflared.repo
dnf update -y
dnf install cloudflared -y

{
    echo "Timestamp: $(date)"
    swapon --show
    echo "Zram Status:"
    zramctl
    echo "free -h"
    free -h
} | tee -a "$LOG_FILE" > /dev/console

cat $LOG_FILE | wall
#!/bin/bash

LOG_FILE="/var/log/first-boot.log"

# stdout and stderr to LOG_FILE and console
exec > >(tee -a "$LOG_FILE") 2>&1
set -x

# --- ZRAM CONFIG VARS ---

# vm.swappiness 
# https://phoenixnap.com/kb/swappiness
# higher the number the more aggressive swap is, from 0..200 

# vm.watermark_boost_factor = 0
# "controls the level of reclaim when memory is being fragmented"
# vm.watermark_scale_factor
# aggressiveness of kswapd.
# https://docs.kernel.org/admin-guide/sysctl/vm.html 

# vm.page-cluster = 0
# one page only 2^0=1, zram doesnt have seek time becuase it's ram 

ZRAM_SIZE="1" # 100% of ram, double ram size but not actually double
ZRAM_COMPRESSION_ALGORITHM="zstd"
ZRAM_SWAP_PRIORITY="100"
ZRAM_FS_TYPE="swap"

VM_SWAPPINESS="180"
VM_PAGE_CLUSTER="0"

# Script User
SCRIPT_USER="atom"

# --- END ZRAM CONFIG VARS ---

mkdir -p /home/${SCRIPT_USER}/containers
chown -R ${SCRIPT_USER}:${SCRIPT_USER} /home/${SCRIPT_USER}/containers

# ensure background services (containers esp) run after logout. 
if id "${SCRIPT_USER}" &>/dev/null; then
    loginctl enable-linger ${SCRIPT_USER}
fi

# --- SWAP ---

# create 1gb disk swap file 
# 600 so only root user can rw swap
if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
    chmod 600 /swapfile
    mkswap /swapfile

    restorecon -v /swapfile
    chcon -t swapfile_t /swapfile
fi

# put in fstab so it persists, with priority -2
# https://superuser.com/questions/173353/how-permanently-change-linux-swap-disk-priority
if ! grep -q "/swapfile" /etc/fstab; then
    echo '/swapfile none swap sw,pri=-2 0 0' >> /etc/fstab
fi
swapon /swapfile -p -2 || true

# --- END SWAP ---

# --- START ZRAM ---
# Notes: zram-generator should already be installed via the imagebuilder, but this again acts as a just in case. 

dnf install -y zram-generator # redundant

# cats at the end of /etc/systemd/zram-generator.conf until it hits the EOF delimiter
# note for myself: <<EOF could be <<LAPTOP or something similar, any word works 
cat <<EOF > /etc/systemd/zram-generator.conf
[zram0]
zram-fraction=${ZRAM_SIZE}
compression-algorithm=${ZRAM_COMPRESSION_ALGORITHM}
swap-priority=${ZRAM_SWAP_PRIORITY}
fs-type=${ZRAM_FS_TYPE}
EOF

cat <<EOF > /etc/sysctl.d/99-zram.conf
vm.swappiness=${VM_SWAPPINESS}
vm.page-cluster=${VM_PAGE_CLUSTER}
EOF

sysctl --system # applies kernel params wo reboot 

systemctl daemon-reload

# https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/
curl -fsSl https://pkg.cloudflare.com/cloudflared.repo | tee /etc/yum.repos.d/cloudflared.repo
dnf update -y
dnf install cloudflared -y

# remove annoying rc.local file
# it's not marked executable by default anyway#
# and has comments stating it's best to create own systemd services instead of using that file. 
rm /etc/rc.d/rc.local

echo "Timestamp: $(date)"
swapon --show
echo "Zram Status:"
zramctl
echo "free -h"
free -h
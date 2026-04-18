#!/bin/bash

LOG_FILE="/var/log/first-boot.log"

# stdout and stderr to LOG_FILE and console
exec > >(tee -a "$LOG_FILE") 2>&1
set -x # remove in prod 

# block logins 

echo "First boot script still running, server will reboot soon. Please wait..." > /etc/nologin

# --- VARS --- 

# --- HOST VARS ---
HOSTNAME="atomsrv"

# --- ZRAM CONFIG VARS ---
# vm.swappiness 
# https://phoenixnap.com/kb/rhel-swappiness
# higher the number the more aggressive swap is, from 0..200 

# vm.watermark_boost_factor = 0
# "controls the level of reclaim when memory is being fragmented"
# vm.watermark_scale_factor
# aggressiveness of kswapd.
# https://docs.kernel.org/admin-guide/sysctl/vm.html 

# vm.page-cluster = 0
# one page only 2^0=1, zram doesnt have seek time becuase it's ram 

ZRAM_SIZE="1.0" # 100% of ram, double ram size but not actually double
ZRAM_COMPRESSION_ALGORITHM="zstd"
ZRAM_SWAP_PRIORITY="100"
ZRAM_FS_TYPE="swap"

VM_SWAPPINESS="180"
VM_PAGE_CLUSTER="0"

# Script User
SCRIPT_USER="atom"

# --- FIX EXPIRED ACCOUNT  ---
echo "Un-expiring user account..."
chage -m 0 -M 99999 -I -1 -E -1 ${SCRIPT_USER}

# --- CHECK REGISTRATION ---
# [atom@atom ~]$ sudo subscription-manager identity && echo $?
    # system identity: 905bd8f6-0533-4efa-86f6-836a621d3384
    # name: atom
    # org name: 20392011
    # org ID: 20392011
    # 0
# [atom@atom ~]$ sudo subscription-manager unregister
    # Unregistering from: subscription.rhsm.redhat.com:443/subscription
    # System has been unregistered.
# [atom@atom ~]$ sudo subscription-manager identity
    # This system is not yet registered. Try 'subscription-manager register --help' for more information.
# [atom@atom ~]$ echo $?
    # 1

MAX_RETRIES=12          # Number of attempts
SLEEP_TIME=5           # Seconds to wait between attempts
REGISTERED=false

echo "Checking Red Hat registration status..."
for ((i=1; i<=MAX_RETRIES; i++)); do
    if subscription-manager identity >/dev/null 2>&1; then
        echo "[SUCCESS] System is registered and identity is valid."
        REGISTERED=true
        break # break when register 
    fi

    echo "[WAIT] Attempt $i/$MAX_RETRIES: Not registered yet. Retrying in ${SLEEP_TIME}s"
    sleep "$SLEEP_TIME"
done

if [ "$REGISTERED" = false ]; then
    echo "[ERROR] Timeout reached. Failed to register. Exiting to prevent broken install."
    exit 1
fi

# --- SYSTEM SETUP ---
mkdir -p /home/${SCRIPT_USER}/containers
chown -R ${SCRIPT_USER}:${SCRIPT_USER} /home/${SCRIPT_USER}/containers

# ensure background services (containers esp) run after logout. 
if id "${SCRIPT_USER}" &>/dev/null; then
    loginctl enable-linger ${SCRIPT_USER}
fi

# --- START ZRAM ---
# Notes: zram-generator should already be installed via the imagebuilder, but this again acts as a just in case. 

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

sysctl --system # applies kernel params wo reboot, we will still reboot at the end tho
systemctl daemon-reload

# --- SOFTWARE ---
# https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/
curl -fsSl https://pkg.cloudflare.com/cloudflared.repo | tee /etc/yum.repos.d/cloudflared.repo
dnf install cloudflared -y

npm install fastify
npm install -D typescript @types/node tsx

# --- CLEANUP ---
rm /etc/rc.d/rc.local

sync # flush filesystem buffers to disk
rm -f /etc/nologin

# --- HOSTNAME ---
hostnamectl set-hostname $HOSTNAME

echo "Done first script, rebooting" 

# From gemini: 
    # We put the sleep INSIDE the subshell so the main script can exit 
    # and the init system (systemd) marks the task as "Success" before the reboot hits.
(sleep 2; reboot) &

echo "Reboot scheduled, script exiting"
exit 0
#!/bin/bash

REMOTE_SCRIPT="https://raw.githubusercontent.com/anthony1x6000/rhel-scripts/refs/heads/main/first-boot.sh"
LOCAL_PATH="/root/first-boot.sh"

curl -fsSL "$REMOTE_SCRIPT" -o "$LOCAL_PATH"

if [ $? -eq 0 ]; then
    chmod +x "$LOCAL_PATH"
    bash "$LOCAL_PATH"
else
    echo "ERROR: Failed to download" >&2
    exit 1
fi
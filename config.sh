#!/bin/bash

# config.sh - Updated for better disk detection

# Function to detect disks using lsblk in JSON format
function detect_disks() {
    disks=$(lsblk -J | jq -r '.blockdevices[] | select(.type == "disk") | .name')
    if [ -z "$disks" ]; then
        echo "No disks found using lsblk. Falling back to Python..."
        disks=$(python3 -c "import psutil; [print(d.device) for d in psutil.disk_partitions(all=False)]")
    fi
    echo "Detected disks: $disks"
}

# Call the detect_disks function

detect_disks

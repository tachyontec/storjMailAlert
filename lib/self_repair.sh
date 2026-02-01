#!/bin/bash
#
# StorjMailAlert - Self Repair Functions
# Functions for automatic recovery of node issues
# Only runs when IS_NODE_OPERATOR=true
#

# Source common functions if not already loaded
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/lib/common.sh"
fi

# ------------------------------------------------------------------------------
# Disk Repair Functions
# ------------------------------------------------------------------------------

# Check if a mount point has a mounted disk
check_mount() {
    local mount_point="$1"
    if mountpoint -q "$mount_point" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Check if disk is mounted using lsblk
check_disk_mounted() {
    local mount_name="$1"
    if lsblk | grep -qw "$mount_name"; then
        return 0
    fi
    return 1
}

# Attempt to mount all fstab entries
try_mount_all() {
    log_info "Attempting to mount all fstab entries..."
    if mount -a 2>/dev/null; then
        log_info "mount -a completed successfully"
        return 0
    else
        log_error "mount -a failed"
        return 1
    fi
}

# Find an unmounted disk
find_unmounted_disk() {
    lsblk -pnro NAME,MOUNTPOINT | awk '$2 == ""' | head -n 1 | awk '{print $1}'
}

# Repair mount for a specific node index
repair_mount() {
    local index="$1"
    local mount_point
    mount_point="/mnt/$(get_mount_point "$index")"
    local result=""

    result+="Checking mount for $mount_point\n"

    if check_mount "$mount_point"; then
        result+="Disk is mounted at $mount_point\n"
        echo -e "$result"
        return 0
    fi

    result+="Disk is NOT mounted at $mount_point\n"

    local available_disk
    available_disk="$(find_unmounted_disk)"

    if [[ -n "$available_disk" ]]; then
        result+="Found unmounted disk: $available_disk\n"
        result+="Attempting mount -a...\n"

        if try_mount_all; then
            if check_mount "$mount_point"; then
                result+="Mount successful!\n"
            else
                result+="Mount -a ran but $mount_point still not mounted\n"
            fi
        else
            result+="Mount attempt failed\n"
        fi
    else
        result+="No unmounted disk available for recovery\n"
    fi

    echo -e "$result"
    return 1
}

# ------------------------------------------------------------------------------
# Container Repair Functions
# ------------------------------------------------------------------------------

# Restart a docker container
restart_container() {
    local container_name="$1"
    local result=""

    result+="Restarting container $container_name...\n"

    if docker restart "$container_name" 2>/dev/null; then
        result+="Container $container_name restarted successfully\n"
        echo -e "$result"
        return 0
    else
        result+="Failed to restart container $container_name\n"
        echo -e "$result"
        return 1
    fi
}

# Full repair sequence for a node
repair_node() {
    local index="$1"
    local result=""
    local mount_point
    local container_name

    mount_point="$(get_mount_point "$index")"
    container_name="$(get_container_name "$index")"

    result+="===== Self-Repair for Node $index =====\n\n"

    # Step 1: Check and repair mount
    result+="$(repair_mount "$index")\n"

    # Step 2: Restart container
    result+="$(restart_container "$container_name")\n"

    echo -e "$result"
}

# ------------------------------------------------------------------------------
# NOIP Repair Functions
# ------------------------------------------------------------------------------

# Get current public IP
get_public_ip() {
    curl -s --max-time 10 https://ipecho.net/plain 2>/dev/null || \
    curl -s --max-time 10 -4 ifconfig.co 2>/dev/null || \
    echo ""
}

# Get IP configured in noip2
get_noip_ip() {
    if ! command -v noip2 &> /dev/null; then
        echo ""
        return 1
    fi

    noip2 -S 2>&1 | grep "Last IP Address set" | awk '{print $5}' || echo ""
}

# Restart noip2 daemon
restart_noip() {
    local result=""

    result+="Restarting noip2 daemon...\n"

    if noip2 2>/dev/null; then
        result+="noip2 restarted successfully\n"
        echo -e "$result"
        return 0
    else
        result+="Failed to restart noip2\n"
        echo -e "$result"
        return 1
    fi
}

# Check and repair NOIP configuration
repair_noip() {
    local result=""
    local public_ip
    local noip_ip

    public_ip="$(get_public_ip)"
    noip_ip="$(get_noip_ip)"

    result+="===== NOIP Check =====\n"
    result+="Current public IP: ${public_ip:-unknown}\n"
    result+="NOIP configured IP: ${noip_ip:-unknown}\n"

    if [[ -z "$public_ip" ]]; then
        result+="Could not determine public IP\n"
        echo -e "$result"
        return 1
    fi

    # Check if noip_ip is empty
    if [[ -z "$noip_ip" ]]; then
        result+="Could not get NOIP status (noip2 not installed?)\n"
        echo -e "$result"
        return 1
    # Validate noip_ip format
    elif ! [[ "$noip_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        result+="NOIP returned invalid IP format: $noip_ip\n"
        echo -e "$result"
        return 1
    fi

    if [[ "$public_ip" == "$noip_ip" ]]; then
        result+="NOIP is pointing to the correct IP address\n"
        echo -e "$result"
        return 0
    else
        result+="IP mismatch detected!\n"
        result+="Noip: $noip_ip"
        result+="Public IP is $public_ip\n"
        result+="$(restart_noip)"
        echo -e "$result"
        return 1
    fi
}

#!/bin/bash
#
# StorjMailAlert - Diskψη Mount Checker
# Verifies Storj data disks are properly mounted
# Requires IS_NODE_OPERATOR=true
#

# Set strict mode
set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/self_repair.sh"

# Load configuration
load_config

# ------------------------------------------------------------------------------
# Main Function
# ------------------------------------------------------------------------------

check_disks() {
    # Verify this is a node operator machine
    if [[ "$IS_NODE_OPERATOR" != "true" ]]; then
        log_info "Disk check skipped: IS_NODE_OPERATOR is not true"
        return 0
    fi

    local has_issues=false

    # Get available disks (sd* type only)
    local disks
    disks="$(lsblk -lnp -o NAME,TYPE | awk '$2 == "disk" && $1 ~ /^\/dev\/sd/ {print $1}')"

    local disk_count
    disk_count="$(echo "$disks" | grep -c . || echo 0)"

    # Get currently mounted devices
    local mounted_devices
    mounted_devices="$(lsblk -lnp -o NAME,MOUNTPOINT | awk '$2 != "" && $1 ~ /^\/dev\/sd/ {print $1}')"

    local mounted_count
    mounted_count="$(echo "$mounted_devices" | grep -c . || echo 0)"

    log_info "Detected $disk_count disks, $mounted_count mounted"
    log_to_file "Disk check: $disk_count disks, $mounted_count mounted"

    # Build list of mount points to check.
    # Prefer nodes.json (supports custom mountPoint), fall back to /mnt/storj* discovery.
    local mount_list=""
    local local_nodes
    local_nodes="$(get_local_nodes 2>/dev/null)" || true

    if [[ -n "$local_nodes" ]]; then
        # Use mount points from nodes.json
        while IFS= read -r node_entry; do
            local mp
            mp="$(echo "$node_entry" | jq -r '.mountPoint')"
            mount_list+="${mp}"$'\n'
        done <<< "$local_nodes"
        log_info "Using mount points from nodes.json"
    else
        # Fall back: discover storj directories in /mnt
        mount_list="$(find /mnt -maxdepth 1 -type d -name "storj*" 2>/dev/null || true)"
        log_info "Using auto-discovered mount points from /mnt/storj*"
    fi

    # Remove empty lines
    mount_list="$(echo "$mount_list" | sed '/^$/d')"

    local mount_count
    mount_count="$(echo "$mount_list" | grep -c . || echo 0)"

    log_info "Checking $mount_count mount point(s)"

    if [[ "$mount_count" -eq 0 ]]; then
        log_info "No mount points to check"
        return 0
    fi

    # Check each mount point
    while IFS= read -r folder; do
        [[ -z "$folder" ]] && continue

        if ! mountpoint -q "$folder" 2>/dev/null; then
            log_error "Directory $folder is NOT mounted"
            has_issues=true

            add_alert "DISKS" "$folder is not mounted"

            local detail="===== Disk Mount Issue =====\n"
            detail+="Directory: $folder\n"
            detail+="Status: NOT MOUNTED\n\n"

            # Attempt repair
            local repair_result
            repair_result="$(repair_mount_for_directory "$folder")"
            detail+="--- Repair Attempt ---\n$repair_result"

            add_alert_detail "$detail"
        else
            log_info "$folder is properly mounted"
        fi
    done <<< "$mount_list"

    if [[ "$has_issues" == "true" ]]; then
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

repair_mount_for_directory() {
    local folder="$1"
    local result=""

    result+="Checking for unmounted disks...\n"

    # Find an unmounted disk
    local available_disk
    available_disk="$(find_unmounted_disk)"

    if [[ -n "$available_disk" ]]; then
        result+="Found unmounted disk: $available_disk\n"
        result+="Attempting mount -a (using fstab)...\n"

        if try_mount_all; then
            # Check if mount succeeded
            if mountpoint -q "$folder" 2>/dev/null; then
                result+="Mount successful!\n"

                # Restart associated container.
                # Look up the container name from nodes.json by matching mountPoint,
                # falling back to convention if not found.
                local container_name=""
                local local_nodes_repair
                local_nodes_repair="$(get_local_nodes 2>/dev/null)" || true

                if [[ -n "$local_nodes_repair" ]]; then
                    container_name="$(echo "$local_nodes_repair" | jq -r --arg mp "$folder" 'select(.mountPoint == $mp) | .containerName' 2>/dev/null || true)"
                fi

                # Fall back to convention if no match found
                if [[ -z "$container_name" ]]; then
                    local folder_name
                    folder_name="$(basename "$folder")"
                    local index
                    if [[ "$folder_name" == "storj" ]]; then
                        index=1
                    else
                        index="${folder_name#storj}"
                    fi
                    container_name="$(get_container_name "$index")"
                fi
                result+="Restarting container $container_name...\n"

                if docker restart "$container_name" 2>/dev/null; then
                    result+="Container restarted successfully\n"
                else
                    result+="Failed to restart container (may not exist)\n"
                fi
            else
                result+="mount -a completed but $folder still not mounted\n"
                result+="Check /etc/fstab configuration\n"
            fi
        else
            result+="mount -a failed\n"
        fi
    else
        result+="No unmounted disk available\n"
        result+="Possible causes:\n"
        result+="  - Disk disconnected\n"
        result+="  - Disk failure\n"
        result+="  - All disks already mounted elsewhere\n"
    fi

    echo -e "$result"
}

# ------------------------------------------------------------------------------
# Entry Point
# ------------------------------------------------------------------------------

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_disks
    exit $?
fi

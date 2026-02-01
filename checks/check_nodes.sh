#!/bin/bash
#
# StorjMailAlert - Node HTTP Status Checker
# Checks Storj node dashboard accessibility via HTTP
# Works for both node operators and remote monitors
#

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

check_nodes() {
    # Verify nodes.json exists
    if [[ ! -f "$NODES_FILE" ]]; then
        log_error "Nodes file not found: $NODES_FILE"
        log_error "Copy from config/nodes.json.example and configure your nodes"
        return 1
    fi

    # Verify jq is available
    if ! require_command "jq" "jq"; then
        return 1
    fi

    local failed_count=0
    local checked_count=0

    # Read each server from JSON
    while IFS= read -r server; do
        local name host sshport
        name="$(echo "$server" | jq -r '.name')"
        host="$(echo "$server" | jq -r '.host')"
        sshport="$(echo "$server" | jq -r '.sshPort')"

        log_info "Checking server: $name ($host)"

        # Check if domain is resolvable
        if ! getent hosts "$host" > /dev/null 2>&1; then
            log_error "DNS resolution failed for $host"
            add_alert "NODES" "$name - DNS resolution failed for $host"
            add_alert_detail "[$name] DNS resolution failed for host: $host\nCheck your NOIP/DNS configuration at https://noip.com"
            ((failed_count++))
            continue
        fi

        # Check each node entry
        local node_index=1
        while IFS= read -r node; do
            local port container_name mount_point
            port="$(echo "$node" | jq -r '.port')"
            container_name="$(resolve_container_name "$node" "$node_index")"
            mount_point="$(resolve_mount_point "$node" "$node_index")"

            local url="http://${host}:${port}"
            local status

            log_debug "Checking $url (container: $container_name, mount: $mount_point)"

            status="$(curl --max-time 10 -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")"
            ((checked_count++))

            if [[ "$status" != "200" ]]; then
                log_warn "$name node $node_index (port $port, container $container_name) returned HTTP $status"
                add_alert "NODES" "$name node $node_index ($container_name) - HTTP $status on port $port"

                local detail="[$name:$node_index] Node $container_name on port $port at $host responded with HTTP $status"

                # Self-repair if this is the local machine and we're a node operator
                if [[ "$IS_NODE_OPERATOR" == "true" ]] && is_local_machine "$name"; then
                    log_info "Attempting self-repair for $container_name (mount: $mount_point)"

                    local repair_result=""

                    # Repair mount using the resolved mount point
                    repair_result+="Checking mount at $mount_point...\n"
                    if ! mountpoint -q "$mount_point" 2>/dev/null; then
                        repair_result+="$mount_point is NOT mounted, attempting mount -a...\n"
                        if mount -a 2>/dev/null; then
                            repair_result+="mount -a completed\n"
                        else
                            repair_result+="mount -a failed\n"
                        fi
                    else
                        repair_result+="$mount_point is mounted\n"
                    fi

                    # Restart the container using the resolved name
                    repair_result+="Restarting container $container_name...\n"
                    if docker restart "$container_name" 2>/dev/null; then
                        repair_result+="Container $container_name restarted successfully\n"
                    else
                        repair_result+="Failed to restart container $container_name\n"
                    fi

                    detail+="\n\n--- Self-Repair Attempt ---\n$repair_result"
                fi

                add_alert_detail "$detail"
                ((failed_count++))
            else
                log_info "$name node $node_index (port $port, $container_name) - OK"
            fi

            ((node_index++))
        done < <(echo "$server" | jq -c '.nodes[]')

        # Check SSH port accessibility (host-level check)
        check_ssh_port "$name" "$host" "$sshport"

        # Track IP changes
        track_ip_changes "$name" "$host"

    done < <(jq -c '.servers[]' "$NODES_FILE")

    log_info "Checked $checked_count node endpoints, $failed_count failed"
    log_to_file "Node check: $checked_count checked, $failed_count failed"

    if [[ $failed_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

check_ssh_port() {
    local name="$1"
    local host="$2"
    local port="$3"

    # Skip if nmap not available
    if ! command -v nmap &> /dev/null; then
        log_debug "nmap not available, skipping SSH port check"
        return 0
    fi

    local nmap_file
    nmap_file="$(create_temp_file "nmap")"

    nmap -sV "$host" -p "$port" -Pn --max-retries 1 --host-timeout 30s > "$nmap_file" 2>/dev/null || true

    if grep -q "open" "$nmap_file"; then
        log_debug "$name SSH port $port is open"
    else
        log_warn "$name SSH port $port appears closed"
        add_alert "NODES" "$name - SSH port $port is not accessible"

        local detail="[$name] SSH port $port at $host is not accessible"

        # Self-repair for NOIP if local machine
        if [[ "$IS_NODE_OPERATOR" == "true" ]] && is_local_machine "$name"; then
            detail+="\n\n--- Self-Repair Attempt ---\n"

            # Get IPs for diagnosis
            local public_ip noip_ip dns_ip
            public_ip="$(curl -s --max-time 10 -4 ifconfig.co 2>/dev/null || echo 'unknown')"
            dns_ip="$(dig +short "$host" 2>/dev/null | xargs || echo 'unknown')"
            noip_ip="$(get_noip_ip)"

            detail+="Public IP: $public_ip\n"
            detail+="DNS resolves to: $dns_ip\n"
            detail+="NOIP configured: ${noip_ip:-not available}\n"

            if [[ "$ENABLE_NOIP_CHECK" == "true" ]]; then
                local repair_result
                repair_result="$(repair_noip)"
                detail+="\n$repair_result"
            fi
        fi

        add_alert_detail "$detail"
    fi
}

track_ip_changes() {
    local name="$1"
    local host="$2"

    local ip_log_file="${LOG_DIR}/ips-${name}.log"

    # Get current IP
    local current_ip
    current_ip="$(dig +short "$host" 2>/dev/null | head -1 | xargs || echo "")"

    # Validate IP format
    local ipv4_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

    if [[ -z "$current_ip" ]]; then
        log_debug "Could not resolve IP for $name"
        return 0
    fi

    if ! [[ $current_ip =~ $ipv4_regex ]]; then
        log_debug "Invalid IP format for $name: $current_ip"
        return 0
    fi

    # Get last recorded IP
    local last_ip=""
    if [[ -f "$ip_log_file" ]]; then
        last_ip="$(tail -1 "$ip_log_file" 2>/dev/null | awk -F'@' '{print $2}' | xargs || echo "")"
    fi

    # Record if changed
    if [[ "$current_ip" != "$last_ip" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') @ $current_ip" >> "$ip_log_file"
        log_info "IP changed for $name: $last_ip -> $current_ip"
    fi
}

# ------------------------------------------------------------------------------
# Entry Point
# ------------------------------------------------------------------------------

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_nodes
    exit $?
fi

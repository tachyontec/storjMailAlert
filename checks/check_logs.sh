#!/bin/bash
#
# StorjMailAlert - Docker Log Checker
# Analyzes Storj node docker logs for errors
# Requires IS_NODE_OPERATOR=true
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Load configuration
load_config

# ------------------------------------------------------------------------------
# Main Function
# ------------------------------------------------------------------------------

check_logs() {
    # Verify this is a node operator machine
    if [[ "$IS_NODE_OPERATOR" != "true" ]]; then
        log_info "Log check skipped: IS_NODE_OPERATOR is not true"
        return 0
    fi

    # Verify docker is available
    if ! require_command "docker" "docker.io"; then
        add_alert "LOGS" "Docker not available for log checking"
        return 1
    fi

    local has_errors=false
    local containers_checked=0

    # Try to get container names from nodes.json for the local machine.
    # If not available, fall back to convention-based auto-discovery.
    local local_nodes
    local_nodes="$(get_local_nodes 2>/dev/null)" || true

    if [[ -n "$local_nodes" ]]; then
        # Use container names from nodes.json
        while IFS= read -r node_entry; do
            local container_name
            container_name="$(echo "$node_entry" | jq -r '.containerName')"

            if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
                log_warn "Container '$container_name' from nodes.json not found"
                continue
            fi

            log_info "Checking logs for container: $container_name"
            check_container_logs "$container_name" && true || has_errors=true
            ((containers_checked++))
        done <<< "$local_nodes"
    else
        # Fall back: discover containers using naming convention
        local container_index=1
        while true; do
            local container_name
            container_name="$(get_container_name "$container_index")"

            if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
                if [[ $container_index -eq 1 ]]; then
                    log_warn "No container named '$container_name' found"
                fi
                break
            fi

            log_info "Checking logs for container: $container_name"
            check_container_logs "$container_name" && true || has_errors=true
            ((containers_checked++))
            ((container_index++))
        done
    fi

    if [[ $containers_checked -eq 0 ]]; then
        add_alert "LOGS" "No storage node containers found"
        return 1
    fi

    log_info "Checked $containers_checked container(s)"

    if [[ "$has_errors" == "true" ]]; then
        return 1
    fi
    return 0
}

check_container_logs() {
    local container_name="$1"

    # Create temp files
    local out_file
    local err_file
    local uniq_file
    out_file="$(create_temp_file "logs_out")"
    err_file="$(create_temp_file "logs_err")"
    uniq_file="$(create_temp_file "logs_uniq")"

    # Get logs from the past CHECK_INTERVAL minutes
    if ! docker logs "$container_name" --since "${CHECK_INTERVAL}m" &> "$out_file" 2>&1; then
        log_error "Failed to get logs for $container_name"
        add_alert "LOGS" "Failed to retrieve logs for $container_name"
        return 1
    fi

    # Count total logs
    local n_logs
    n_logs="$(wc -l < "$out_file")"

    # Check for empty logs
    if [[ "$n_logs" -eq 0 ]]; then
        log_warn "No logs found for $container_name in the last ${CHECK_INTERVAL} minutes"
        add_alert "LOGS" "No logs found for $container_name (possible issue)"
        return 1
    fi

    # Filter for errors (excluding "too many" which is common and not critical)
    grep -E 'FATAL|ERROR|WARN' "$out_file" | grep -v "too many" > "$err_file" || true

    local err_logs
    err_logs="$(wc -l < "$err_file")"

    # Calculate error percentage
    local percent
    percent="$(echo "scale=2; $err_logs * 100 / $n_logs" | bc)"

    log_info "$container_name: $err_logs errors out of $n_logs logs (${percent}%)"
    log_to_file "$container_name: ${percent}% errors ($err_logs/$n_logs)"

    # Check if percentage exceeds threshold
    if (( $(echo "$percent > $ERROR_PERCENT_THRESHOLD" | bc -l) )); then
        log_warn "Error threshold exceeded for $container_name"

        # Count unique errors
        cut -d "Z" -f2- "$err_file" | cut -d "{" -f1 | sort | uniq -c > "$uniq_file"
        local uniq_errors
        uniq_errors="$(wc -l < "$uniq_file")"

        # Build alert message
        add_alert "LOGS" "$container_name has ${percent}% errors (threshold: ${ERROR_PERCENT_THRESHOLD}%)"

        # Build detailed report
        local detail=""
        detail+="===== Log Analysis for $container_name =====\n"
        detail+="Total logs: $n_logs\n"
        detail+="Error logs: $err_logs\n"
        detail+="Unique errors: $uniq_errors\n"
        detail+="Error percentage: ${percent}%\n"
        detail+="\n--- Unique Errors (count | error) ---\n"
        detail+="$(cat "$uniq_file")\n"
        detail+="\n--- Recent Errors ---\n"
        detail+="$(tail -50 "$err_file")\n"

        add_alert_detail "$detail"

        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Entry Point
# ------------------------------------------------------------------------------

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_logs
    exit $?
fi

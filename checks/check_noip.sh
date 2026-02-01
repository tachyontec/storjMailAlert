#!/bin/bash
#
# StorjMailAlert - NOIP Dynamic DNS Checker
# Verifies NOIP is pointing to the correct public IP
# Can auto-restart noip2 daemon if IS_NODE_OPERATOR=true
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

check_noip() {
    # Check if noip2 is installed
    if ! command -v noip2 &> /dev/null; then
        log_info "noip2 not installed, skipping NOIP check"
        return 0
    fi

    local public_ip noip_ip
    public_ip="$(get_public_ip)"
    noip_ip="$(get_noip_ip)"

    log_info "Public IP: ${public_ip:-unknown}"
    log_info "NOIP configured IP: ${noip_ip:-unknown}"
    log_to_file "NOIP check: Public=$public_ip, NOIP=$noip_ip"

    # Validate we got the IPs
    if [[ -z "$public_ip" ]]; then
        log_error "Could not determine public IP address"
        add_alert "NOIP" "Failed to determine public IP address"
        add_alert_detail "NOIP Check: Could not fetch public IP from ipecho.net or ifconfig.co"
        return 1
    fi

    if [[ -z "$noip_ip" ]]; then
        log_error "Could not get NOIP configured IP"
        add_alert "NOIP" "Failed to get NOIP status"
        add_alert_detail "NOIP Check: noip2 -S did not return an IP address. The daemon may not be running."
        return 1
    fi

    # Compare IPs
    if [[ "$public_ip" == "$noip_ip" ]]; then
        log_info "NOIP is correctly configured"
        return 0
    fi

    # IP mismatch detected
    log_warn "NOIP IP mismatch: public=$public_ip, noip=$noip_ip"

    local detail="===== NOIP Mismatch Detected =====\n"
    detail+="Public IP: $public_ip\n"
    detail+="NOIP configured: $noip_ip\n\n"

    # Attempt repair if node operator
    if [[ "$IS_NODE_OPERATOR" == "true" ]]; then
        detail+="--- Auto-Repair Attempt ---\n"
        detail+="Restarting noip2 daemon...\n"

        if noip2 2>/dev/null; then
            detail+="noip2 daemon restarted\n"

            # Wait a moment and re-check
            sleep 5
            local new_noip_ip
            new_noip_ip="$(get_noip_ip)"

            if [[ "$public_ip" == "$new_noip_ip" ]]; then
                detail+="IP now matches after restart!\n"
                log_info "NOIP fixed after restart"
                add_alert_detail "$detail"
                # Don't add to main alerts since it's fixed
                return 0
            else
                detail+="IP still doesn't match after restart: $new_noip_ip\n"
            fi
        else
            detail+="Failed to restart noip2 daemon\n"
        fi
    else
        detail+="Self-repair disabled (IS_NODE_OPERATOR=false)\n"
    fi

    add_alert "NOIP" "IP mismatch - public: $public_ip, noip: $noip_ip"
    add_alert_detail "$detail"

    return 1
}

# ------------------------------------------------------------------------------
# Entry Point
# ------------------------------------------------------------------------------

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_noip
    exit $?
fi

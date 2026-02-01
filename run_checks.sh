#!/bin/bash
#
# StorjMailAlert - Main Entry Point
# Runs all enabled checks and sends aggregated alerts
#
# Usage: ./run_checks.sh [--check <check_name>]
#
# Options:
#   --check logs    Run only log check
#   --check nodes   Run only node check
#   --check disks   Run only disk check
#   --check noip    Run only NOIP check
#   (no options)    Run all enabled checks
#

set -euo pipefail

# Handle --help before loading config (config.env may not exist yet)
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Usage: $0 [--check <check_name>]"
            echo ""
            echo "Options:"
            echo "  --check logs    Run only log check"
            echo "  --check nodes   Run only node check"
            echo "  --check disks   Run only disk check"
            echo "  --check noip    Run only NOIP check"
            echo "  (no options)    Run all enabled checks"
            exit 0
            ;;
    esac
done

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "${SCRIPT_DIR}/lib/common.sh"

# Load configuration
load_config

# ------------------------------------------------------------------------------
# Run a specific check
# ------------------------------------------------------------------------------

run_check() {
    local check_name="$1"
    local check_script="${SCRIPT_DIR}/checks/check_${check_name}.sh"

    if [[ ! -f "$check_script" ]]; then
        log_error "Check script not found: $check_script"
        return 1
    fi

    log_info "Running check: $check_name"

    # Source and run the check
    # shellcheck source=/dev/null
    source "$check_script"

    case "$check_name" in
        logs)
            check_logs || true
            ;;
        nodes)
            check_nodes || true
            ;;
        disks)
            check_disks || true
            ;;
        noip)
            check_noip || true
            ;;
        *)
            log_error "Unknown check: $check_name"
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    local specific_check=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                specific_check="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    log_info "StorjMailAlert starting..."
    log_info "Mode: $(if [[ "$IS_NODE_OPERATOR" == "true" ]]; then echo "Node Operator"; else echo "Monitor Only"; fi)"
    log_to_file "Check started"

    # Check dependencies
    if ! check_dependencies; then
        log_error "Missing dependencies. Please install required packages."
        exit 1
    fi

    # Run specific check or all enabled checks
    if [[ -n "$specific_check" ]]; then
        run_check "$specific_check"
    else
        # Run all enabled checks

        # Log check (requires node operator mode)
        if [[ "$ENABLE_LOG_CHECK" == "true" ]]; then
            if [[ "$IS_NODE_OPERATOR" == "true" ]]; then
                run_check "logs"
            else
                log_info "Log check skipped (requires IS_NODE_OPERATOR=true)"
            fi
        fi

        # Node check (works in all modes)
        if [[ "$ENABLE_NODE_CHECK" == "true" ]]; then
            run_check "nodes"
        fi

        # Disk check (requires node operator mode)
        if [[ "$ENABLE_DISK_CHECK" == "true" ]]; then
            if [[ "$IS_NODE_OPERATOR" == "true" ]]; then
                run_check "disks"
            else
                log_info "Disk check skipped (requires IS_NODE_OPERATOR=true)"
            fi
        fi

        # NOIP check
        if [[ "$ENABLE_NOIP_CHECK" == "true" ]]; then
            run_check "noip"
        fi
    fi

    # Send aggregated alerts if any issues were found
    send_aggregated_alerts

    log_info "StorjMailAlert completed"
    log_to_file "Check completed"
}

# Run main
main "$@"

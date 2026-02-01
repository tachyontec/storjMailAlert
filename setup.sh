#!/bin/bash
#
# StorjMailAlert - Setup Script
# Creates config.env from user input and sets up cron job
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
NODES_FILE="${SCRIPT_DIR}/nodes.json"
NODES_EXAMPLE="${SCRIPT_DIR}/config/nodes.json.example"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

print_header() {
    echo ""
    echo "=============================================="
    echo "  StorjMailAlert Setup"
    echo "=============================================="
    echo ""
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

validate_positive_int() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
        return 0
    fi
    return 1
}

# ------------------------------------------------------------------------------
# Check if all necessary commands are installed
# ------------------------------------------------------------------------------

check_dependencies() {
    echo "Checking dependencies..."
    local missing=0

    for cmd in ssmtp jq bc curl; do
        if command -v "$cmd" &> /dev/null; then
            print_success "$cmd installed"
        else
            print_error "$cmd not found - install with: apt install $cmd"
            ((missing++))
        fi
    done

    if [[ $missing -gt 0 ]]; then
        echo ""
        print_warning "Some dependencies are missing. Install them before running checks."
    fi

    echo ""
}

# ------------------------------------------------------------------------------
# Create Configuration
# ------------------------------------------------------------------------------

create_config() {
    echo "Configuration Setup"
    echo "-------------------"
    echo "Press Enter to accept defaults shown in [brackets]"
    echo ""

    # Load existing values if config exists
    local current_email=""
    local current_interval="15"
    local current_threshold="5"
    local current_is_operator="true"
    local current_log_check="true"
    local current_node_check="true"
    local current_disk_check="true"
    local current_noip_check="false"
    local current_container_prefix="storagenode"

    # Config file exists in selected path
    # In this case, load existing values to use as defaults:
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Existing configuration found. Loading current values..."
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        current_email="${ALERT_EMAIL:-}"
        current_interval="${CHECK_INTERVAL:-15}"
        current_threshold="${ERROR_PERCENT_THRESHOLD:-5}"
        current_is_operator="${IS_NODE_OPERATOR:-true}"
        current_log_check="${ENABLE_LOG_CHECK:-true}"
        current_node_check="${ENABLE_NODE_CHECK:-true}"
        current_disk_check="${ENABLE_DISK_CHECK:-true}"
        current_noip_check="${ENABLE_NOIP_CHECK:-false}"
        current_container_prefix="${CONTAINER_PREFIX:-storagenode}"
        echo ""
    fi

    # Email
    while true; do
        read -rp "Alert email address [${current_email:-required}]: " input_email
        input_email="${input_email:-$current_email}"

        if [[ -z "$input_email" ]]; then
            print_error "Email is required"
            continue
        fi

        if validate_email "$input_email"; then
            ALERT_EMAIL="$input_email"
            break
        else
            print_error "Invalid email format"
        fi
    done

    # Check interval
    while true; do
        read -rp "Check interval in minutes [$current_interval]: " input_interval
        input_interval="${input_interval:-$current_interval}"

        if validate_positive_int "$input_interval"; then
            CHECK_INTERVAL="$input_interval"
            break
        else
            print_error "Must be a positive number"
        fi
    done

    # Error threshold
    while true; do
        read -rp "Error percentage threshold [$current_threshold]: " input_threshold
        input_threshold="${input_threshold:-$current_threshold}"

        if validate_positive_int "$input_threshold" && [[ "$input_threshold" -le 100 ]]; then
            ERROR_PERCENT_THRESHOLD="$input_threshold"
            break
        else
            print_error "Must be a number between 1 and 100"
        fi
    done

    # Is node operator?
    echo ""
    echo "Is this machine a Storj node operator?"
    echo "  - 'true' enables local checks (docker logs, disk mounts) and self-repair"
    echo "  - 'false' for monitoring-only (checks nodes via HTTP from remote)"
    read -rp "Is node operator? (true/false) [$current_is_operator]: " input_is_operator
    IS_NODE_OPERATOR="${input_is_operator:-$current_is_operator}"

    # Feature toggles
    echo ""
    echo "Enable/disable individual checks (true/false):"

    read -rp "Enable log check? [$current_log_check]: " input_log
    ENABLE_LOG_CHECK="${input_log:-$current_log_check}"

    read -rp "Enable node HTTP check? [$current_node_check]: " input_node
    ENABLE_NODE_CHECK="${input_node:-$current_node_check}"

    read -rp "Enable disk check? [$current_disk_check]: " input_disk
    ENABLE_DISK_CHECK="${input_disk:-$current_disk_check}"

    read -rp "Enable NOIP check? [$current_noip_check]: " input_noip
    ENABLE_NOIP_CHECK="${input_noip:-$current_noip_check}"

    # Container prefix
    read -rp "Docker container prefix [$current_container_prefix]: " input_prefix
    CONTAINER_PREFIX="${input_prefix:-$current_container_prefix}"

    # Write config file
    cat > "$CONFIG_FILE" << EOF
#
# StorjMailAlert Configuration
# Generated by setup.sh on $(date)
#

# Email Configuration
ALERT_EMAIL="$ALERT_EMAIL"

# Check Intervals (minutes)
CHECK_INTERVAL=$CHECK_INTERVAL

# Thresholds
ERROR_PERCENT_THRESHOLD=$ERROR_PERCENT_THRESHOLD

# Machine Role
IS_NODE_OPERATOR=$IS_NODE_OPERATOR

# Feature Toggles
ENABLE_LOG_CHECK=$ENABLE_LOG_CHECK
ENABLE_NODE_CHECK=$ENABLE_NODE_CHECK
ENABLE_DISK_CHECK=$ENABLE_DISK_CHECK
ENABLE_NOIP_CHECK=$ENABLE_NOIP_CHECK

# Docker Configuration
CONTAINER_PREFIX="$CONTAINER_PREFIX"

# Debug mode
DEBUG=false
EOF

    print_success "Configuration saved to $CONFIG_FILE"
}

# ------------------------------------------------------------------------------
# Setup Nodes File
# ------------------------------------------------------------------------------

setup_nodes_file() {
    if [[ -f "$NODES_FILE" ]]; then
        echo ""
        print_success "nodes.json already exists"
        return 0
    fi

    echo ""
    echo "Node Configuration"
    echo "------------------"

    if [[ -f "$NODES_EXAMPLE" ]]; then
        read -rp "Copy nodes.json.example to nodes.json? (y/n) [y]: " copy_nodes
        copy_nodes="${copy_nodes:-y}"

        if [[ "${copy_nodes,,}" == "y" ]]; then
            cp "$NODES_EXAMPLE" "$NODES_FILE"
            print_success "Copied nodes.json.example to nodes.json"
            print_warning "Edit nodes.json to add your node details"
        fi
    else
        print_warning "No nodes.json.example found. Create nodes.json manually."
    fi
}

# ------------------------------------------------------------------------------
# Setup Cron Job
# ------------------------------------------------------------------------------

setup_cron() {
    echo ""
    echo "Cron Job Setup"
    echo "--------------"

    local cron_entry="*/${CHECK_INTERVAL} * * * * ${SCRIPT_DIR}/run_checks.sh >> ${SCRIPT_DIR}/logs/cron.log 2>&1"

    echo "The following cron job will be added:"
    echo "  $cron_entry"
    echo ""

    read -rp "Add cron job? (y/n) [y]: " add_cron
    add_cron="${add_cron:-y}"

    if [[ "${add_cron,,}" != "y" ]]; then
        echo "Skipping cron setup. Add manually with: crontab -e"
        return 0
    fi

    # Create a temporary file for the new crontab
    local temp_cron
    temp_cron="$(mktemp)"

    # Remove any existing storjMailAlert cron entries
    crontab -l 2>/dev/null | grep -v "storjMailAlert\|run_checks.sh" > "$temp_cron" || true

    # Add new entry
    echo "$cron_entry" >> "$temp_cron"

    # Install new crontab
    crontab "$temp_cron"
    rm "$temp_cron"

    print_success "Cron job installed"
    echo "Checks will run every $CHECK_INTERVAL minutes"
}

# ------------------------------------------------------------------------------
# Make Scripts Executable
# ------------------------------------------------------------------------------

make_executable() {
    echo ""
    echo "Setting permissions..."

    # Make sure not to fail if already executable
    chmod +x "${SCRIPT_DIR}/run_checks.sh" 2>/dev/null || true
    chmod +x "${SCRIPT_DIR}/checks/"*.sh 2>/dev/null || true
    chmod +x "${SCRIPT_DIR}/lib/"*.sh 2>/dev/null || true

    print_success "Scripts are now executable"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    print_header

    # Check if running as root (needed for some operations)
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Cron job will be added to root's crontab."
    fi

    check_dependencies
    create_config
    setup_nodes_file
    make_executable
    setup_cron

    echo ""
    echo "=============================================="
    echo "  Setup Complete!"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo "  1. Edit nodes.json with your node details"
    echo "  2. Test manually: ./run_checks.sh"
    echo "  3. Check logs in: ${SCRIPT_DIR}/logs/"
    echo ""
    echo "To reconfigure, run: ./setup.sh"
    echo ""
}

# Maintain the possibility to add arguments in the future
main "$@"

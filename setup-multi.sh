#!/bin/bash
#
# StorjMailAlert - Multi-Node Setup Script
# Interactive wizard for operators with multiple Storj nodes.
# Generates config files for each host and an Ansible inventory,
# then optionally runs the Ansible playbook to deploy everything.
#
# Usage: ./setup-multi.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
GENERATED_DIR="${ANSIBLE_DIR}/generated"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory.ini"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

print_header() {
    echo ""
    echo "=============================================="
    echo "  StorjMailAlert Multi-Node Setup"
    echo "=============================================="
    echo ""
    echo "This wizard will help you configure StorjMailAlert"
    echo "across multiple machines using Ansible."
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

print_section() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
    echo ""
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

validate_positive_int() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local input
    read -rp "$prompt (y/n) [$default]: " input
    input="${input:-$default}"
    [[ "${input,,}" == "y" ]]
}

# ------------------------------------------------------------------------------
# Check Dependencies
# ------------------------------------------------------------------------------

check_dependencies() {
    print_section "Checking Dependencies"

    local missing=0

    if command -v ansible-playbook &> /dev/null; then
        print_success "ansible-playbook found"
    else
        print_error "ansible-playbook not found"
        echo "  Install with pip"
        echo "    pip install ansible"
        echo "  Or apt:"
        echo "    sudo apt install ansible"
        ((missing++)) || true
    fi

    if command -v jq &> /dev/null; then
        print_success "jq found"
    else
        print_error "jq not found - install with: sudo apt install jq"
        ((missing++)) || true
    fi

    if [[ $missing -gt 0 ]]; then
        echo ""
        print_error "Missing dependencies. Please install them and re-run."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Collect Common Settings
# ------------------------------------------------------------------------------

collect_common_settings() {
    print_section "Common Settings"
    echo "These settings will be applied to all nodes."
    echo "Press Enter to accept defaults shown in [brackets]."
    echo ""

    # Email
    while true; do
        read -rp "Alert email address: " ALERT_EMAIL
        if [[ -z "$ALERT_EMAIL" ]]; then
            print_error "Email is required"
            continue
        fi
        if validate_email "$ALERT_EMAIL"; then
            break
        else
            print_error "Invalid email format"
        fi
    done

    # Check interval
    while true; do
        read -rp "Check interval in minutes [15]: " CHECK_INTERVAL
        CHECK_INTERVAL="${CHECK_INTERVAL:-15}"
        if validate_positive_int "$CHECK_INTERVAL"; then
            break
        else
            print_error "Must be a positive number"
        fi
    done

    # Error threshold
    while true; do
        read -rp "Error percentage threshold [5]: " ERROR_PERCENT_THRESHOLD
        ERROR_PERCENT_THRESHOLD="${ERROR_PERCENT_THRESHOLD:-5}"
        if validate_positive_int "$ERROR_PERCENT_THRESHOLD" && [[ "$ERROR_PERCENT_THRESHOLD" -le 100 ]]; then
            break
        else
            print_error "Must be a number between 1 and 100"
        fi
    done

    # Container prefix
    read -rp "Docker container prefix [storagenode]: " CONTAINER_PREFIX
    CONTAINER_PREFIX="${CONTAINER_PREFIX:-storagenode}"

    # Feature toggles
    echo ""
    echo "Enable/disable checks (true/false):"

    read -rp "Enable log check? [true]: " ENABLE_LOG_CHECK
    ENABLE_LOG_CHECK="${ENABLE_LOG_CHECK:-true}"

    read -rp "Enable node HTTP check? [true]: " ENABLE_NODE_CHECK
    ENABLE_NODE_CHECK="${ENABLE_NODE_CHECK:-true}"

    read -rp "Enable disk check? [true]: " ENABLE_DISK_CHECK
    ENABLE_DISK_CHECK="${ENABLE_DISK_CHECK:-true}"

    read -rp "Enable NOIP check? [false]: " ENABLE_NOIP_CHECK
    ENABLE_NOIP_CHECK="${ENABLE_NOIP_CHECK:-false}"
}

# ------------------------------------------------------------------------------
# Collect Server/Node Information
# ------------------------------------------------------------------------------

# Arrays to hold server data
declare -a SERVER_NAMES=()
declare -a SERVER_HOSTS=()
declare -a SERVER_SSH_PORTS=()
declare -a SERVER_SSH_USERS=()
declare -a SERVER_IS_LOCAL=()
declare -a SERVER_NODES_JSON=()   # JSON array string per server

collect_servers() {
    print_section "Server Configuration"
    echo "Add each machine that runs Storj nodes."
    echo "The server name MUST match /etc/hostname on that machine."
    echo "Press Enter on an empty server name when done adding servers."
    echo ""

    local server_count=0

    while true; do
        # Server name (empty to stop)
        local name=""
        read -rp "Server name (must match /etc/hostname) [done]: " name
        if [[ -z "$name" ]]; then
            if [[ $server_count -eq 0 ]]; then
                print_error "At least one server is required"
                continue
            fi
            break
        fi

        ((server_count++)) || true
        echo -e "${CYAN}  Configuring: ${name}${NC}"

        # Host/domain
        local host=""
        while [[ -z "$host" ]]; do
            read -rp "  Host/domain (e.g., ${name}.ddns.net): " host
            if [[ -z "$host" ]]; then
                print_error "  Host is required"
            fi
        done

        # SSH port
        local ssh_port=""
        while true; do
            read -rp "  SSH port [22]: " ssh_port
            ssh_port="${ssh_port:-22}"
            if validate_port "$ssh_port"; then
                break
            else
                print_error "  Invalid port number"
            fi
        done

        # SSH user
        local ssh_user=""
        local default_user
        default_user="$(whoami)"
        read -rp "  SSH user [$default_user]: " ssh_user
        ssh_user="${ssh_user:-$default_user}"

        # Is this the local machine?
        local is_local="false"
        if ask_yes_no "  Is this the machine you're running setup from?" "n"; then
            is_local="true"
        fi

        # Collect nodes for this server
        local nodes_json="["
        local node_count=0

        echo ""
        echo "  Add Storj nodes running on $name."
        echo "  Press Enter on an empty port when done adding nodes."

        while true; do
            local port=""
            read -rp "    Node dashboard port [done]: " port
            if [[ -z "$port" ]]; then
                if [[ $node_count -eq 0 ]]; then
                    print_error "    At least one node is required per server"
                    continue
                fi
                break
            fi

            if ! validate_port "$port"; then
                print_error "    Invalid port"
                continue
            fi

            ((node_count++)) || true

            # Optional custom container name
            read -rp "    Custom container name? (Enter for default convention): " custom_container

            # Optional custom mount point
            read -rp "    Custom mount point? (Enter for default convention): " custom_mount

            # Build node JSON
            local node_obj="{\"port\":${port}"
            if [[ -n "$custom_container" ]]; then
                node_obj+=",\"containerName\":\"${custom_container}\""
            fi
            if [[ -n "$custom_mount" ]]; then
                node_obj+=",\"mountPoint\":\"${custom_mount}\""
            fi
            node_obj+="}"

            if [[ $node_count -gt 1 ]]; then
                nodes_json+=","
            fi
            nodes_json+="$node_obj"
            echo ""
        done

        nodes_json+="]"

        # Store server data
        SERVER_NAMES+=("$name")
        SERVER_HOSTS+=("$host")
        SERVER_SSH_PORTS+=("$ssh_port")
        SERVER_SSH_USERS+=("$ssh_user")
        SERVER_IS_LOCAL+=("$is_local")
        SERVER_NODES_JSON+=("$nodes_json")

        print_success "Added $name with $node_count node(s)"
        echo ""
    done
}

# ------------------------------------------------------------------------------
# Generate Files
# ------------------------------------------------------------------------------

generate_nodes_json() {
    print_section "Generating nodes.json"

    mkdir -p "$GENERATED_DIR"

    local json="{\"servers\":["

    for i in "${!SERVER_NAMES[@]}"; do
        if [[ $i -gt 0 ]]; then
            json+=","
        fi
        json+="{\"name\":\"${SERVER_NAMES[$i]}\","
        json+="\"host\":\"${SERVER_HOSTS[$i]}\","
        json+="\"sshPort\":${SERVER_SSH_PORTS[$i]},"
        json+="\"nodes\":${SERVER_NODES_JSON[$i]}}"
    done

    json+="]}"

    # Pretty-print with jq
    echo "$json" | jq '.' > "${GENERATED_DIR}/nodes.json"

    print_success "Generated ${GENERATED_DIR}/nodes.json"
}

generate_config_files() {
    print_section "Generating per-host config.env files"

    for i in "${!SERVER_NAMES[@]}"; do
        local name="${SERVER_NAMES[$i]}"
        local host_dir="${GENERATED_DIR}/${name}"
        mkdir -p "$host_dir"

        cat > "${host_dir}/config.env" << EOF
#
# StorjMailAlert Configuration
# Generated by setup-multi.sh on $(date)
# Host: ${name}
#

# Email Configuration
ALERT_EMAIL="${ALERT_EMAIL}"

# Check Intervals (minutes)
CHECK_INTERVAL=${CHECK_INTERVAL}

# Thresholds
ERROR_PERCENT_THRESHOLD=${ERROR_PERCENT_THRESHOLD}

# Machine Role
IS_NODE_OPERATOR=true

# Feature Toggles
ENABLE_LOG_CHECK=${ENABLE_LOG_CHECK}
ENABLE_NODE_CHECK=${ENABLE_NODE_CHECK}
ENABLE_DISK_CHECK=${ENABLE_DISK_CHECK}
ENABLE_NOIP_CHECK=${ENABLE_NOIP_CHECK}

# Docker Configuration
CONTAINER_PREFIX="${CONTAINER_PREFIX}"

# Debug mode
DEBUG=false
EOF

        print_success "Generated config for $name"
    done
}

generate_inventory() {
    print_section "Generating Ansible inventory"

    cat > "$INVENTORY_FILE" << 'HEADER'
# StorjMailAlert - Ansible Inventory
# Generated by setup-multi.sh
#
# Re-run setup-multi.sh to regenerate, or edit manually.

[storj_nodes]
HEADER

    for i in "${!SERVER_NAMES[@]}"; do
        local line="${SERVER_NAMES[$i]}"
        line+="  ansible_host=${SERVER_HOSTS[$i]}"
        line+="  ansible_port=${SERVER_SSH_PORTS[$i]}"
        line+="  ansible_user=${SERVER_SSH_USERS[$i]}"

        if [[ "${SERVER_IS_LOCAL[$i]}" == "true" ]]; then
            line+="  ansible_connection=local"
        fi

        echo "$line" >> "$INVENTORY_FILE"
    done

    print_success "Generated ${INVENTORY_FILE}"
}

# ------------------------------------------------------------------------------
# Summary and Deploy
# ------------------------------------------------------------------------------

print_summary() {
    print_section "Summary"

    echo "Common settings:"
    echo "  Email:              $ALERT_EMAIL"
    echo "  Check interval:     ${CHECK_INTERVAL}m"
    echo "  Error threshold:    ${ERROR_PERCENT_THRESHOLD}%"
    echo "  Container prefix:   $CONTAINER_PREFIX"
    echo ""
    echo "Servers:"

    for i in "${!SERVER_NAMES[@]}"; do
        local local_tag=""
        if [[ "${SERVER_IS_LOCAL[$i]}" == "true" ]]; then
            local_tag=" (local)"
        fi
        echo "  ${SERVER_NAMES[$i]} - ${SERVER_HOSTS[$i]}:${SERVER_SSH_PORTS[$i]}${local_tag}"

        # Count nodes
        local node_count
        node_count="$(echo "${SERVER_NODES_JSON[$i]}" | jq 'length')"
        echo "    ${node_count} node(s)"
    done

    echo ""
    echo "Generated files:"
    echo "  ${GENERATED_DIR}/nodes.json"
    for i in "${!SERVER_NAMES[@]}"; do
        echo "  ${GENERATED_DIR}/${SERVER_NAMES[$i]}/config.env"
    done
    echo "  ${INVENTORY_FILE}"
}

run_deployment() {
    echo ""
    if ask_yes_no "Run Ansible playbook now to deploy to all nodes?"; then
        echo ""
        echo "Running: ansible-playbook ${ANSIBLE_DIR}/playbook.yml -i ${INVENTORY_FILE}"
        echo ""
        ansible-playbook "${ANSIBLE_DIR}/playbook.yml" -i "${INVENTORY_FILE}"
    else
        echo ""
        echo "To deploy later, run:"
        echo "  ansible-playbook ${ANSIBLE_DIR}/playbook.yml -i ${INVENTORY_FILE}"
        echo ""
        echo "For a dry run first:"
        echo "  ansible-playbook ${ANSIBLE_DIR}/playbook.yml -i ${INVENTORY_FILE} --check"
    fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    print_header
    check_dependencies
    collect_common_settings
    collect_servers
    generate_nodes_json
    generate_config_files
    generate_inventory
    print_summary
    run_deployment

    echo ""
    echo "=============================================="
    echo "  Multi-Node Setup Complete!"
    echo "=============================================="
    echo ""
    echo "To reconfigure, run: ./setup-multi.sh"
    echo "To redeploy, run: ansible-playbook ${ANSIBLE_DIR}/playbook.yml -i ${INVENTORY_FILE}"
    echo ""
}

main "$@"

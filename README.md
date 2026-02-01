[![CI](https://github.com/tachyontec/storjMailAlert/actions/workflows/ci.yml/badge.svg)](https://github.com/tachyontec/storjMailAlert/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
# StorjMailAlert

A modular monitoring and alerting system for Storj storage node operators. Get email notifications when your nodes have issues, with automatic self-repair capabilities.

## Architecture Diagram

```
                              ┌─────────────────────────────────────────────────────────┐
                              │                    CRON SCHEDULER                       │
                              │                  (runs every X min)                     │
                              └───────────────────────────┬─────────────────────────────┘
                                                          │
                                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                         run_checks.sh                                               │
│                                      (Main Entry Point)                                             │
│                                                                                                     │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                          │
│   │ check_logs  │    │ check_nodes │    │ check_disks │    │ check_noip  │     Loaded from          │
│   │     .sh     │    │     .sh     │    │     .sh     │    │     .sh     │ ◄── config.env           │
│   └──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     + nodes.json         │
│          │                  │                  │                  │                                 │
└──────────┼──────────────────┼──────────────────┼──────────────────┼─────────────────────────────────┘
           │                  │                  │                  │
           ▼                  ▼                  ▼                  ▼
┌────────────────┐  ┌──────────────────┐  ┌────────────────┐  ┌────────────────┐
│  Docker Logs   │  │   HTTP Request   │  │   Disk Mount   │  │   Public IP    │
│   Analysis     │  │  to :14002 etc   │  │     Check      │  │  vs NOIP DNS   │
│                │  │                  │  │                │  │                │
│ • Error count  │  │ ┌──────────────┐ │  │ • /mnt/storj*  │  │ • ipecho.net   │
│ • FATAL/WARN   │  │ │   Node 1     │ │  │ • mountpoint   │  │ • noip2 -S     │
│ • % threshold  │  │ │   Node 2     │ │  │ • lsblk        │  │                │
│                │  │ │   Node N...  │ │  │                │  │                │
└───────┬────────┘  └ └──────────────┘ ┘  └───────┬────────┘  └───────┬────────┘
        │                    │                    │                   │
        │                    │                    │                   │
        ▼                    ▼                    ▼                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ISSUE DETECTED?                                    │
│                                                                             │
│   IS_NODE_OPERATOR=true                    IS_NODE_OPERATOR=false           │
│   ┌─────────────────────────────┐          ┌─────────────────────────────┐  │
│   │      SELF-REPAIR            │          │      ALERT ONLY             │  │
│   │  • docker restart container │          │  • No local access          │  │
│   │  • mount -a (remount disks) │          │  • HTTP checks only         │  │
│   │  • noip2 restart            │          │  • Remote monitoring        │  │
│   └─────────────────────────────┘          └─────────────────────────────┘  │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │       AGGREGATE ALERTS       │
                    │   (collect all issues)       │
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │      SEND EMAIL (ssmtp)      │
                    │                              │
                    │  To: ALERT_EMAIL             │
                    │  Subject: X issues detected  │
                    │  Body: Details + logs        │
                    └──────────────────────────────┘
```

### Deployment Scenarios

```
 SCENARIO A: Node Operator Mode              SCENARIO B: Central Monitor
 (Install on each Storj node)                (Install on separate VPS)

 ┌─────────────────────────────┐             ┌─────────────────────────────┐
 │  Raspberry Pi / Server      │             │     Monitoring VPS          │
 │  ┌───────────────────────┐  │             │                             │
 │  │    StorjMailAlert     │  │             │  ┌───────────────────────┐  │
 │  │  IS_NODE_OPERATOR=true│  │             │  │    StorjMailAlert     │  │
 │  └───────────┬───────────┘  │             │  │ IS_NODE_OPERATOR=false│  │
 │              │              │             │  └───────────┬───────────┘  │
 │              ▼              │             │              │              │
 │  ┌───────────────────────┐  │             │              │ HTTP only    │
 │  │ Local Checks:         │  │             │              ▼              │
 │  │ • Docker logs         │  │             └──────────────┼──────────────┘
 │  │ • Disk mounts         │  │                            │
 │  │ • Self-repair         │  │             ┌──────────────┴──────────────┐
 │  └───────────────────────┘  │             │                             │
 │              +              │             ▼              ▼              ▼
 │  ┌───────────────────────┐  │        ┌────────┐    ┌────────┐    ┌────────┐
 │  │ Remote Checks:        │  │        │ Node 1 │    │ Node 2 │    │ Node 3 │
 │  │ • HTTP status (as VPS)|  │        │ :14002 │    │ :14002 │    │ :14002 │
 │  └───────────────────────┘  │        └────────┘    └────────┘    └────────┘
 └─────────────────────────────┘
```

## Features

- **Docker Log Analysis** - Monitor container logs for errors with configurable thresholds
- **Node HTTP Status** - Check node dashboard accessibility across multiple hosts
- **Disk Mount Monitoring** - Verify storage disks are properly mounted
- **NOIP Dynamic DNS** - Check and auto-repair dynamic DNS configuration
- **Self-Repair** - Automatic container restart and mount recovery
- **Multi-Node Support** - Monitor multiple nodes across different machines
- **Flexible Deployment** - Run as a node operator or as a remote monitor
- **Ansible Deployment** - Automated multi-node deployment with a single command

## Deployment Modes

### Monitor-Only Mode (`IS_NODE_OPERATOR=false`)

Install on a separate machine (VPS, home server) to monitor nodes remotely. Enables:
- HTTP status checking for all configured nodes
- Email alerts when nodes are unreachable

### Node Operator Mode (`IS_NODE_OPERATOR=true`)

Install on each machine running Storj nodes. Enables `all of the above` plus:
- Local docker log checking
- Local disk mount monitoring
- Self-repair (auto-restart containers, remount disks, fix NOIP)

>Preferences can be set per check to enable/disable features as needed.

## Requirements

### Required
- `ssmtp` - For sending email alerts (configured with your SMTP server)
- `jq` - For parsing JSON configuration
- `bc` - For calculations
- `curl` - For HTTP checks and IP detection
- `crontab` - For scheduled execution

### Optional
- `nmap` - For SSH port checking
- `noip2` - For dynamic DNS management with NOIP

Install dependencies:
```bash
sudo apt install ssmtp jq bc curl nmap
```

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/tachyontec/storjMailAlert
cd storjMailAlert
```

### 2. Run setup

```bash
chmod +x  .sh
./setup.sh
```

The setup wizard will guide you through:
- Email configuration
- Check intervals and thresholds
- Node operator mode selection
- Feature toggles
- Cron job installation

**Alternative:** Manually copy and edit the configuration files:
```bash
cp config/config.env.example config.env
cp config/nodes.json.example nodes.json
# Edit config.env and nodes.json with your settings
```


### 3. Configure your nodes

Edit `nodes.json` with your node details:

```json
{
  "servers": [
    {
      "name": "MyServerNode",
      "host": "myservernode.ddns.net",
      "sshPort": 22,
      "nodes": [
        { "port": 14002 }
      ]
    },
    {
      "name": "MyMultiNode",
      "host": "mymultinode.ddns.net",
      "sshPort": 22,
      "nodes": [
        { "port": 14002 },
        { "port": 14003, "containerName": "my-custom-node", "mountPoint": "/mnt/my-data" }
      ]
    }
  ]
}
```

**Server fields:**
- `name` - Hostname identifier (should match `/etc/hostname` for self-repair)
- `host` - Domain or IP address
- `sshPort` - SSH port for host-level checks

**Node fields (per-node within a server):**
- `port` - **(required)** Node dashboard port to check
- `containerName` - *(optional)* Docker container name. Falls back to naming convention if omitted.
- `mountPoint` - *(optional)* Disk mount path. Falls back to naming convention if omitted.

### 4. Test manually

```bash
./run_checks.sh
# Or wait for the cron job to run automatically
```

## Project Structure
```
storjMailAlert/
├── ansible/
│   ├── generated/                # Generated configs (git-ignored)
│   ├── roles/
│   │   └── storjMailAlert/
│   │       ├── defaults/main.yml # Role default variables
│   │       └── tasks/main.yml    # Deployment tasks
│   ├── inventory.ini.example     # Inventory template
│   └── playbook.yml              # Ansible playbook
├── config/
│   ├── config.env.example        # Configuration template
│   └── nodes.json.example        # Nodes list template
├── lib/
│   ├── common.sh                 # Shared functions
│   └── self_repair.sh            # Self-repair functions
├── checks/
│   ├── check_logs.sh             # Docker log analysis
│   ├── check_nodes.sh            # Node HTTP status
│   ├── check_disks.sh            # Disk mount checker
│   └── check_noip.sh             # Dynamic DNS checker
├── logs/                         # Log output directory
├── tmp/                          # Temporary files
├── config.env                    # Your configuration (git-ignored)
├── nodes.json                    # Your nodes list (git-ignored)
├── run_checks.sh                 # Main entry point
├── setup.sh                      # Single-node setup wizard
├── setup-multi.sh                # Multi-node Ansible setup wizard
└── README.md
```

## Configuration

### config.env

| Variable | Description | Default |
|----------|-------------|---------|
| `ALERT_EMAIL` | Email to receive alerts | (required) |
| `CHECK_INTERVAL` | Minutes between checks | `15` |
| `ERROR_PERCENT_THRESHOLD` | Error % to trigger alert | `5` |
| `IS_NODE_OPERATOR` | Enable local checks/repair | `true` |
| `ENABLE_LOG_CHECK` | Check docker logs | `true` |
| `ENABLE_NODE_CHECK` | Check node HTTP status | `true` |
| `ENABLE_DISK_CHECK` | Check disk mounts | `true` |
| `ENABLE_NOIP_CHECK` | Check NOIP DNS | `false` |
| `CONTAINER_PREFIX` | Docker container prefix | `storagenode` |
| `DEBUG` | Enable debug logging | `false` |

### Naming Conventions

By default, StorjMailAlert expects the following naming pattern for Docker containers and disk mount points:

| Node # | Container Name | Mount Point |
|--------|---------------|-------------|
| 1st | `storagenode` | `/mnt/storj` |
| 2nd | `storagenode2` | `/mnt/storj2` |
| 3rd | `storagenode3` | `/mnt/storj3` |
| Nth | `storagenodeN` | `/mnt/storjN` |

- The **first node** has no numeric suffix (e.g. `storagenode`, `/mnt/storj`)
- All **subsequent nodes** append their index (e.g. `storagenode2`, `/mnt/storj2`)
- The container prefix is configurable via `CONTAINER_PREFIX` (default: `storagenode`)

>It is highly recommended to follow this convention for simplicity. However, custom names can be specified as needed.

**Default example:**
```json{
  "nodes": [
    { "port": 14002 },          // uses storagenode, /mnt/storj
    { "port": 14003 }           // uses storagenode2, /mnt/storj2
  ]
}
```

**Custom names:** If the default convention doesn't match your setup, you can override the container name and mount point per node in `nodes.json` using the optional `containerName` and `mountPoint` fields:

```json
{
  "nodes": [
    { "port": 14002 }, // uses storagenode, /mnt/storj
    { "port": 14003, "containerName": "my-node-2", "mountPoint": "/mnt/my-data" }
  ]
}
```

When these fields are omitted, the default convention is used. When provided, they take priority. Self-repair, log checks, and disk checks all respect custom names.

### Feature Matrix

| Feature | IS_NODE_OPERATOR=true | IS_NODE_OPERATOR=false |
|---------|----------------------|------------------------|
| Log Check | Runs | Skipped |
| Disk Check | Runs | Skipped |
| Node Check | Runs + self-repair | Runs (HTTP only) |
| NOIP Check | Runs + auto-restart | Check only |

## Usage

### Run all enabled checks
```bash
./run_checks.sh
```

### Run specific check
```bash
./run_checks.sh --check logs
./run_checks.sh --check nodes
./run_checks.sh --check disks
./run_checks.sh --check noip
```

### View logs
```bash
tail -f logs/storjMailAlert.log
tail -f logs/cron.log
```

### Reconfigure
```bash
./setup.sh
```

## Multi-Node Setup Example

### Scenario: 3 Raspberry Pis running Storj nodes

**On each Pi (node operator mode):**
```bash
# config.env
ALERT_EMAIL="you@example.com"
IS_NODE_OPERATOR=true
ENABLE_LOG_CHECK=true
ENABLE_NODE_CHECK=true
ENABLE_DISK_CHECK=true
```

Each Pi monitors itself with full self-repair capabilities.

### Scenario: Central monitoring server

**On a separate VPS (monitor-only mode):**
```bash
# config.env
ALERT_EMAIL="you@example.com"
IS_NODE_OPERATOR=false
ENABLE_LOG_CHECK=false
ENABLE_NODE_CHECK=true
ENABLE_DISK_CHECK=false
```

```json
// nodes.json - monitors all your nodes remotely
{
  "servers": [
    {"name": "storjNode1", "host": "storjNode1.ddns.net", "sshPort": 22, "nodes": [{"port": 14002}]},
    {"name": "storjNode2", "host": "storjNode2.ddns.net", "sshPort": 22, "nodes": [{"port": 14002}]},
    {"name": "storjNode3", "host": "storjNode3.ddns.net", "sshPort": 22, "nodes": [{"port": 14002}, {"port": 14003}]}
  ]
}
```

## Multi-Node Deployment with Ansible

For operators running Storj nodes across multiple machines, StorjMailAlert includes an Ansible-based deployment system. A single setup wizard collects all node information, generates configuration files, and deploys to every machine automatically.

All nodes receive the same `nodes.json`, so every node monitors every other node via HTTP checks while also performing local checks (docker logs, disk mounts, self-repair) on itself.

### Prerequisites

- **Ansible** installed on the control machine (the machine you run setup from)
  ```bash
  # Install via pip (recommended)
  pip install ansible

  # Or via apt
  sudo apt install ansible
  ```
- **SSH public key authentication** to all target machines (recommended)

### SSH Key Setup

Set up passwordless SSH access to all your nodes:

```bash
# Generate a key pair (if you don't have one)
ssh-keygen -t ed25519

# Copy your public key to each node
ssh-copy-id user@node1.ddns.net
ssh-copy-id user@node2.ddns.net
ssh-copy-id user@node3.ddns.net

# Verify you can connect without a password
ssh user@node1.ddns.net hostname
```

### Quick Start

```bash
# Run the multi-node setup wizard
chmod +x setup-multi.sh
./setup-multi.sh
```

The wizard will:
1. Collect common settings (email, check interval, thresholds, feature toggles)
2. Collect server and node details for each machine
3. Generate per-host `config.env` files, a shared `nodes.json`, and an Ansible inventory
4. Optionally run the Ansible playbook to deploy everything

### Manual Deployment

If you prefer to run the playbook separately or re-deploy after changes:

```bash
# Dry run (shows what would change without modifying anything)
ansible-playbook ansible/playbook.yml -i ansible/inventory.ini --check

# Full deployment
ansible-playbook ansible/playbook.yml -i ansible/inventory.ini

# Deploy to a specific host only
ansible-playbook ansible/playbook.yml -i ansible/inventory.ini --limit node1
```

### Control Machine as a Node

If the machine you're running the setup from is also a Storj node, the wizard will ask if each server is the current machine. When you answer yes, it sets `ansible_connection=local` in the inventory so Ansible deploys to that host directly without SSH.

### What the Playbook Does

On each target host, the Ansible playbook will:
1. Install dependencies (`ssmtp`, `jq`, `bc`, `curl`)
2. Clone or update the StorjMailAlert repository to `~/storjMailAlert`
3. Copy the shared `nodes.json`
4. Copy the host-specific `config.env`
5. Set file permissions
6. Install the cron job
7. Run a smoke test to verify the installation

### Updating

To update StorjMailAlert on all nodes after pulling new changes or modifying configuration:

```bash
# Re-run the playbook (pulls latest code, re-deploys configs)
ansible-playbook ansible/playbook.yml -i ansible/inventory.ini
```

To reconfigure from scratch:
```bash
./setup-multi.sh
```

### Manual Ansible Setup

If you prefer not to use `setup-multi.sh`, you can create the files manually:

1. Copy `ansible/inventory.ini.example` to `ansible/inventory.ini` and add your hosts
2. Create `ansible/generated/nodes.json` with your node list
3. Create `ansible/generated/<hostname>/config.env` for each host
4. Run the playbook:
   ```bash
   ansible-playbook ansible/playbook.yml -i ansible/inventory.ini
   ```

## Troubleshooting

### No emails received
1. Check ssmtp configuration: `/etc/ssmtp/ssmtp.conf`
2. Test ssmtp: `echo "test" | ssmtp your@email.com`
3. Check logs: `tail logs/storjMailAlert.log`

### Checks not running
1. Verify cron is installed: `crontab -l`
2. Check cron logs: `grep CRON /var/log/syslog`
3. Run manually: `./run_checks.sh`

### Permission errors
```bash
chmod +x run_checks.sh setup.sh
chmod +x checks/*.sh lib/*.sh
```

### Docker logs access denied
By default, Docker requires root privileges to access logs. If you are running the script as a non-root user, add your user to the docker group:
```bash
sudo usermod -aG docker $USER
```

## License

MIT License

## Contributing

Pull requests welcome! Please ensure your changes:
- Follow the existing code style
- Include appropriate error handling
- Update documentation as needed
- Use descriptive commit messages
- Branch names should follow conventions:
  - `feature/your-feature-name`
  - `fix/your-bugfix-name`
  - `docs/update-readme`

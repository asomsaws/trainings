# Bash Scripts

This directory contains bash scripts for Linux system administration and automation tasks.

## Available Scripts

### User Management

#### `create-sudo-user.sh`
Creates a new user account and grants sudo privileges.

**Usage:**
```bash
sudo ./create-sudo-user.sh <username>
```

**Features:**
- Validates username format
- Creates user with home directory and bash shell
- Interactive password setup
- Auto-detects distribution (Debian/Ubuntu vs RHEL/CentOS)
- Adds user to appropriate sudo group (sudo/wheel)
- Falls back to `/etc/sudoers.d/` configuration if needed
- Validates sudoers file before applying
- Verifies sudo access after creation

**Requirements:**
- Must be run as root or with sudo
- Standard Linux user management tools (useradd, usermod, passwd)

**Example:**
```bash
sudo ./create-sudo-user.sh john
```

---

### SSH Key Management

#### `setup-ssh-keypair.sh`
Generates SSH key pairs and configures key-based authentication on remote Linux hosts.

**Usage:**
```bash
./setup-ssh-keypair.sh [OPTIONS] <user@remote_host>
```

**Options:**
- `-t TYPE` - Key type: rsa, ed25519 (default), ecdsa
- `-b BITS` - Key size for RSA (default: 4096)
- `-n NAME` - Custom key name (default: id_<type>)
- `-c COMMENT` - Custom key comment (default: user@host_date)
- `-h` - Display help message

**Features:**
- Generates secure SSH key pairs (ed25519 by default)
- Copies public key to remote host using ssh-copy-id
- Tests key-based authentication automatically
- Optionally adds host to SSH config with alias
- Handles existing keys gracefully
- Sets proper file permissions (600 for private, 644 for public)
- Provides security reminders for hardening SSH

**Requirements:**
- ssh, ssh-keygen, ssh-copy-id
- Network access to remote host
- Password authentication initially enabled on remote host

**Examples:**
```bash
# Generate ed25519 key and setup on remote host
./setup-ssh-keypair.sh user@192.168.1.100

# Generate 4096-bit RSA key with custom name
./setup-ssh-keypair.sh -t rsa -b 4096 -n myserver_key admin@server.example.com

# Generate key with custom comment
./setup-ssh-keypair.sh -c "deploy_key_2025" deploy@10.0.0.50
```

---

### System Auditing

#### `linux-audit.sh`
Performs comprehensive security and configuration audit on remote Linux hosts via SSH, storing all results locally.

**Usage:**
```bash
./linux-audit.sh <user@remote_host> [ssh_key_path]
```

**Features:**
- Connects to remote host via SSH and collects audit data
- All output saved locally in `audit/<remote_ip>/` directory
- Collects comprehensive system information:
  - System and hardware details
  - User accounts and password hashes (requires sudo)
  - Network configuration and active connections
  - Installed packages and running services
  - Firewall rules and SSH configuration
  - Scheduled tasks (cron jobs)
  - Critical file permissions and SUID/SGID files
  - Disk usage and mounted filesystems
  - Running processes
- Generates summary report with audit metadata
- Color-coded progress output

**Requirements:**
- SSH access to remote host
- Sudo privileges on remote host (for sensitive data)
- Standard Linux utilities (most are built-in)

**Output Structure:**
```
audit/<remote_ip>/
├── system_info.txt
├── users.txt
├── password_hashes.txt
├── network_config.txt
├── network_connections.txt
├── installed_packages.txt
├── services.txt
├── firewall_rules.txt
├── ssh_config.txt
├── cron_jobs.txt
├── file_permissions.txt
├── disk_usage.txt
├── process_list.txt
└── audit_summary.txt
```

**Examples:**
```bash
# Basic audit using default SSH credentials
./linux-audit.sh root@192.168.1.100

# Audit using specific SSH key
./linux-audit.sh admin@server.example.com ~/.ssh/id_rsa

# Audit with custom key name
./linux-audit.sh user@10.0.0.50 ~/.ssh/audit_key
```

**Security Notes:**
- Password hashes are collected from `/etc/shadow` (requires sudo)
- All data is stored locally on the auditing workstation
- Review and secure audit output appropriately
- Sensitive data includes passwords, SSH keys, and system configurations

---

### Jump Host / Multi-Hop Access

#### `ssh-jump-exec.sh`
Execute commands and scripts on remote hosts through SSH jump hosts (bastion hosts) without installing anything on intermediate hosts.

**Usage:**
```bash
./ssh-jump-exec.sh -j jumphost1[,jumphost2,...] -t target -c "command"
./ssh-jump-exec.sh -j jumphost -t target -s script.sh
```

**Features:**
- Execute commands through single or multiple jump hosts
- Upload and execute local scripts on remote targets
- Uses native SSH ProxyJump (OpenSSH 7.3+)
- No software installation required on jump hosts
- Automatic cleanup of temporary files
- Support for custom SSH keys and ports
- Verbose mode for debugging

**Requirements:**
- OpenSSH 7.3+ (for ProxyJump support)
- SSH access through the entire chain
- Each jump host must be able to reach the next hop

**Output Management:**
- By default, all command/script output is saved to `audit/<target_ip>/<command>-<timestamp>.txt`
- Command name is extracted from the executed command (e.g., nmap, ps, df)
- Each execution creates a timestamped file on your local workstation
- Output includes full headers with execution metadata
- Use `-n` flag to display only (no save)

**Examples:**
```bash
# Execute command through single jump (output auto-saved)
./ssh-jump-exec.sh -j root@kali -t user@internal-vm -c "nmap -sn 192.168.1.0/24"
# Saves to: audit/192.168.1.100/nmap-20251203-145030.txt

# Multiple jump hosts
./ssh-jump-exec.sh -j user@kali,admin@internal-vm -t root@target -c "hostname -I"

# Upload and execute script (output auto-saved)
./ssh-jump-exec.sh -j root@kali -t user@scanner -s ./linux-audit.sh
# Saves to: audit/<scanner_ip>/script-linux-audit.sh-<timestamp>.txt

# Display only, don't save output
./ssh-jump-exec.sh -j root@kali -t user@target -c "whoami" -n

# With SSH key
./ssh-jump-exec.sh -j root@kali -t user@target -k ~/.ssh/id_rsa -c "df -h"

# Keep uploaded script on target
./ssh-jump-exec.sh -j root@kali -t user@target -s ./script.sh -u
```

**Output Structure:**
```
audit/
├── 192.168.1.100/
│   ├── nmap-20251203-145030.txt
│   ├── ps-20251203-150215.txt
│   └── script-linux-audit.sh-20251203-151000.txt
└── 192.168.2.50/
    ├── df-20251203-152030.txt
    ├── nmap-20251203-152500.txt
    └── script-nmap-scan.sh-20251203-153000.txt
```

#### `setup-jump-config.sh`
Interactive SSH configuration generator for jump host chains and helper functions.

**Usage:**
```bash
./setup-jump-config.sh
```

**Features:**
- Interactive configuration wizard
- Generates SSH config with ProxyJump settings
- Creates host aliases for easy access
- Backs up existing SSH config
- Generates helper shell functions
- Provides usage examples
- Creates ProxyCommand examples for older SSH versions

**Generated Capabilities:**
- Simple host aliases (e.g., `ssh kali-jump`, `ssh internal-vm`)
- Automatic jump chain traversal
- Wildcard host patterns for network ranges
- Port forwarding configurations
- SOCKS proxy setup

**After Setup:**
```bash
# Connect using aliases
ssh internal-vm

# Execute commands
ssh internal-vm 'nmap -sn 192.168.1.0/24'

# Copy files
scp file.txt internal-vm:/tmp/

# Access deeper hosts
ssh internal-192.168.2.50  # Automatically uses ProxyJump chain
```

**Cyber Polygon Scenario:**
```
Your Workstation → Kali Jump → Internal VM → Target Network
```

The script configures seamless access through this entire chain.

---

#### `ssh-router.sh`
Intelligent SSH routing with automatic jump chain selection based on network topology and CIDR matching.

**Usage:**
```bash
./ssh-router.sh -r routes.conf -t target -c "command"
```

**Features:**
- Automatic route selection based on destination network (CIDR matching)
- Define multiple network segments with different jump chains
- Support for complex multi-hop topologies
- Direct access configuration for some networks
- Default route fallback
- Route listing and connectivity testing
- Same output management as ssh-jump-exec.sh

**Perfect for scenarios where:**
- Different internal networks require different jump paths
- VMs have multiple network adapters on different subnets
- Complex network segmentation (DMZ, management, internal)
- Need to maintain routing table for entire infrastructure

**Routes Configuration File (ssh-routes.conf):**
```conf
# Network segments with their jump chains
192.168.1.0/24 via root@kali,admin@vm1
192.168.2.0/24 via root@kali,admin@vm2
10.0.5.0/24 via root@kali,user@vm3
172.16.0.0/16 via root@kali,admin@gateway1,root@gateway2
10.10.0.0/16 via direct
default via root@kali
```

**Examples:**
```bash
# Auto-select route based on target IP
./ssh-router.sh -r routes.conf -t root@192.168.1.50 -c "hostname"
# Automatically uses: root@kali,admin@vm1

./ssh-router.sh -r routes.conf -t user@10.0.5.100 -s ./audit.sh
# Automatically uses: root@kali,user@vm3

# List all configured routes
./ssh-router.sh -r routes.conf -l

# Test connectivity to specific target
./ssh-router.sh -r routes.conf -t 192.168.2.75 -c "echo test"
```

**Cyber Polygon Scenario:**
```
Your Workstation
    └─> Kali (203.0.113.10)
        ├─> VM1 (192.168.1.10) ──> 192.168.1.0/24 network
        ├─> VM2 (192.168.2.10) ──> 192.168.2.0/24 network  
        ├─> VM3 (10.0.5.1) ──────> 10.0.5.0/24 network
        └─> VM4 (172.16.1.1) ───> 172.16.0.0/16 network
```

The router automatically selects the correct path based on target IP.

#### `generate-routes.sh`
Interactive tool to create SSH routes configuration files.

**Usage:**
```bash
./generate-routes.sh [-o routes.conf]
```

**Features:**
- Interactive prompts for network configuration
- Validates CIDR format
- Supports multi-hop chains
- Creates properly formatted routes file
- Helpful for initial setup or documentation

---

### Jump Host Documentation

See **[JUMP-HOSTS.md](JUMP-HOSTS.md)** for comprehensive guide including:
- Native SSH ProxyJump usage
- ProxyChains integration (for tools like nmap)
- SOCKS proxy setup for any TCP tool
- Port forwarding through jump chains
- Practical examples and troubleshooting
- Comparison: ProxyJump vs ProxyChains
- Security considerations

**Quick Reference:**
```bash
# Direct SSH ProxyJump
ssh -J user@kali user@internal-vm 'command'

# SOCKS proxy for proxychains
ssh -D 1080 -J user@kali user@internal-vm -N
proxychains nmap -sn 192.168.1.0/24
```

---

## General Notes

- All scripts include comprehensive error handling
- Color-coded output for better readability
- Scripts follow bash best practices with `set -euo pipefail`
- Each script includes usage instructions and validation

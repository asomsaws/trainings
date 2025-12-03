#!/usr/bin/env bash
# Description: Comprehensive Linux system audit script via SSH
# Usage: ./linux-audit.sh <remote_user@remote_host> [ssh_key_path]
# Dependencies: ssh, sudo access on remote host

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AUDIT_BASE_DIR="./audit"
SSH_OPTIONS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 <remote_user@remote_host> [ssh_key_path]

Performs comprehensive security audit on remote Linux host via SSH.
All audit data is collected and stored locally in audit/<ip>/ directory.

ARGUMENTS:
    remote_user@remote_host    Remote host to audit
    ssh_key_path              Optional: Path to SSH private key

EXAMPLES:
    $0 admin@192.168.1.100
    $0 root@server.example.com ~/.ssh/id_rsa
    $0 user@10.0.0.50 ~/.ssh/myserver_key

OUTPUT:
    All audit results are saved to: audit/<remote_ip>/
    - system_info.txt         : System and hardware information
    - users.txt               : User accounts and groups
    - password_hashes.txt     : Password hashes from /etc/shadow
    - network_config.txt      : Network configuration and routing
    - network_connections.txt : Active network connections
    - installed_packages.txt  : Installed software packages
    - services.txt            : Running services
    - firewall_rules.txt      : Firewall configuration
    - ssh_config.txt          : SSH server configuration
    - cron_jobs.txt           : Scheduled tasks
    - file_permissions.txt    : Critical file permissions
    - disk_usage.txt          : Disk space and mounts
    - process_list.txt        : Running processes
    - audit_summary.txt       : Summary report

EOF
    exit 1
}

# Check arguments
if [[ $# -eq 0 ]]; then
    echo -e "${RED}Error: Remote host not provided${NC}"
    usage
fi

REMOTE_HOST=$1
SSH_KEY=""

if [[ $# -ge 2 ]]; then
    SSH_KEY=$2
    if [[ ! -f "$SSH_KEY" ]]; then
        echo -e "${RED}Error: SSH key file not found: $SSH_KEY${NC}"
        exit 1
    fi
    SSH_OPTIONS="$SSH_OPTIONS -i $SSH_KEY"
fi

# Extract IP or hostname for directory naming
REMOTE_USER="${REMOTE_HOST%@*}"
REMOTE_ADDR="${REMOTE_HOST#*@}"

# Test SSH connection
echo -e "${BLUE}Testing SSH connection to $REMOTE_HOST...${NC}"
if ! ssh $SSH_OPTIONS "$REMOTE_HOST" "echo 'Connection successful'" &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to $REMOTE_HOST${NC}"
    echo "Please verify:"
    echo "  - Host is reachable"
    echo "  - SSH credentials are correct"
    echo "  - SSH service is running on remote host"
    exit 1
fi
echo -e "${GREEN}Connection successful${NC}"

# Get actual IP address
REMOTE_IP=$(ssh $SSH_OPTIONS "$REMOTE_HOST" "hostname -I | awk '{print \$1}'" 2>/dev/null || echo "$REMOTE_ADDR")
REMOTE_IP=$(echo "$REMOTE_IP" | tr -d '[:space:]')

# Create audit directory
AUDIT_DIR="$AUDIT_BASE_DIR/$REMOTE_IP"
mkdir -p "$AUDIT_DIR"
echo -e "${GREEN}Audit directory created: $AUDIT_DIR${NC}"

# Timestamp
AUDIT_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
echo -e "${BLUE}Starting audit at $AUDIT_TIMESTAMP${NC}\n"

# Function to run command on remote host and save output
audit_collect() {
    local description=$1
    local output_file=$2
    local command=$3
    local require_sudo=${4:-false}
    
    echo -e "${YELLOW}Collecting: $description${NC}"
    
    {
        echo "============================================"
        echo "$description"
        echo "============================================"
        echo "Collected: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Remote Host: $REMOTE_HOST"
        echo "Remote IP: $REMOTE_IP"
        echo ""
        
        if [[ "$require_sudo" == "true" ]]; then
            ssh $SSH_OPTIONS "$REMOTE_HOST" "sudo bash -c '$command'" 2>&1 || echo "Error: Command failed or insufficient permissions"
        else
            ssh $SSH_OPTIONS "$REMOTE_HOST" "$command" 2>&1 || echo "Error: Command failed"
        fi
        
        echo ""
    } > "$AUDIT_DIR/$output_file"
    
    echo -e "${GREEN}✓ Saved to $output_file${NC}"
}

# Start audit collection
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Linux System Audit${NC}"
echo -e "${GREEN}  Target: $REMOTE_HOST ($REMOTE_IP)${NC}"
echo -e "${GREEN}========================================${NC}\n"

# System Information
audit_collect "System Information" "system_info.txt" \
    "echo '--- Hostname ---' && hostname && echo -e '\n--- OS Release ---' && cat /etc/os-release && echo -e '\n--- Kernel Version ---' && uname -a && echo -e '\n--- Uptime ---' && uptime && echo -e '\n--- CPU Info ---' && lscpu | head -20 && echo -e '\n--- Memory Info ---' && free -h && echo -e '\n--- DMI/Hardware ---' && sudo dmidecode -t system 2>/dev/null | head -30 || echo 'dmidecode not available or requires sudo'" \
    false

# User Accounts
audit_collect "User Accounts and Groups" "users.txt" \
    "echo '--- /etc/passwd ---' && cat /etc/passwd && echo -e '\n--- /etc/group ---' && cat /etc/group && echo -e '\n--- Users with Login Shell ---' && grep -v 'nologin\|false' /etc/passwd && echo -e '\n--- Sudo Group Members ---' && getent group sudo 2>/dev/null || getent group wheel 2>/dev/null || echo 'No sudo/wheel group found' && echo -e '\n--- Recently Logged in Users ---' && last -n 20 2>/dev/null || echo 'last command not available' && echo -e '\n--- Currently Logged in Users ---' && w 2>/dev/null || who" \
    false

# Password Hashes (requires sudo)
audit_collect "Password Hashes" "password_hashes.txt" \
    "cat /etc/shadow" \
    true

# Network Configuration
audit_collect "Network Configuration" "network_config.txt" \
    "echo '--- IP Addresses ---' && ip addr show || ifconfig && echo -e '\n--- Routing Table ---' && ip route show || route -n && echo -e '\n--- DNS Configuration ---' && cat /etc/resolv.conf && echo -e '\n--- Hosts File ---' && cat /etc/hosts && echo -e '\n--- Network Interfaces ---' && ls -la /etc/network/interfaces* /etc/sysconfig/network-scripts/ifcfg-* 2>/dev/null || echo 'Network config files not found in standard locations'" \
    false

# Network Connections
audit_collect "Active Network Connections" "network_connections.txt" \
    "echo '--- Active Connections ---' && ss -tunap 2>/dev/null || netstat -tunap 2>/dev/null || echo 'ss/netstat not available or requires sudo' && echo -e '\n--- Listening Ports ---' && ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null" \
    false

# Installed Packages
audit_collect "Installed Packages" "installed_packages.txt" \
    "if command -v dpkg &>/dev/null; then echo '--- DPKG Packages ---' && dpkg -l; elif command -v rpm &>/dev/null; then echo '--- RPM Packages ---' && rpm -qa; else echo 'No supported package manager found'; fi" \
    false

# Running Services
audit_collect "Running Services" "services.txt" \
    "echo '--- Systemd Services ---' && systemctl list-units --type=service --state=running 2>/dev/null || echo 'systemd not available' && echo -e '\n--- All Services Status ---' && systemctl list-units --type=service --all 2>/dev/null || service --status-all 2>/dev/null || echo 'Cannot list services' && echo -e '\n--- Enabled Services ---' && systemctl list-unit-files --type=service --state=enabled 2>/dev/null || echo 'Cannot list enabled services'" \
    false

# Firewall Rules
audit_collect "Firewall Configuration" "firewall_rules.txt" \
    "echo '--- IPTables Rules ---' && sudo iptables -L -n -v 2>/dev/null || echo 'iptables not available or requires sudo' && echo -e '\n--- UFW Status ---' && sudo ufw status verbose 2>/dev/null || echo 'ufw not installed' && echo -e '\n--- Firewalld Status ---' && sudo firewall-cmd --list-all 2>/dev/null || echo 'firewalld not installed'" \
    true

# SSH Configuration
audit_collect "SSH Server Configuration" "ssh_config.txt" \
    "echo '--- SSHD Config ---' && sudo cat /etc/ssh/sshd_config 2>/dev/null || echo 'Cannot read sshd_config' && echo -e '\n--- SSH Client Config ---' && cat /etc/ssh/ssh_config 2>/dev/null || echo 'Cannot read ssh_config' && echo -e '\n--- Authorized Keys (Current User) ---' && cat ~/.ssh/authorized_keys 2>/dev/null || echo 'No authorized_keys found'" \
    true

# Cron Jobs
audit_collect "Scheduled Tasks (Cron)" "cron_jobs.txt" \
    "echo '--- User Crontabs ---' && for user in \$(cut -f1 -d: /etc/passwd); do echo \"Crontab for \$user:\" && sudo crontab -u \$user -l 2>/dev/null || echo 'No crontab'; echo ''; done && echo -e '\n--- System Crontabs ---' && ls -la /etc/cron* && echo -e '\n--- /etc/crontab ---' && cat /etc/crontab 2>/dev/null || echo 'No /etc/crontab'" \
    true

# File Permissions on Critical Files
audit_collect "Critical File Permissions" "file_permissions.txt" \
    "echo '--- Critical System Files ---' && ls -la /etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers 2>/dev/null || echo 'Some files not accessible' && echo -e '\n--- SSH Directory Permissions ---' && ls -la /etc/ssh/ 2>/dev/null && echo -e '\n--- Sudoers.d Directory ---' && sudo ls -la /etc/sudoers.d/ 2>/dev/null || echo 'Cannot access sudoers.d' && echo -e '\n--- SUID/SGID Files (sample) ---' && sudo find / -type f \( -perm -4000 -o -perm -2000 \) -ls 2>/dev/null | head -50 || echo 'Cannot search for SUID/SGID files'" \
    true

# Disk Usage
audit_collect "Disk Usage and Mounts" "disk_usage.txt" \
    "echo '--- Disk Space ---' && df -h && echo -e '\n--- Mounted Filesystems ---' && mount && echo -e '\n--- /etc/fstab ---' && cat /etc/fstab 2>/dev/null || echo 'Cannot read fstab' && echo -e '\n--- Block Devices ---' && lsblk 2>/dev/null || echo 'lsblk not available'" \
    false

# Running Processes
audit_collect "Running Processes" "process_list.txt" \
    "echo '--- Process Tree ---' && ps auxf 2>/dev/null || ps aux && echo -e '\n--- Top Processes by CPU ---' && ps aux --sort=-%cpu | head -20 && echo -e '\n--- Top Processes by Memory ---' && ps aux --sort=-%mem | head -20" \
    false

# Generate Summary Report
echo -e "\n${BLUE}Generating audit summary...${NC}"

{
    echo "============================================"
    echo "Linux System Audit Summary"
    echo "============================================"
    echo "Audit Date: $AUDIT_TIMESTAMP"
    echo "Remote Host: $REMOTE_HOST"
    echo "Remote IP: $REMOTE_IP"
    echo "Audited By: $USER@$(hostname)"
    echo ""
    echo "Audit Files Generated:"
    echo "--------------------------------------------"
    ls -lh "$AUDIT_DIR" | tail -n +2
    echo ""
    echo "--------------------------------------------"
    echo "Total Audit Files: $(ls -1 "$AUDIT_DIR" | wc -l)"
    echo "Audit Directory Size: $(du -sh "$AUDIT_DIR" | cut -f1)"
    echo ""
    echo "Review individual files for detailed information:"
    for file in "$AUDIT_DIR"/*.txt; do
        [[ -f "$file" ]] && echo "  - $(basename "$file")"
    done
    echo ""
    echo "============================================"
} > "$AUDIT_DIR/audit_summary.txt"

# Display completion message
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Audit Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Audit results saved to: ${BLUE}$AUDIT_DIR${NC}"
echo -e "Summary report: ${BLUE}$AUDIT_DIR/audit_summary.txt${NC}"
echo -e "\nTo review the summary:"
echo -e "  ${YELLOW}cat $AUDIT_DIR/audit_summary.txt${NC}"
echo -e "\nTo browse all files:"
echo -e "  ${YELLOW}ls -lh $AUDIT_DIR${NC}"
echo ""

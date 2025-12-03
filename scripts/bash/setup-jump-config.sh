#!/usr/bin/env bash
# Description: Setup SSH config for jump host chains and generate helper commands
# Usage: ./setup-jump-config.sh
# Dependencies: ssh

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SSH_CONFIG="$HOME/.ssh/config"
BACKUP_CONFIG="${SSH_CONFIG}.backup.$(date +%s)"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  SSH Jump Host Configuration${NC}"
echo -e "${CYAN}========================================${NC}\n"

# Function to add host configuration
add_host_config() {
    local host_alias=$1
    local hostname=$2
    local user=$3
    local port=${4:-22}
    local proxy_jump=${5:-}
    local identity_file=${6:-}
    
    cat << EOF

# $host_alias - Added by setup-jump-config.sh on $(date)
Host $host_alias
    HostName $hostname
    User $user
    Port $port
EOF
    
    if [[ -n "$proxy_jump" ]]; then
        echo "    ProxyJump $proxy_jump"
    fi
    
    if [[ -n "$identity_file" ]]; then
        echo "    IdentityFile $identity_file"
    fi
    
    cat << EOF
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
}

# Interactive configuration
echo -e "${YELLOW}This script will help you configure SSH jump host chains.${NC}\n"

# Backup existing config
if [[ -f "$SSH_CONFIG" ]]; then
    echo -e "${YELLOW}Backing up existing SSH config...${NC}"
    cp "$SSH_CONFIG" "$BACKUP_CONFIG"
    echo -e "${GREEN}✓ Backup created: $BACKUP_CONFIG${NC}\n"
fi

# Create .ssh directory if it doesn't exist
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Example configuration for cyber polygon scenario
echo -e "${BLUE}Creating example configuration for cyber polygon scenario...${NC}\n"

# Ask for configuration details
read -p "Enter Kali jump host (e.g., kali.cyberpolygon.com or IP): " KALI_HOST
read -p "Enter Kali username: " KALI_USER
read -p "Enter Kali SSH port [22]: " KALI_PORT
KALI_PORT=${KALI_PORT:-22}

echo ""
read -p "Enter internal VM host (e.g., 192.168.1.100): " VM_HOST
read -p "Enter internal VM username: " VM_USER
read -p "Enter internal VM SSH port [22]: " VM_PORT
VM_PORT=${VM_PORT:-22}

echo ""
read -p "Enter SSH key path (optional, press Enter to skip): " SSH_KEY

echo -e "\n${YELLOW}Generating SSH config...${NC}\n"

# Generate configuration
CONFIG_CONTENT=$(cat << EOF
# ========================================
# Cyber Polygon Jump Host Configuration
# Generated: $(date)
# ========================================

# Jump Host: Kali on Cyber Polygon
Host kali-jump
    HostName $KALI_HOST
    User $KALI_USER
    Port $KALI_PORT
EOF
)

if [[ -n "$SSH_KEY" ]]; then
    CONFIG_CONTENT="$CONFIG_CONTENT
    IdentityFile $SSH_KEY"
fi

CONFIG_CONTENT="$CONFIG_CONTENT
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
    ServerAliveCountMax 3

# Internal VM (through Kali)
Host internal-vm
    HostName $VM_HOST
    User $VM_USER
    Port $VM_PORT
    ProxyJump kali-jump"

if [[ -n "$SSH_KEY" ]]; then
    CONFIG_CONTENT="$CONFIG_CONTENT
    IdentityFile $SSH_KEY"
fi

CONFIG_CONTENT="$CONFIG_CONTENT
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60

# Wildcard for any internal network host through VM
# Usage: ssh internal-<ip> (e.g., ssh internal-192.168.2.50)
Host internal-*
    ProxyJump internal-vm
    User root
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60

# Alternative: Direct multi-hop for specific hosts
# Host target-server
#     HostName 192.168.2.100
#     User admin
#     ProxyJump kali-jump,internal-vm
#     StrictHostKeyChecking accept-new
"

# Append to SSH config
echo "$CONFIG_CONTENT" >> "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

echo -e "${GREEN}✓ SSH config updated${NC}\n"

# Display configuration
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Configuration Summary${NC}"
echo -e "${CYAN}========================================${NC}\n"

echo -e "${BLUE}SSH Config Location:${NC} $SSH_CONFIG"
echo -e "${BLUE}Backup Location:${NC} $BACKUP_CONFIG\n"

echo -e "${YELLOW}Usage Examples:${NC}\n"

echo -e "${GREEN}1. Connect to Kali jump host:${NC}"
echo -e "   ssh kali-jump\n"

echo -e "${GREEN}2. Connect to internal VM (through Kali):${NC}"
echo -e "   ssh internal-vm\n"

echo -e "${GREEN}3. Execute command on internal VM:${NC}"
echo -e "   ssh internal-vm 'hostname -I'\n"

echo -e "${GREEN}4. Copy files to internal VM:${NC}"
echo -e "   scp file.txt internal-vm:/tmp/\n"

echo -e "${GREEN}5. Run nmap on internal network from VM:${NC}"
echo -e "   ssh internal-vm 'nmap -sn 192.168.1.0/24'\n"

echo -e "${GREEN}6. Access hosts beyond internal VM:${NC}"
echo -e "   ssh internal-192.168.2.50  ${YELLOW}# Uses ProxyJump through internal-vm${NC}\n"

echo -e "${GREEN}7. Port forwarding through jump hosts:${NC}"
echo -e "   ssh -L 8080:localhost:80 internal-vm  ${YELLOW}# Forward port through chain${NC}\n"

echo -e "${GREEN}8. SOCKS proxy through jump chain:${NC}"
echo -e "   ssh -D 1080 internal-vm  ${YELLOW}# Create SOCKS proxy${NC}\n"

# Create quick reference script
HELPER_SCRIPT="$HOME/.ssh/jump-helpers.sh"
cat > "$HELPER_SCRIPT" << 'EOFHELPER'
#!/usr/bin/env bash
# Quick helper functions for jump host operations

# Execute command through jump chain
jump-exec() {
    local host=$1
    shift
    local command="$@"
    ssh "$host" "$command"
}

# Copy file through jump chain
jump-copy() {
    local source=$1
    local host=$2
    local dest=$3
    scp "$source" "${host}:${dest}"
}

# Interactive shell through jump
jump-shell() {
    local host=$1
    ssh -t "$host"
}

# Port forward through jump
jump-forward() {
    local local_port=$1
    local remote_host=$2
    local remote_port=$3
    local jump_host=$4
    ssh -L "${local_port}:${remote_host}:${remote_port}" "$jump_host" -N
}

# SOCKS proxy
jump-socks() {
    local port=${1:-1080}
    local jump_host=${2:-internal-vm}
    echo "Starting SOCKS proxy on localhost:$port through $jump_host"
    ssh -D "$port" "$jump_host" -N
}

echo "Jump host helper functions loaded:"
echo "  jump-exec <host> <command>          - Execute command"
echo "  jump-copy <file> <host> <dest>      - Copy file"
echo "  jump-shell <host>                   - Interactive shell"
echo "  jump-forward <lport> <rhost> <rport> <jump> - Port forward"
echo "  jump-socks [port] [jump_host]       - SOCKS proxy"
EOFHELPER

chmod +x "$HELPER_SCRIPT"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Additional Tools${NC}"
echo -e "${CYAN}========================================${NC}\n"

echo -e "${YELLOW}Helper functions created:${NC} $HELPER_SCRIPT"
echo -e "Source it in your shell: ${GREEN}source $HELPER_SCRIPT${NC}\n"

# Create ProxyCommand alternative (for older SSH versions)
PROXYCOMMAND_EXAMPLE="$HOME/.ssh/proxycommand-example.txt"
cat > "$PROXYCOMMAND_EXAMPLE" << 'EOFPROXY'
# Alternative: Using ProxyCommand for older SSH versions
# (If ProxyJump is not available)

Host internal-vm-legacy
    HostName 192.168.1.100
    User admin
    ProxyCommand ssh -W %h:%p kali-jump

Host target-legacy
    HostName 192.168.2.50
    User root
    ProxyCommand ssh -W %h:%p internal-vm-legacy
EOFPROXY

echo -e "${YELLOW}For older SSH versions (< 7.3):${NC} $PROXYCOMMAND_EXAMPLE\n"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}Test your configuration:${NC}"
echo -e "  ssh kali-jump 'echo \"Kali jump host working\"'"
echo -e "  ssh internal-vm 'echo \"Internal VM accessible\"'\n"

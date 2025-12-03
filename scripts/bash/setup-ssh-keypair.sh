#!/usr/bin/env bash
# Description: Generate SSH key pair and configure key-based authentication on remote Linux host
# Usage: ./setup-ssh-keypair.sh <remote_user@remote_host>
# Dependencies: ssh, ssh-keygen, ssh-copy-id

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
KEY_TYPE="ed25519"
KEY_SIZE=""
KEY_COMMENT="${USER}@$(hostname)_$(date +%Y%m%d)"
SSH_DIR="$HOME/.ssh"
KEY_NAME="id_${KEY_TYPE}"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] <remote_user@remote_host>

Generate SSH key pair and configure key-based authentication on remote host.

OPTIONS:
    -t TYPE     Key type (rsa, ed25519, ecdsa). Default: ed25519
    -b BITS     Key size in bits (for RSA: 2048, 4096). Default: 4096 for RSA
    -n NAME     Custom key name. Default: id_<type>
    -c COMMENT  Key comment. Default: user@host_date
    -h          Display this help message

EXAMPLES:
    $0 user@192.168.1.100
    $0 -t rsa -b 4096 admin@server.example.com
    $0 -n myserver_key -t ed25519 deploy@10.0.0.50

EOF
    exit 1
}

# Parse command line options
while getopts "t:b:n:c:h" opt; do
    case $opt in
        t)
            KEY_TYPE="$OPTARG"
            KEY_NAME="id_${KEY_TYPE}"
            ;;
        b)
            KEY_SIZE="$OPTARG"
            ;;
        n)
            KEY_NAME="$OPTARG"
            ;;
        c)
            KEY_COMMENT="$OPTARG"
            ;;
        h)
            usage
            ;;
        \?)
            echo -e "${RED}Invalid option: -$OPTARG${NC}" >&2
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check if remote host is provided
if [[ $# -eq 0 ]]; then
    echo -e "${RED}Error: Remote host not provided${NC}"
    usage
fi

REMOTE_HOST=$1
KEY_PATH="$SSH_DIR/$KEY_NAME"

# Validate key type
case $KEY_TYPE in
    rsa|ed25519|ecdsa)
        ;;
    *)
        echo -e "${RED}Error: Invalid key type '$KEY_TYPE'${NC}"
        echo "Supported types: rsa, ed25519, ecdsa"
        exit 1
        ;;
esac

# Set default key size for RSA if not specified
if [[ "$KEY_TYPE" == "rsa" ]] && [[ -z "$KEY_SIZE" ]]; then
    KEY_SIZE="4096"
fi

# Create .ssh directory if it doesn't exist
if [[ ! -d "$SSH_DIR" ]]; then
    echo -e "${GREEN}Creating SSH directory at $SSH_DIR${NC}"
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi

# Check if key already exists
if [[ -f "$KEY_PATH" ]]; then
    echo -e "${YELLOW}Warning: SSH key already exists at $KEY_PATH${NC}"
    read -p "Do you want to use the existing key? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter a new key name (without path): " NEW_KEY_NAME
        KEY_NAME="$NEW_KEY_NAME"
        KEY_PATH="$SSH_DIR/$KEY_NAME"
        
        if [[ -f "$KEY_PATH" ]]; then
            echo -e "${RED}Error: Key $KEY_PATH already exists${NC}"
            exit 1
        fi
    else
        echo -e "${BLUE}Using existing key: $KEY_PATH${NC}"
        SKIP_KEYGEN=true
    fi
fi

# Generate SSH key pair
if [[ "${SKIP_KEYGEN:-false}" != "true" ]]; then
    echo -e "${GREEN}Generating $KEY_TYPE SSH key pair...${NC}"
    
    if [[ -n "$KEY_SIZE" ]]; then
        ssh-keygen -t "$KEY_TYPE" -b "$KEY_SIZE" -C "$KEY_COMMENT" -f "$KEY_PATH"
    else
        ssh-keygen -t "$KEY_TYPE" -C "$KEY_COMMENT" -f "$KEY_PATH"
    fi
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}SSH key pair generated successfully${NC}"
        echo -e "Private key: ${BLUE}$KEY_PATH${NC}"
        echo -e "Public key:  ${BLUE}${KEY_PATH}.pub${NC}"
        chmod 600 "$KEY_PATH"
        chmod 644 "${KEY_PATH}.pub"
    else
        echo -e "${RED}Error: Failed to generate SSH key pair${NC}"
        exit 1
    fi
fi

# Display public key
echo -e "\n${GREEN}Public Key:${NC}"
cat "${KEY_PATH}.pub"
echo ""

# Copy public key to remote host
echo -e "${GREEN}Copying public key to remote host $REMOTE_HOST${NC}"
echo -e "${YELLOW}You will be prompted for the password of the remote user${NC}"

if command -v ssh-copy-id &>/dev/null; then
    ssh-copy-id -i "${KEY_PATH}.pub" "$REMOTE_HOST"
else
    # Fallback method if ssh-copy-id is not available
    echo -e "${YELLOW}ssh-copy-id not found, using alternative method${NC}"
    cat "${KEY_PATH}.pub" | ssh "$REMOTE_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
fi

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Public key successfully copied to remote host${NC}"
else
    echo -e "${RED}Error: Failed to copy public key to remote host${NC}"
    exit 1
fi

# Test SSH connection
echo -e "\n${GREEN}Testing SSH connection...${NC}"
if ssh -i "$KEY_PATH" -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_HOST" "echo 'SSH key authentication successful'" 2>/dev/null; then
    echo -e "${GREEN}Success! Key-based authentication is working${NC}"
else
    echo -e "${YELLOW}Warning: Could not verify key-based authentication${NC}"
    echo -e "Please try manually: ${BLUE}ssh -i $KEY_PATH $REMOTE_HOST${NC}"
fi

# Add SSH config entry
echo -e "\n${BLUE}Would you like to add this host to your SSH config file?${NC}"
read -p "(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter a host alias (e.g., 'myserver'): " HOST_ALIAS
    
    if [[ -z "$HOST_ALIAS" ]]; then
        echo -e "${YELLOW}No alias provided, skipping SSH config${NC}"
    else
        SSH_CONFIG="$SSH_DIR/config"
        
        cat >> "$SSH_CONFIG" << EOF

# Added by setup-ssh-keypair.sh on $(date)
Host $HOST_ALIAS
    HostName ${REMOTE_HOST#*@}
    User ${REMOTE_HOST%@*}
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
EOF
        
        chmod 600 "$SSH_CONFIG"
        echo -e "${GREEN}SSH config updated. You can now connect using: ${BLUE}ssh $HOST_ALIAS${NC}"
    fi
fi

# Summary
echo -e "\n${GREEN}=== Setup Complete ===${NC}"
echo -e "Key location: ${BLUE}$KEY_PATH${NC}"
echo -e "Connect using: ${BLUE}ssh -i $KEY_PATH $REMOTE_HOST${NC}"
if [[ -n "${HOST_ALIAS:-}" ]]; then
    echo -e "Or simply: ${BLUE}ssh $HOST_ALIAS${NC}"
fi

# Optional: Disable password authentication reminder
echo -e "\n${YELLOW}Security Reminder:${NC}"
echo -e "Consider disabling password authentication on the remote host by:"
echo -e "1. SSH to remote: ${BLUE}ssh -i $KEY_PATH $REMOTE_HOST${NC}"
echo -e "2. Edit sshd_config: ${BLUE}sudo vi /etc/ssh/sshd_config${NC}"
echo -e "3. Set: ${BLUE}PasswordAuthentication no${NC}"
echo -e "4. Restart SSH: ${BLUE}sudo systemctl restart sshd${NC}"

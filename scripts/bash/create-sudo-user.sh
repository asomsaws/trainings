#!/usr/bin/env bash
# Description: Create a new user and add them to the sudoers group
# Usage: sudo ./create-sudo-user.sh <username>
# Dependencies: sudo privileges required

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
   exit 1
fi

# Check if username is provided
if [[ $# -eq 0 ]]; then
    echo -e "${RED}Error: Username not provided${NC}"
    echo "Usage: sudo $0 <username>"
    exit 1
fi

USERNAME=$1

# Validate username format
if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo -e "${RED}Error: Invalid username format${NC}"
    echo "Username must start with a lowercase letter or underscore,"
    echo "followed by lowercase letters, digits, underscores, or hyphens."
    exit 1
fi

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    echo -e "${YELLOW}Warning: User '$USERNAME' already exists${NC}"
    read -p "Do you want to add this user to sudoers? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
else
    # Create the user with a home directory
    echo -e "${GREEN}Creating user '$USERNAME'...${NC}"
    useradd -m -s /bin/bash "$USERNAME"
    
    # Set password for the new user
    echo -e "${GREEN}Setting password for '$USERNAME'${NC}"
    passwd "$USERNAME"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}User '$USERNAME' created successfully${NC}"
    else
        echo -e "${RED}Error: Failed to set password for '$USERNAME'${NC}"
        exit 1
    fi
fi

# Add user to sudo group (Debian/Ubuntu) or wheel group (RHEL/CentOS)
echo -e "${GREEN}Adding '$USERNAME' to sudoers...${NC}"

if getent group sudo &>/dev/null; then
    # Debian/Ubuntu systems
    usermod -aG sudo "$USERNAME"
    echo -e "${GREEN}User '$USERNAME' added to 'sudo' group${NC}"
elif getent group wheel &>/dev/null; then
    # RHEL/CentOS systems
    usermod -aG wheel "$USERNAME"
    echo -e "${GREEN}User '$USERNAME' added to 'wheel' group${NC}"
else
    echo -e "${YELLOW}Warning: Neither 'sudo' nor 'wheel' group found${NC}"
    echo "Creating sudoers file entry manually..."
    
    # Create a sudoers file for the user
    SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
    echo "$USERNAME ALL=(ALL:ALL) ALL" > "$SUDOERS_FILE"
    chmod 0440 "$SUDOERS_FILE"
    
    # Validate the sudoers file
    if visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
        echo -e "${GREEN}Sudoers file created successfully at $SUDOERS_FILE${NC}"
    else
        echo -e "${RED}Error: Invalid sudoers file. Removing...${NC}"
        rm -f "$SUDOERS_FILE"
        exit 1
    fi
fi

# Verify sudo access
echo -e "${GREEN}Verifying sudo access for '$USERNAME'...${NC}"
if sudo -l -U "$USERNAME" &>/dev/null; then
    echo -e "${GREEN}Success! User '$USERNAME' has been created and granted sudo privileges${NC}"
    echo -e "${YELLOW}Note: The user may need to log out and back in for group changes to take effect${NC}"
else
    echo -e "${YELLOW}Warning: Could not verify sudo access. Please check manually.${NC}"
fi

# Display user information
echo -e "\n${GREEN}User Information:${NC}"
id "$USERNAME"

#!/usr/bin/env bash
# Description: Execute commands/scripts on remote hosts through SSH jump hosts (ProxyJump)
# Usage: ./ssh-jump-exec.sh -j jumphost1[,jumphost2,...] -t target -c "command" [-k key] [-s script]
# Dependencies: ssh (OpenSSH 7.3+ for ProxyJump support)

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
JUMP_HOSTS=""
TARGET_HOST=""
COMMAND=""
SSH_KEY=""
SCRIPT_FILE=""
UPLOAD_SCRIPT=false
SSH_OPTIONS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
VERBOSE=false
SAVE_OUTPUT=true
AUDIT_BASE_DIR="./audit"

# Usage function
usage() {
    cat << 'EOF'
Usage: ./ssh-jump-exec.sh [OPTIONS]

Execute commands or scripts on remote hosts through one or more jump hosts.
Supports multi-hop SSH connections without installing anything on intermediate hosts.

OPTIONS:
    -j JUMPHOSTS    Comma-separated list of jump hosts (user@host:port,user@host:port,...)
                    Example: user@kali.example.com,admin@internal-vm
    -t TARGET       Target host to execute command on (user@host or user@host:port)
    -c COMMAND      Command to execute on target host
    -s SCRIPT       Local script file to upload and execute on target
    -k KEY          SSH private key file path
    -u              Upload script (use with -s, keeps script on target)
    -o              Save output to audit/<remote_ip>/command-<timestamp>.txt
    -n              No output save (display only, don't save to file)
    -v              Verbose mode (show SSH debug output)
    -h              Display this help message

EXAMPLES:
    # Execute command through single jump host
    ./ssh-jump-exec.sh -j root@kali -t user@192.168.1.100 -c "whoami"

    # Execute through multiple jump hosts
    ./ssh-jump-exec.sh -j user@kali,admin@internal-vm -t root@target -c "hostname -I"

    # Run nmap through jump hosts
    ./ssh-jump-exec.sh -j root@kali -t user@scanner -c "nmap -sn 192.168.1.0/24"

    # Upload and execute local script
    ./ssh-jump-exec.sh -j root@kali -t user@target -s ./audit-script.sh

    # With SSH key
    ./ssh-jump-exec.sh -j root@kali -t user@target -k ~/.ssh/id_rsa -c "df -h"

    # Multiple hops with specific ports
    ./ssh-jump-exec.sh -j user@kali:22,admin@internal:2222 -t root@target:22 -c "ps aux"

    # Save output to audit directory (default behavior)
    ./ssh-jump-exec.sh -j root@kali -t user@target -c "nmap -sn 192.168.1.0/24"
    # Output saved to: audit/<target_ip>/command-<timestamp>.txt

    # Display only, don't save output
    ./ssh-jump-exec.sh -j root@kali -t user@target -c "whoami" -n

ENVIRONMENT:
    The script uses SSH ProxyJump feature (OpenSSH 7.3+) to chain connections.
    No software installation required on jump hosts.
    
    Output is automatically saved to: audit/<remote_ip>/command-<timestamp>.txt
    Each execution creates a new timestamped file with full command output.

NOTES:
    - Ensure you have SSH access to all hosts in the chain
    - Jump hosts must be able to reach the next hop
    - For scripts, temporary files are cleaned up automatically
    - Use -u flag to keep uploaded scripts on target host
    - Use -n flag to disable output saving (display only)

EOF
    exit 1
}

# Parse command line options
while getopts "j:t:c:s:k:uonvh" opt; do
    case $opt in
        j) JUMP_HOSTS="$OPTARG" ;;
        t) TARGET_HOST="$OPTARG" ;;
        c) COMMAND="$OPTARG" ;;
        s) SCRIPT_FILE="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        u) UPLOAD_SCRIPT=true ;;
        o) SAVE_OUTPUT=true ;;
        n) SAVE_OUTPUT=false ;;
        v) VERBOSE=true ;;
        h) usage ;;
        \?)
            echo -e "${RED}Invalid option: -$OPTARG${NC}" >&2
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$JUMP_HOSTS" ]]; then
    echo -e "${RED}Error: Jump host(s) not specified${NC}"
    usage
fi

if [[ -z "$TARGET_HOST" ]]; then
    echo -e "${RED}Error: Target host not specified${NC}"
    usage
fi

if [[ -z "$COMMAND" && -z "$SCRIPT_FILE" ]]; then
    echo -e "${RED}Error: Either command (-c) or script (-s) must be specified${NC}"
    usage
fi

if [[ -n "$SCRIPT_FILE" && ! -f "$SCRIPT_FILE" ]]; then
    echo -e "${RED}Error: Script file not found: $SCRIPT_FILE${NC}"
    exit 1
fi

# Validate SSH key if provided
if [[ -n "$SSH_KEY" ]]; then
    if [[ ! -f "$SSH_KEY" ]]; then
        echo -e "${RED}Error: SSH key not found: $SSH_KEY${NC}"
        exit 1
    fi
    SSH_OPTIONS="$SSH_OPTIONS -i $SSH_KEY"
fi

# Add verbose mode
if [[ "$VERBOSE" == true ]]; then
    SSH_OPTIONS="$SSH_OPTIONS -v"
fi

# Build ProxyJump chain
# Convert comma-separated list to ProxyJump format
PROXY_JUMP=$(echo "$JUMP_HOSTS" | tr ',' ',')

# Extract target IP for audit directory
TARGET_USER="${TARGET_HOST%@*}"
TARGET_ADDR="${TARGET_HOST#*@}"
TARGET_ADDR="${TARGET_ADDR%%:*}"  # Remove port if present

# Get actual IP address of target
TARGET_IP=$(ssh $SSH_OPTIONS -J "$PROXY_JUMP" "$TARGET_HOST" "hostname -I | awk '{print \$1}' 2>/dev/null || echo '$TARGET_ADDR'" 2>/dev/null | tr -d '[:space:]' || echo "$TARGET_ADDR")

# Create audit directory structure
AUDIT_DIR="$AUDIT_BASE_DIR/$TARGET_IP"
if [[ "$SAVE_OUTPUT" == true ]]; then
    mkdir -p "$AUDIT_DIR"
fi

# Generate timestamp for output file
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  SSH Jump Host Execution${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${BLUE}Jump Chain:${NC} $JUMP_HOSTS"
echo -e "${BLUE}Target:${NC} $TARGET_HOST ($TARGET_IP)"
if [[ -n "$COMMAND" ]]; then
    echo -e "${BLUE}Command:${NC} $COMMAND"
fi
if [[ -n "$SCRIPT_FILE" ]]; then
    echo -e "${BLUE}Script:${NC} $SCRIPT_FILE"
fi
if [[ "$SAVE_OUTPUT" == true ]]; then
    echo -e "${BLUE}Output Dir:${NC} $AUDIT_DIR"
fi
echo ""

# Test connectivity through jump chain
echo -e "${YELLOW}Testing connectivity through jump chain...${NC}"
if ssh $SSH_OPTIONS -J "$PROXY_JUMP" "$TARGET_HOST" "echo 'Connection successful'" 2>/dev/null; then
    echo -e "${GREEN}✓ Connection successful${NC}\n"
else
    echo -e "${RED}✗ Connection failed${NC}"
    echo -e "${YELLOW}Please verify:${NC}"
    echo -e "  1. All hosts are reachable"
    echo -e "  2. SSH credentials are correct"
    echo -e "  3. Each jump host can reach the next hop"
    echo -e "  4. Try with -v flag for verbose output"
    exit 1
fi

# Execute command or script
if [[ -n "$COMMAND" ]]; then
    # Direct command execution
    echo -e "${YELLOW}Executing command on $TARGET_HOST...${NC}"
    echo -e "${CYAN}-----------------------------------${NC}"
    
    if [[ "$SAVE_OUTPUT" == true ]]; then
        # Extract the main command (first word) for filename
        MAIN_COMMAND=$(echo "$COMMAND" | awk '{print $1}' | sed 's/[^a-zA-Z0-9._-]/_/g')
        OUTPUT_FILE="$AUDIT_DIR/${MAIN_COMMAND}-$TIMESTAMP.txt"
        
        # Create header for output file
        {
            echo "============================================"
            echo "SSH Jump Host Command Execution"
            echo "============================================"
            echo "Executed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
            echo "Jump Chain: $JUMP_HOSTS"
            echo "Target Host: $TARGET_HOST"
            echo "Target IP: $TARGET_IP"
            echo "Command: $COMMAND"
            echo "Executed By: $USER@$(hostname)"
            echo ""
            echo "============================================"
            echo "Command Output:"
            echo "============================================"
            echo ""
        } > "$OUTPUT_FILE"
        
        # Execute and capture output (both stdout and stderr)
        ssh $SSH_OPTIONS -J "$PROXY_JUMP" "$TARGET_HOST" "$COMMAND" 2>&1 | tee -a "$OUTPUT_FILE"
        EXIT_CODE=${PIPESTATUS[0]}
        
        # Add footer
        {
            echo ""
            echo "============================================"
            echo "Exit Code: $EXIT_CODE"
            echo "Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
            echo "============================================"
        } >> "$OUTPUT_FILE"
    else
        # Just display output without saving
        ssh $SSH_OPTIONS -J "$PROXY_JUMP" "$TARGET_HOST" "$COMMAND"
        EXIT_CODE=$?
    fi
    
    echo -e "${CYAN}-----------------------------------${NC}"
    if [[ $EXIT_CODE -eq 0 ]]; then
        echo -e "${GREEN}✓ Command executed successfully${NC}"
        if [[ "$SAVE_OUTPUT" == true ]]; then
            echo -e "${GREEN}✓ Output saved to: ${BLUE}$OUTPUT_FILE${NC}"
        fi
    else
        echo -e "${RED}✗ Command failed with exit code: $EXIT_CODE${NC}"
        if [[ "$SAVE_OUTPUT" == true ]]; then
            echo -e "${YELLOW}Output saved to: ${BLUE}$OUTPUT_FILE${NC}"
        fi
        exit $EXIT_CODE
    fi

elif [[ -n "$SCRIPT_FILE" ]]; then
    # Script execution
    SCRIPT_NAME=$(basename "$SCRIPT_FILE")
    REMOTE_SCRIPT="/tmp/${SCRIPT_NAME}.$$"
    
    echo -e "${YELLOW}Uploading script to $TARGET_HOST...${NC}"
    
    # Upload script through jump hosts
    scp $SSH_OPTIONS -J "$PROXY_JUMP" "$SCRIPT_FILE" "$TARGET_HOST:$REMOTE_SCRIPT" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Script uploaded${NC}"
    else
        echo -e "${RED}✗ Failed to upload script${NC}"
        exit 1
    fi
    
    # Make script executable
    ssh $SSH_OPTIONS -J "$PROXY_JUMP" "$TARGET_HOST" "chmod +x $REMOTE_SCRIPT" 2>/dev/null
    
    # Execute script
    echo -e "${YELLOW}Executing script on $TARGET_HOST...${NC}"
    echo -e "${CYAN}-----------------------------------${NC}"
    
    if [[ "$SAVE_OUTPUT" == true ]]; then
        OUTPUT_FILE="$AUDIT_DIR/script-${SCRIPT_NAME}-$TIMESTAMP.txt"
        
        # Create header for output file
        {
            echo "============================================"
            echo "SSH Jump Host Script Execution"
            echo "============================================"
            echo "Executed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
            echo "Jump Chain: $JUMP_HOSTS"
            echo "Target Host: $TARGET_HOST"
            echo "Target IP: $TARGET_IP"
            echo "Script: $SCRIPT_FILE"
            echo "Remote Path: $REMOTE_SCRIPT"
            echo "Executed By: $USER@$(hostname)"
            echo ""
            echo "============================================"
            echo "Script Output:"
            echo "============================================"
            echo ""
        } > "$OUTPUT_FILE"
        
        # Execute and capture output
        ssh $SSH_OPTIONS -J "$PROXY_JUMP" "$TARGET_HOST" "$REMOTE_SCRIPT" 2>&1 | tee -a "$OUTPUT_FILE"
        EXIT_CODE=${PIPESTATUS[0]}
        
        # Add footer
        {
            echo ""
            echo "============================================"
            echo "Exit Code: $EXIT_CODE"
            echo "Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
            echo "============================================"
        } >> "$OUTPUT_FILE"
    else
        # Just display output without saving
        ssh $SSH_OPTIONS -J "$PROXY_JUMP" "$TARGET_HOST" "$REMOTE_SCRIPT"
        EXIT_CODE=$?
    fi
    
    echo -e "${CYAN}-----------------------------------${NC}"
    
    # Cleanup unless -u flag is set
    if [[ "$UPLOAD_SCRIPT" == false ]]; then
        echo -e "${YELLOW}Cleaning up temporary files...${NC}"
        ssh $SSH_OPTIONS -J "$PROXY_JUMP" "$TARGET_HOST" "rm -f $REMOTE_SCRIPT" 2>/dev/null
        echo -e "${GREEN}✓ Cleanup complete${NC}"
    else
        echo -e "${BLUE}Script kept on target: $REMOTE_SCRIPT${NC}"
    fi
    
    if [[ $EXIT_CODE -eq 0 ]]; then
        echo -e "${GREEN}✓ Script executed successfully${NC}"
        if [[ "$SAVE_OUTPUT" == true ]]; then
            echo -e "${GREEN}✓ Output saved to: ${BLUE}$OUTPUT_FILE${NC}"
        fi
    else
        echo -e "${RED}✗ Script failed with exit code: $EXIT_CODE${NC}"
        if [[ "$SAVE_OUTPUT" == true ]]; then
            echo -e "${YELLOW}Output saved to: ${BLUE}$OUTPUT_FILE${NC}"
        fi
        exit $EXIT_CODE
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Execution Complete${NC}"
echo -e "${GREEN}========================================${NC}"

if [[ "$SAVE_OUTPUT" == true ]]; then
    echo -e "${BLUE}All output files in: ${NC}$AUDIT_DIR"
    echo -e "${YELLOW}View latest output: ${NC}cat $OUTPUT_FILE"
    echo -e "${YELLOW}List all outputs: ${NC}ls -lht $AUDIT_DIR"
fi
echo ""

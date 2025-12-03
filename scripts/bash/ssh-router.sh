#!/usr/bin/env bash
# Description: SSH routing manager for complex multi-hop network topologies
# Usage: ./ssh-router.sh -r routes.conf -t target -c "command"
# Dependencies: ssh (OpenSSH 7.3+)

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
ROUTES_FILE=""
TARGET_HOST=""
COMMAND=""
SCRIPT_FILE=""
SSH_KEY=""
UPLOAD_SCRIPT=false
SAVE_OUTPUT=true
AUDIT_BASE_DIR="./audit"
SSH_OPTIONS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
VERBOSE=false
LIST_ROUTES=false

# Usage function
usage() {
    cat << 'EOF'
Usage: ./ssh-router.sh [OPTIONS]

Intelligently route SSH connections through jump hosts based on network topology.
Automatically selects the correct jump chain based on destination network.

OPTIONS:
    -r ROUTES       Routes configuration file (default: ./ssh-routes.conf)
    -t TARGET       Target host to reach (user@host or IP)
    -c COMMAND      Command to execute on target host
    -s SCRIPT       Local script file to upload and execute on target
    -k KEY          SSH private key file path
    -l              List configured routes and test connectivity
    -u              Upload script (use with -s, keeps script on target)
    -n              No output save (display only)
    -v              Verbose mode
    -h              Display this help message

EXAMPLES:
    # Execute command with automatic routing
    ./ssh-router.sh -r routes.conf -t root@192.168.2.50 -c "hostname -I"

    # Run script on target using automatic route selection
    ./ssh-router.sh -r routes.conf -t user@10.0.5.100 -s ./audit.sh

    # List all configured routes
    ./ssh-router.sh -r routes.conf -l

    # Test specific target routing
    ./ssh-router.sh -r routes.conf -t 192.168.3.75 -c "echo test"

ROUTES FILE FORMAT:
    # Route definition: NETWORK/CIDR via JUMP_CHAIN
    192.168.1.0/24 via user@kali
    192.168.2.0/24 via user@kali,admin@vm1
    10.0.5.0/24 via user@kali,admin@vm2
    172.16.0.0/16 via user@kali,admin@vm3,root@gateway
    
    # Direct access (no jump)
    10.10.0.0/16 via direct
    
    # Comments start with #
    # Default route (if no match found)
    default via user@kali

See example file: ssh-routes.conf.example

EOF
    exit 1
}

# Parse command line options
while getopts "r:t:c:s:k:lunvh" opt; do
    case $opt in
        r) ROUTES_FILE="$OPTARG" ;;
        t) TARGET_HOST="$OPTARG" ;;
        c) COMMAND="$OPTARG" ;;
        s) SCRIPT_FILE="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        l) LIST_ROUTES=true ;;
        u) UPLOAD_SCRIPT=true ;;
        n) SAVE_OUTPUT=false ;;
        v) VERBOSE=true ;;
        h) usage ;;
        \?)
            echo -e "${RED}Invalid option: -$OPTARG${NC}" >&2
            usage
            ;;
    esac
done

# Set default routes file if not specified
if [[ -z "$ROUTES_FILE" ]]; then
    ROUTES_FILE="./ssh-routes.conf"
fi

# Check routes file exists
if [[ ! -f "$ROUTES_FILE" ]]; then
    echo -e "${RED}Error: Routes file not found: $ROUTES_FILE${NC}"
    echo -e "${YELLOW}Create a routes file or see: ssh-routes.conf.example${NC}"
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

if [[ "$VERBOSE" == true ]]; then
    SSH_OPTIONS="$SSH_OPTIONS -v"
fi

# Function to convert IP to decimal for CIDR matching
ip_to_dec() {
    local ip=$1
    local IFS=.
    local -a octets=($ip)
    echo $(( (octets[0] << 24) + (octets[1] << 16) + (octets[2] << 8) + octets[3] ))
}

# Function to check if IP is in CIDR range
ip_in_cidr() {
    local ip=$1
    local cidr=$2
    
    local network=${cidr%/*}
    local prefix=${cidr#*/}
    
    # Convert to decimal
    local ip_dec=$(ip_to_dec "$ip")
    local net_dec=$(ip_to_dec "$network")
    
    # Calculate netmask
    local mask=$((0xFFFFFFFF << (32 - prefix)))
    
    # Check if IP is in range
    if (( (ip_dec & mask) == (net_dec & mask) )); then
        return 0
    else
        return 1
    fi
}

# Function to extract IP from target
extract_ip() {
    local target=$1
    
    # Remove user@ prefix if present
    target="${target#*@}"
    # Remove :port suffix if present
    target="${target%%:*}"
    
    # Check if it's already an IP
    if [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$target"
        return 0
    fi
    
    # Try to resolve hostname
    local resolved=$(getent hosts "$target" 2>/dev/null | awk '{print $1}' | head -1)
    if [[ -n "$resolved" ]]; then
        echo "$resolved"
        return 0
    fi
    
    # Return original if can't resolve
    echo "$target"
    return 1
}

# Function to find route for target
find_route() {
    local target_ip=$1
    local default_route=""
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        # Parse route line: NETWORK via JUMPS
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+via[[:space:]]+(.+)$ ]]; then
            local network="${BASH_REMATCH[1]}"
            local jumps="${BASH_REMATCH[2]}"
            
            # Store default route
            if [[ "$network" == "default" ]]; then
                default_route="$jumps"
                continue
            fi
            
            # Check for direct access
            if [[ "$network" == "direct" ]]; then
                continue
            fi
            
            # Check if target IP matches this network
            if ip_in_cidr "$target_ip" "$network"; then
                echo "$jumps"
                return 0
            fi
        fi
    done < "$ROUTES_FILE"
    
    # Return default route if no match
    if [[ -n "$default_route" ]]; then
        echo "$default_route"
        return 0
    fi
    
    return 1
}

# Function to list and test routes
list_routes() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  SSH Routes Configuration${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${BLUE}Routes File:${NC} $ROUTES_FILE\n"
    
    local route_num=0
    
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Display comments
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            echo -e "${YELLOW}$line${NC}"
            continue
        fi
        
        # Parse and display routes
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+via[[:space:]]+(.+)$ ]]; then
            local network="${BASH_REMATCH[1]}"
            local jumps="${BASH_REMATCH[2]}"
            
            ((route_num++))
            
            if [[ "$network" == "default" ]]; then
                echo -e "${GREEN}Route $route_num: ${YELLOW}DEFAULT ROUTE${NC}"
            else
                echo -e "${GREEN}Route $route_num: ${BLUE}$network${NC}"
            fi
            
            if [[ "$jumps" == "direct" ]]; then
                echo -e "  Jump Chain: ${CYAN}DIRECT (no jump host)${NC}"
            else
                echo -e "  Jump Chain: ${CYAN}$jumps${NC}"
                
                # Test connectivity if not listing only
                if [[ "$LIST_ROUTES" == true ]]; then
                    echo -n "  Testing connectivity... "
                    
                    # Extract first hop for testing
                    local first_hop="${jumps%%,*}"
                    if ssh $SSH_OPTIONS -o ConnectTimeout=5 "$first_hop" "echo ok" &>/dev/null; then
                        echo -e "${GREEN}✓ Reachable${NC}"
                    else
                        echo -e "${RED}✗ Unreachable${NC}"
                    fi
                fi
            fi
            echo ""
        fi
    done < "$ROUTES_FILE"
    
    echo -e "${CYAN}========================================${NC}"
    echo -e "Total routes configured: ${GREEN}$route_num${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# If listing routes, do that and exit
if [[ "$LIST_ROUTES" == true ]]; then
    list_routes
    exit 0
fi

# Validate target is provided
if [[ -z "$TARGET_HOST" ]]; then
    echo -e "${RED}Error: Target host not specified${NC}"
    usage
fi

# Validate command or script is provided
if [[ -z "$COMMAND" && -z "$SCRIPT_FILE" ]]; then
    echo -e "${RED}Error: Either command (-c) or script (-s) must be specified${NC}"
    usage
fi

# Validate script file if provided
if [[ -n "$SCRIPT_FILE" && ! -f "$SCRIPT_FILE" ]]; then
    echo -e "${RED}Error: Script file not found: $SCRIPT_FILE${NC}"
    exit 1
fi

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  SSH Router - Auto Route Selection${NC}"
echo -e "${CYAN}========================================${NC}"

# Extract IP from target
TARGET_USER="${TARGET_HOST%@*}"
TARGET_ADDR="${TARGET_HOST#*@}"
TARGET_ADDR="${TARGET_ADDR%%:*}"

echo -e "${YELLOW}Resolving target address...${NC}"
TARGET_IP=$(extract_ip "$TARGET_HOST")
echo -e "${BLUE}Target Host:${NC} $TARGET_HOST"
echo -e "${BLUE}Target IP:${NC} $TARGET_IP"

# Find appropriate route
echo -e "\n${YELLOW}Finding route for $TARGET_IP...${NC}"
JUMP_CHAIN=$(find_route "$TARGET_IP")

if [[ -z "$JUMP_CHAIN" ]]; then
    echo -e "${RED}Error: No route found for $TARGET_IP${NC}"
    echo -e "${YELLOW}Check your routes configuration: $ROUTES_FILE${NC}"
    exit 1
fi

if [[ "$JUMP_CHAIN" == "direct" ]]; then
    echo -e "${GREEN}✓ Direct connection (no jump host)${NC}"
    USE_JUMP=false
else
    echo -e "${GREEN}✓ Route found: ${CYAN}$JUMP_CHAIN${NC}"
    USE_JUMP=true
fi

# Create audit directory
AUDIT_DIR="$AUDIT_BASE_DIR/$TARGET_IP"
if [[ "$SAVE_OUTPUT" == true ]]; then
    mkdir -p "$AUDIT_DIR"
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Test connectivity
echo -e "\n${YELLOW}Testing connectivity...${NC}"
if [[ "$USE_JUMP" == true ]]; then
    if ssh $SSH_OPTIONS -J "$JUMP_CHAIN" "$TARGET_HOST" "echo 'ok'" &>/dev/null; then
        echo -e "${GREEN}✓ Connection successful${NC}\n"
    else
        echo -e "${RED}✗ Connection failed${NC}"
        echo -e "${YELLOW}Verify:${NC}"
        echo -e "  - Jump hosts are accessible"
        echo -e "  - Target host is reachable through jump chain"
        echo -e "  - Credentials are correct"
        exit 1
    fi
else
    if ssh $SSH_OPTIONS "$TARGET_HOST" "echo 'ok'" &>/dev/null; then
        echo -e "${GREEN}✓ Connection successful${NC}\n"
    else
        echo -e "${RED}✗ Connection failed${NC}"
        exit 1
    fi
fi

# Execute command or script
if [[ -n "$COMMAND" ]]; then
    echo -e "${YELLOW}Executing command on $TARGET_HOST...${NC}"
    echo -e "${CYAN}-----------------------------------${NC}"
    
    if [[ "$SAVE_OUTPUT" == true ]]; then
        MAIN_COMMAND=$(echo "$COMMAND" | awk '{print $1}' | sed 's/[^a-zA-Z0-9._-]/_/g')
        OUTPUT_FILE="$AUDIT_DIR/${MAIN_COMMAND}-$TIMESTAMP.txt"
        
        {
            echo "============================================"
            echo "SSH Router - Command Execution"
            echo "============================================"
            echo "Executed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
            echo "Target Host: $TARGET_HOST"
            echo "Target IP: $TARGET_IP"
            echo "Route: $JUMP_CHAIN"
            echo "Command: $COMMAND"
            echo "Executed By: $USER@$(hostname)"
            echo ""
            echo "============================================"
            echo "Command Output:"
            echo "============================================"
            echo ""
        } > "$OUTPUT_FILE"
        
        if [[ "$USE_JUMP" == true ]]; then
            ssh $SSH_OPTIONS -J "$JUMP_CHAIN" "$TARGET_HOST" "$COMMAND" 2>&1 | tee -a "$OUTPUT_FILE"
        else
            ssh $SSH_OPTIONS "$TARGET_HOST" "$COMMAND" 2>&1 | tee -a "$OUTPUT_FILE"
        fi
        EXIT_CODE=${PIPESTATUS[0]}
        
        {
            echo ""
            echo "============================================"
            echo "Exit Code: $EXIT_CODE"
            echo "Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
            echo "============================================"
        } >> "$OUTPUT_FILE"
    else
        if [[ "$USE_JUMP" == true ]]; then
            ssh $SSH_OPTIONS -J "$JUMP_CHAIN" "$TARGET_HOST" "$COMMAND"
        else
            ssh $SSH_OPTIONS "$TARGET_HOST" "$COMMAND"
        fi
        EXIT_CODE=$?
    fi
    
    echo -e "${CYAN}-----------------------------------${NC}"
    if [[ $EXIT_CODE -eq 0 ]]; then
        echo -e "${GREEN}✓ Command executed successfully${NC}"
        [[ "$SAVE_OUTPUT" == true ]] && echo -e "${GREEN}✓ Output: ${BLUE}$OUTPUT_FILE${NC}"
    else
        echo -e "${RED}✗ Command failed (exit code: $EXIT_CODE)${NC}"
        [[ "$SAVE_OUTPUT" == true ]] && echo -e "${YELLOW}Output: ${BLUE}$OUTPUT_FILE${NC}"
        exit $EXIT_CODE
    fi

elif [[ -n "$SCRIPT_FILE" ]]; then
    SCRIPT_NAME=$(basename "$SCRIPT_FILE")
    REMOTE_SCRIPT="/tmp/${SCRIPT_NAME}.$$"
    
    echo -e "${YELLOW}Uploading script to $TARGET_HOST...${NC}"
    
    if [[ "$USE_JUMP" == true ]]; then
        scp $SSH_OPTIONS -J "$JUMP_CHAIN" "$SCRIPT_FILE" "$TARGET_HOST:$REMOTE_SCRIPT" 2>/dev/null
    else
        scp $SSH_OPTIONS "$SCRIPT_FILE" "$TARGET_HOST:$REMOTE_SCRIPT" 2>/dev/null
    fi
    
    [[ $? -eq 0 ]] && echo -e "${GREEN}✓ Script uploaded${NC}" || { echo -e "${RED}✗ Upload failed${NC}"; exit 1; }
    
    if [[ "$USE_JUMP" == true ]]; then
        ssh $SSH_OPTIONS -J "$JUMP_CHAIN" "$TARGET_HOST" "chmod +x $REMOTE_SCRIPT" 2>/dev/null
    else
        ssh $SSH_OPTIONS "$TARGET_HOST" "chmod +x $REMOTE_SCRIPT" 2>/dev/null
    fi
    
    echo -e "${YELLOW}Executing script on $TARGET_HOST...${NC}"
    echo -e "${CYAN}-----------------------------------${NC}"
    
    if [[ "$SAVE_OUTPUT" == true ]]; then
        OUTPUT_FILE="$AUDIT_DIR/script-${SCRIPT_NAME}-$TIMESTAMP.txt"
        
        {
            echo "============================================"
            echo "SSH Router - Script Execution"
            echo "============================================"
            echo "Executed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
            echo "Target Host: $TARGET_HOST"
            echo "Target IP: $TARGET_IP"
            echo "Route: $JUMP_CHAIN"
            echo "Script: $SCRIPT_FILE"
            echo "Remote Path: $REMOTE_SCRIPT"
            echo "Executed By: $USER@$(hostname)"
            echo ""
            echo "============================================"
            echo "Script Output:"
            echo "============================================"
            echo ""
        } > "$OUTPUT_FILE"
        
        if [[ "$USE_JUMP" == true ]]; then
            ssh $SSH_OPTIONS -J "$JUMP_CHAIN" "$TARGET_HOST" "$REMOTE_SCRIPT" 2>&1 | tee -a "$OUTPUT_FILE"
        else
            ssh $SSH_OPTIONS "$TARGET_HOST" "$REMOTE_SCRIPT" 2>&1 | tee -a "$OUTPUT_FILE"
        fi
        EXIT_CODE=${PIPESTATUS[0]}
        
        {
            echo ""
            echo "============================================"
            echo "Exit Code: $EXIT_CODE"
            echo "Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
            echo "============================================"
        } >> "$OUTPUT_FILE"
    else
        if [[ "$USE_JUMP" == true ]]; then
            ssh $SSH_OPTIONS -J "$JUMP_CHAIN" "$TARGET_HOST" "$REMOTE_SCRIPT"
        else
            ssh $SSH_OPTIONS "$TARGET_HOST" "$REMOTE_SCRIPT"
        fi
        EXIT_CODE=$?
    fi
    
    echo -e "${CYAN}-----------------------------------${NC}"
    
    if [[ "$UPLOAD_SCRIPT" == false ]]; then
        echo -e "${YELLOW}Cleaning up...${NC}"
        if [[ "$USE_JUMP" == true ]]; then
            ssh $SSH_OPTIONS -J "$JUMP_CHAIN" "$TARGET_HOST" "rm -f $REMOTE_SCRIPT" 2>/dev/null
        else
            ssh $SSH_OPTIONS "$TARGET_HOST" "rm -f $REMOTE_SCRIPT" 2>/dev/null
        fi
        echo -e "${GREEN}✓ Cleanup complete${NC}"
    else
        echo -e "${BLUE}Script kept on target: $REMOTE_SCRIPT${NC}"
    fi
    
    if [[ $EXIT_CODE -eq 0 ]]; then
        echo -e "${GREEN}✓ Script executed successfully${NC}"
        [[ "$SAVE_OUTPUT" == true ]] && echo -e "${GREEN}✓ Output: ${BLUE}$OUTPUT_FILE${NC}"
    else
        echo -e "${RED}✗ Script failed (exit code: $EXIT_CODE)${NC}"
        [[ "$SAVE_OUTPUT" == true ]] && echo -e "${YELLOW}Output: ${BLUE}$OUTPUT_FILE${NC}"
        exit $EXIT_CODE
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Execution Complete${NC}"
echo -e "${GREEN}========================================${NC}"
if [[ "$SAVE_OUTPUT" == true ]]; then
    echo -e "${BLUE}Output directory: ${NC}$AUDIT_DIR"
    echo -e "${YELLOW}View output: ${NC}cat $OUTPUT_FILE"
fi
echo ""

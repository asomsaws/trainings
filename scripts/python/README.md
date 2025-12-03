# Python Scripts

This directory contains cross-platform Python scripts for automation and system administration tasks.

**Key Feature:** All scripts output results in JSON format for easy integration with automation pipelines, APIs, and other tools.

## Available Scripts

### User Management

#### `create_sudo_user.py`
Create a new user account and grant sudo privileges with JSON output.

**Usage:**
```bash
python create_sudo_user.py <username>
# Or with sudo
sudo python create_sudo_user.py john
```

**Features:**
- Validates username format
- Creates user with home directory
- Interactive password setup
- Auto-detects distribution (sudo/wheel groups)
- Falls back to sudoers.d configuration
- Comprehensive step-by-step logging
- JSON output with all operation details

**Output:** `audit/create-sudo-user-<username>-<timestamp>.json`

**JSON Structure:**
```json
{
  "operation": "create_sudo_user",
  "timestamp": "2025-12-03T...",
  "username": "john",
  "success": true,
  "steps": [...],
  "errors": [],
  "user_info": "uid=1001(john) gid=1001(john) groups=1001(john),27(sudo)"
}
```

---

### SSH Key Management

#### `setup_ssh_keypair.py`
Generate SSH key pairs and configure key-based authentication with JSON output.

**Usage:**
```bash
python setup_ssh_keypair.py <user@host> [options]
```

**Options:**
- `-t TYPE` - Key type: rsa, ed25519 (default), ecdsa
- `-b BITS` - Key size for RSA
- `-n NAME` - Custom key name
- `-c COMMENT` - Key comment
- `-a ALIAS` - Add SSH config alias
- `-o DIR` - Output directory

**Examples:**
```bash
# Generate ed25519 key for remote host
python setup_ssh_keypair.py user@192.168.1.100

# RSA key with custom options
python setup_ssh_keypair.py -t rsa -b 4096 -a myserver admin@server.com
```

**Output:** `audit/ssh-keypair-<host>-<timestamp>.json`

**JSON Structure:**
```json
{
  "operation": "setup_ssh_keypair",
  "timestamp": "...",
  "remote_host": "user@host",
  "key_type": "ed25519",
  "key_path": "/home/user/.ssh/id_ed25519",
  "public_key": "ssh-ed25519 AAAA...",
  "success": true,
  "steps": [...]
}
```

---

### System Auditing

#### `linux_audit.py`
Comprehensive Linux system audit via SSH with complete JSON output.

**Usage:**
```bash
python linux_audit.py <user@host> [options]
```

**Options:**
- `-k KEY` - SSH private key path
- `-o DIR` - Output directory

**Features:**
- System information (OS, kernel, hardware, uptime)
- User accounts and password hashes
- Network configuration and connections
- Installed packages
- Running services
- Firewall rules
- SSH configuration
- Cron jobs
- File permissions and SUID/SGID files
- Disk usage
- Running processes

**Output:** `audit/<remote_ip>/linux-audit-<timestamp>.json`

**JSON Structure:**
```json
{
  "audit_type": "linux_system_audit",
  "timestamp": "...",
  "remote_host": "user@host",
  "remote_ip": "192.168.1.100",
  "audit_sections": {
    "system_info": { "hostname": "...", "os_release": "...", ... },
    "users": { "passwd": "...", "groups": "...", ... },
    "password_hashes": "...",
    "network": { "ip_addresses": "...", "routing": "...", ... },
    "packages": "...",
    "services": {...},
    "firewall": {...},
    "ssh_config": {...},
    "cron_jobs": "...",
    "file_permissions": "...",
    "disk_usage": {...},
    "processes": {...}
  },
  "errors": []
}
```

---

### Jump Host Execution

#### `ssh_jump_exec.py`
Execute commands/scripts through SSH jump hosts with JSON output.

**Usage:**
```bash
python ssh_jump_exec.py -j jumphost1[,jumphost2] -t target -c "command"
```

**Options:**
- `-j JUMP` - Comma-separated jump hosts
- `-t TARGET` - Target host
- `-c COMMAND` - Command to execute
- `-s SCRIPT` - Script file to execute
- `-k KEY` - SSH private key
- `-u` - Keep uploaded script
- `-n` - No output save
- `-o DIR` - Output directory

**Examples:**
```bash
# Execute command through single jump
python ssh_jump_exec.py -j root@kali -t user@192.168.1.100 -c "hostname"

# Multiple jumps with script
python ssh_jump_exec.py -j root@kali,admin@vm1 -t user@target -s ./audit.sh
```

**Output:** `audit/<target_ip>/<command>-<timestamp>.json`

**JSON Structure:**
```json
{
  "operation": "ssh_jump_exec",
  "timestamp": "...",
  "jump_chain": "root@kali,admin@vm1",
  "target_host": "user@target",
  "target_ip": "192.168.1.50",
  "command": "hostname",
  "output": "target-hostname\n",
  "exit_code": 0,
  "success": true,
  "errors": []
}
```

---

### Intelligent Routing

#### `ssh_router.py`
Automatic route selection based on network topology with JSON output.

**Usage:**
```bash
python ssh_router.py -r routes.json -t target -c "command"
```

**Options:**
- `-r ROUTES` - Routes configuration JSON file
- `-t TARGET` - Target host
- `-c COMMAND` - Command to execute
- `-s SCRIPT` - Script to execute
- `-l` - List all routes
- `-k KEY` - SSH private key
- `-u` - Keep uploaded script
- `-n` - No output save

**Routes File (ssh_routes.json):**
```json
{
  "routes": [
    {
      "network": "192.168.1.0/24",
      "via": "root@kali,admin@vm1",
      "description": "Internal Network 1"
    },
    {
      "network": "default",
      "via": "root@kali",
      "description": "Default route"
    }
  ]
}
```

**Examples:**
```bash
# Auto-select route based on target IP
python ssh_router.py -r routes.json -t root@192.168.1.50 -c "hostname"

# List all configured routes
python ssh_router.py -r routes.json -l
```

**Output:** `audit/<target_ip>/<command>-<timestamp>.json`

---

## JSON Output Benefits

All Python scripts output structured JSON for:

1. **Automation Integration** - Easy parsing in CI/CD pipelines
2. **API Compatibility** - Direct integration with REST APIs
3. **Data Analysis** - Import into pandas, databases, or analytics tools
4. **Audit Trails** - Complete operation history with timestamps
5. **Error Tracking** - Structured error logging
6. **Monitoring** - Integration with monitoring tools

## Processing JSON Output

**Python:**
```python
import json

with open('audit/192.168.1.100/linux-audit-20251203-145030.json') as f:
    audit_data = json.load(f)
    
print(f"Audit of: {audit_data['remote_host']}")
print(f"Success: {audit_data.get('success', False)}")
```

**Command Line (jq):**
```bash
# Extract specific data
jq '.audit_sections.system_info.hostname' audit/192.168.1.100/linux-audit-*.json

# Check for errors
jq '.errors[]' audit/*/**.json

# Get all successful operations
jq 'select(.success == true) | .operation' audit/*/*.json
```

**Bash:**
```bash
# Parse with python
python -c "import json, sys; data=json.load(sys.stdin); print(data['remote_ip'])" < output.json
```

---

## Dependencies

All scripts use only Python 3 standard library - no external packages required!

**Minimum Python Version:** 3.6+

---

## Output Directory Structure

```
audit/
├── 192.168.1.100/
│   ├── linux-audit-20251203-145030.json
│   ├── hostname-20251203-150000.json
│   └── nmap-20251203-151500.json
├── 192.168.2.50/
│   └── ps-20251203-152000.json
└── create-sudo-user-john-20251203-143000.json
```

---

## Comparison: Bash vs Python Scripts

| Feature | Bash Scripts | Python Scripts |
|---------|--------------|----------------|
| **Output Format** | Text files | JSON |
| **Parsing** | grep/awk/sed | Native JSON |
| **Integration** | Manual parsing | Direct import |
| **Error Handling** | Exit codes | Structured errors |
| **Data Structure** | Flat text | Nested objects |
| **Best For** | Direct usage | Automation/APIs |

Use **Bash scripts** for direct command-line usage and human-readable output.  
Use **Python scripts** for automation, integration, and programmatic access.

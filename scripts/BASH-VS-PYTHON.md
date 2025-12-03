# Bash vs Python Scripts Comparison

## Overview

Both script sets provide identical functionality, but differ in output format and use cases.

## Available Scripts

| Script | Bash Version | Python Version | Output Format |
|--------|-------------|----------------|---------------|
| Create Sudo User | `create-sudo-user.sh` | `create_sudo_user.py` | Text / JSON |
| SSH Key Setup | `setup-ssh-keypair.sh` | `setup_ssh_keypair.py` | Text / JSON |
| Linux Audit | `linux-audit.sh` | `linux_audit.py` | Text files / JSON |
| SSH Jump Exec | `ssh-jump-exec.sh` | `ssh_jump_exec.py` | Text / JSON |
| SSH Router | `ssh-router.sh` | `ssh_router.py` | Text / JSON |

## Key Differences

### Bash Scripts
- **Output:** Human-readable text files
- **Best For:** Direct command-line usage, manual review
- **Parsing:** grep, awk, sed required
- **Dependencies:** Standard Linux tools
- **Format:** Plain text in `audit/<ip>/<command>-<timestamp>.txt`

### Python Scripts
- **Output:** Structured JSON format
- **Best For:** Automation, APIs, data processing
- **Parsing:** Native JSON parsing
- **Dependencies:** Python 3.6+ (standard library only)
- **Format:** JSON in `audit/<ip>/<command>-<timestamp>.json`

## Usage Examples

### Create Sudo User

**Bash:**
```bash
sudo ./create-sudo-user.sh john
# No file output, terminal only
```

**Python:**
```bash
sudo python create_sudo_user.py john
# Output: audit/create-sudo-user-john-20251203-145030.json
```

### SSH Key Setup

**Bash:**
```bash
./setup-ssh-keypair.sh user@host
# Terminal output only
```

**Python:**
```bash
python setup_ssh_keypair.py user@host
# Output: audit/ssh-keypair-user_at_host-20251203-145030.json
```

### Linux Audit

**Bash:**
```bash
./linux-audit.sh user@192.168.1.100
# Output: audit/192.168.1.100/*.txt (14 separate files)
```

**Python:**
```bash
python linux_audit.py user@192.168.1.100
# Output: audit/192.168.1.100/linux-audit-20251203-145030.json (single file)
```

### SSH Jump Execution

**Bash:**
```bash
./ssh-jump-exec.sh -j root@kali -t user@target -c "nmap -sn 192.168.1.0/24"
# Output: audit/<ip>/nmap-20251203-145030.txt
```

**Python:**
```bash
python ssh_jump_exec.py -j root@kali -t user@target -c "nmap -sn 192.168.1.0/24"
# Output: audit/<ip>/nmap-20251203-145030.json
```

### SSH Router

**Bash:**
```bash
./ssh-router.sh -r ssh-routes.conf -t root@192.168.1.50 -c "hostname"
# Output: audit/192.168.1.50/hostname-20251203-145030.txt
```

**Python:**
```bash
python ssh_router.py -r ssh_routes.json -t root@192.168.1.50 -c "hostname"
# Output: audit/192.168.1.50/hostname-20251203-145030.json
```

## Configuration Files

### Routes Configuration

**Bash (ssh-routes.conf):**
```conf
192.168.1.0/24 via root@kali,admin@vm1
192.168.2.0/24 via root@kali,admin@vm2
default via root@kali
```

**Python (ssh_routes.json):**
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

## Processing Output

### Bash Output (Text)

```bash
# View audit
cat audit/192.168.1.100/system_info.txt

# Search for pattern
grep -r "kernel" audit/192.168.1.100/

# Count users
wc -l audit/192.168.1.100/users.txt
```

### Python Output (JSON)

```bash
# View audit
cat audit/192.168.1.100/linux-audit-20251203-145030.json | jq .

# Extract specific data
jq '.audit_sections.system_info.hostname' audit/*/linux-audit-*.json

# Check success status
jq '.success' audit/*/*.json

# Get all errors
jq '.errors[]' audit/*/*.json

# Python processing
python -c "
import json
with open('audit/192.168.1.100/linux-audit-20251203-145030.json') as f:
    data = json.load(f)
    print(f'Hostname: {data["audit_sections"]["system_info"]["hostname"]}')
"
```

## Integration Examples

### CI/CD Pipeline

```python
import json
import requests

# Load audit result
with open('audit/192.168.1.100/linux-audit-20251203-145030.json') as f:
    audit_data = json.load(f)

# Send to monitoring API
if not audit_data.get('success'):
    requests.post('https://api.monitoring.com/alerts', json={
        'host': audit_data['remote_host'],
        'errors': audit_data['errors'],
        'timestamp': audit_data['timestamp']
    })
```

### Database Storage

```python
import json
import psycopg2

# Load audit result
with open('audit/192.168.1.100/linux-audit-20251203-145030.json') as f:
    audit_data = json.load(f)

# Store in PostgreSQL
conn = psycopg2.connect(...)
cur = conn.cursor()
cur.execute(
    "INSERT INTO audits (host, timestamp, data) VALUES (%s, %s, %s)",
    (audit_data['remote_host'], audit_data['timestamp'], json.dumps(audit_data))
)
conn.commit()
```

### Data Analysis

```python
import json
import pandas as pd
from pathlib import Path

# Load all audit files
audits = []
for file in Path('audit').rglob('linux-audit-*.json'):
    with open(file) as f:
        audits.append(json.load(f))

# Create DataFrame
df = pd.DataFrame(audits)

# Analyze
print(f"Total audits: {len(df)}")
print(f"Success rate: {df['success'].mean():.2%}")
print(f"Most audited hosts: {df['remote_host'].value_counts()}")
```

## When to Use Which

### Use Bash Scripts When:
- Manual execution and review
- Need human-readable output
- Quick one-off audits
- Piping to other shell commands
- Working in restricted environments

### Use Python Scripts When:
- Building automation pipelines
- Integrating with APIs or databases
- Need structured data for analysis
- Programmatic processing of results
- Building monitoring/reporting systems
- CI/CD integration

## Both Can Be Used Together

```bash
# Run bash audit (human-readable)
./linux-audit.sh user@host

# Run python audit (machine-readable)
python linux_audit.py user@host

# Now you have both:
# - audit/192.168.1.100/*.txt (for manual review)
# - audit/192.168.1.100/linux-audit-*.json (for automation)
```

## Performance

Both script sets have similar performance:
- Network latency is the primary bottleneck
- SSH connection time dominates execution
- JSON serialization adds negligible overhead
- Text file I/O is comparable to JSON I/O

## Maintenance

- **Bash:** Easier for sysadmins familiar with shell scripting
- **Python:** Better for developers and automation engineers
- **Both:** Well-documented, similar structure, easy to modify

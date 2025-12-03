# SSH Jump Host and ProxyChain Solutions

This guide covers executing commands and scripts on remote hosts through intermediate jump hosts (bastions) without installing software on the intermediate nodes.

## The Problem

You need to access hosts deep in a network through multiple hops:
```
Your Workstation → Kali (Jump Host) → Internal VM → Target Network
```

**Constraints:**
- Cannot install software on jump hosts
- Need to run tools (nmap, scripts, etc.) from internal nodes
- Must traverse multiple network boundaries

## Solutions Overview

### 1. SSH ProxyJump (Recommended)
Built into OpenSSH 7.3+, no additional software needed.

### 2. SSH ProxyCommand (Legacy)
For older SSH versions.

### 3. Dynamic Port Forwarding (SOCKS Proxy)
For tool compatibility with proxychains.

---

## Solution 1: SSH ProxyJump (Native SSH Feature)

### Quick Usage

**Execute single command through jump host:**
```bash
ssh -J user@kali user@internal-vm 'nmap -sn 192.168.1.0/24'
```

**Multiple jump hosts:**
```bash
ssh -J user@kali,admin@internal-vm root@target 'hostname -I'
```

**Copy files through jumps:**
```bash
scp -J user@kali file.txt admin@internal-vm:/tmp/
```

### Using Our Script: `ssh-jump-exec.sh`

**Execute command through jump chain:**
```bash
# Single jump
./ssh-jump-exec.sh -j root@kali -t user@internal-vm -c "nmap -sn 192.168.1.0/24"

# Multiple jumps
./ssh-jump-exec.sh -j root@kali,admin@internal-vm -t user@target -c "ps aux"
```

**Upload and execute local script:**
```bash
# Run audit script on target through jump hosts
./ssh-jump-exec.sh -j root@kali -t user@target -s ./linux-audit.sh

# Keep script on target
./ssh-jump-exec.sh -j root@kali -t user@target -s ./script.sh -u
```

**With SSH key:**
```bash
./ssh-jump-exec.sh -j root@kali -t user@target -k ~/.ssh/id_rsa -c "df -h"
```

### Permanent Configuration: `setup-jump-config.sh`

Run the interactive setup:
```bash
./setup-jump-config.sh
```

This creates SSH config aliases in `~/.ssh/config`:

```ssh-config
Host kali-jump
    HostName kali.example.com
    User root
    Port 22

Host internal-vm
    HostName 192.168.1.100
    User admin
    ProxyJump kali-jump

Host internal-*
    ProxyJump internal-vm
    User root
```

**Then use simple aliases:**
```bash
# Connect to hosts
ssh kali-jump
ssh internal-vm
ssh internal-192.168.2.50  # Automatically uses ProxyJump

# Execute commands
ssh internal-vm 'nmap -sn 192.168.1.0/24'

# Copy files
scp file.txt internal-vm:/tmp/
```

---

## Solution 2: Dynamic Port Forwarding (SOCKS Proxy)

### Setup SOCKS Proxy

**Create SOCKS proxy through jump chain:**
```bash
# SOCKS proxy on localhost:1080 through internal-vm
ssh -D 1080 -J user@kali user@internal-vm -N
```

**Use with proxychains:**

Edit `/etc/proxychains4.conf` (or create local config):
```
[ProxyList]
socks5 127.0.0.1 1080
```

**Then run tools through proxy:**
```bash
proxychains nmap -sn 192.168.2.0/24
proxychains curl http://192.168.2.50
proxychains ssh user@192.168.2.100
```

### Local ProxyChains Config (No root needed)

Create `./proxychains.conf`:
```
strict_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5 127.0.0.1 1080
```

**Use it:**
```bash
proxychains4 -f ./proxychains.conf nmap -sn 192.168.2.0/24
```

---

## Solution 3: Port Forwarding

**Forward specific port through jump chain:**
```bash
# Forward local 8080 to 192.168.2.50:80 through internal-vm
ssh -L 8080:192.168.2.50:80 -J user@kali user@internal-vm -N
```

Then access: `http://localhost:8080`

---

## Practical Examples

### Example 1: Run Nmap from Internal Network

**Without our scripts:**
```bash
ssh -J root@kali user@scanner-vm 'nmap -sn 192.168.1.0/24'
```

**With our script:**
```bash
./ssh-jump-exec.sh -j root@kali -t user@scanner-vm -c "nmap -sn 192.168.1.0/24"
```

**With SOCKS proxy:**
```bash
# Terminal 1: Start proxy
ssh -D 1080 -J root@kali user@scanner-vm -N

# Terminal 2: Use proxy
proxychains nmap -sn 192.168.1.0/24
```

### Example 2: Run Audit Script on Deep Network Host

```bash
# Upload and execute audit script through 2 jumps
./ssh-jump-exec.sh \
    -j root@kali,admin@internal-vm \
    -t user@target-host \
    -s ./linux-audit.sh
```

### Example 3: Interactive Session Through Jumps

```bash
# With SSH config setup
ssh internal-192.168.2.50

# Or manual
ssh -J user@kali,admin@internal-vm root@192.168.2.50
```

### Example 4: Copy Files Through Multiple Hops

```bash
# With SSH config
scp file.tar.gz internal-vm:/tmp/

# Manual with jumps
scp -J user@kali,admin@internal-vm file.tar.gz root@target:/tmp/
```

---

## Cyber Polygon Scenario

**Your setup:**
```
Workstation → Kali (cyber polygon) → Internal VM → Target Network
```

**1. Configure SSH (one-time):**
```bash
./setup-jump-config.sh
```

**2. Run tools from internal VM:**
```bash
# Option A: Direct execution
ssh internal-vm 'nmap -sT 192.168.1.0/24'

# Option B: Using our script
./ssh-jump-exec.sh -j root@kali -t user@internal-vm -c "nmap -sT 192.168.1.0/24"

# Option C: SOCKS proxy
ssh -D 1080 internal-vm -N  # Terminal 1
proxychains nmap -sT 192.168.1.0/24  # Terminal 2
```

**3. Access hosts beyond internal VM:**
```bash
# If internal VM can reach 192.168.2.x
ssh -J root@kali,user@internal-vm root@192.168.2.50 'hostname'
```

---

## Comparison: ProxyJump vs ProxyChains

| Feature | SSH ProxyJump | ProxyChains |
|---------|---------------|-------------|
| **Installation** | Built-in (OpenSSH 7.3+) | Requires proxychains install |
| **Jump Hosts** | No software needed | No software needed |
| **Tool Support** | SSH, SCP only | Any TCP tool |
| **Configuration** | SSH config | /etc/proxychains.conf |
| **Performance** | Native, fast | Slightly slower |
| **Use Case** | SSH-based access | Running any tool remotely |

---

## Troubleshooting

### Connection Issues

**Test each hop:**
```bash
# Test first hop
ssh user@kali 'echo hop1 works'

# Test second hop
ssh -J user@kali admin@internal-vm 'echo hop2 works'

# Test third hop
ssh -J user@kali,admin@internal-vm root@target 'echo hop3 works'
```

**Verbose mode:**
```bash
ssh -v -J user@kali user@internal-vm
```

### Permission Issues

Ensure you have:
- SSH access to all hosts in chain
- Each jump host can reach the next hop
- Proper SSH keys configured

### Port Issues

Specify non-standard ports:
```bash
ssh -J user@kali:2222,admin@internal-vm:22 root@target:2222 'command'
```

---

## Security Notes

- **Jump hosts see your traffic** - they decrypt and re-encrypt
- **Use SSH keys** instead of passwords for automation
- **Limit jump host access** - only authorized users
- **Monitor jump host logs** - track who accessed what
- **Consider VPN** for frequent access to internal networks

---

## Quick Reference

| Task | Command |
|------|---------|
| Execute command | `ssh -J jump target 'command'` |
| Copy file | `scp -J jump file target:path` |
| Multiple jumps | `ssh -J jump1,jump2 target 'cmd'` |
| SOCKS proxy | `ssh -D 1080 -J jump target -N` |
| Port forward | `ssh -L local:remote:port -J jump target -N` |
| Interactive | `ssh -J jump target` |
| With key | `ssh -i key -J jump target` |

---

## Scripts in This Directory

- **`ssh-jump-exec.sh`** - Execute commands/scripts through jump hosts
- **`setup-jump-config.sh`** - Configure SSH config for jump chains
- **`linux-audit.sh`** - Can be executed remotely through jumps

All scripts support jump host scenarios without requiring software installation on intermediate nodes.

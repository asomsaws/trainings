#!/usr/bin/env python3
"""
Description: Comprehensive Linux system audit script via SSH
Usage: python linux_audit.py <remote_user@remote_host> [options]
Dependencies: ssh, sudo access on remote host
"""

import sys
import subprocess
import json
import argparse
from datetime import datetime
from pathlib import Path
import socket


class LinuxAuditor:
    def __init__(self, remote_host, ssh_key=None, output_dir="./audit"):
        self.remote_host = remote_host
        self.ssh_key = ssh_key
        self.output_dir = Path(output_dir)
        self.timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        
        # Extract remote IP
        self.remote_ip = self.extract_ip()
        self.audit_dir = self.output_dir / self.remote_ip
        
        self.result = {
            "audit_type": "linux_system_audit",
            "timestamp": datetime.now().isoformat(),
            "remote_host": remote_host,
            "remote_ip": self.remote_ip,
            "audited_by": f"{os.getenv('USER')}@{socket.gethostname()}",
            "audit_sections": {},
            "errors": []
        }

    def extract_ip(self):
        """Extract IP address from remote host"""
        try:
            addr = self.remote_host.split('@')[-1]
            # Try to get actual IP
            result = self.ssh_exec("hostname -I | awk '{print $1}'")
            if result['success'] and result['stdout']:
                return result['stdout'].strip()
            return addr
        except:
            return self.remote_host.split('@')[-1]

    def ssh_exec(self, command, use_sudo=False):
        """Execute command on remote host via SSH"""
        try:
            ssh_cmd = ['ssh']
            
            if self.ssh_key:
                ssh_cmd.extend(['-i', self.ssh_key])
            
            ssh_cmd.extend([
                '-o', 'StrictHostKeyChecking=accept-new',
                '-o', 'ConnectTimeout=10',
                self.remote_host
            ])
            
            if use_sudo:
                ssh_cmd.append(f"sudo bash -c '{command}'")
            else:
                ssh_cmd.append(command)
            
            result = subprocess.run(
                ssh_cmd,
                capture_output=True,
                text=True,
                timeout=60
            )
            
            return {
                'success': result.returncode == 0,
                'stdout': result.stdout,
                'stderr': result.stderr,
                'returncode': result.returncode
            }
        except Exception as e:
            return {
                'success': False,
                'stdout': '',
                'stderr': str(e),
                'returncode': -1
            }

    def audit_system_info(self):
        """Collect system information"""
        print("Collecting system information...")
        
        commands = {
            "hostname": "hostname",
            "os_release": "cat /etc/os-release",
            "kernel": "uname -a",
            "uptime": "uptime",
            "cpu_info": "lscpu | head -20",
            "memory": "free -h",
            "hardware": "sudo dmidecode -t system 2>/dev/null | head -30 || echo 'dmidecode not available'"
        }
        
        section_data = {}
        for key, cmd in commands.items():
            result = self.ssh_exec(cmd, use_sudo='sudo' in cmd)
            if result['success']:
                section_data[key] = result['stdout'].strip()
            else:
                section_data[key] = f"Error: {result['stderr']}"
        
        self.result['audit_sections']['system_info'] = section_data

    def audit_users(self):
        """Collect user account information"""
        print("Collecting user accounts...")
        
        commands = {
            "passwd": "cat /etc/passwd",
            "groups": "cat /etc/group",
            "login_users": "grep -v 'nologin\\|false' /etc/passwd",
            "sudo_members": "getent group sudo 2>/dev/null || getent group wheel 2>/dev/null || echo 'No sudo/wheel group'",
            "recent_logins": "last -n 20 2>/dev/null || echo 'last command not available'",
            "current_users": "w 2>/dev/null || who"
        }
        
        section_data = {}
        for key, cmd in commands.items():
            result = self.ssh_exec(cmd)
            if result['success']:
                section_data[key] = result['stdout'].strip()
        
        self.result['audit_sections']['users'] = section_data

    def audit_password_hashes(self):
        """Collect password hashes (requires sudo)"""
        print("Collecting password hashes...")
        
        result = self.ssh_exec("cat /etc/shadow", use_sudo=True)
        if result['success']:
            self.result['audit_sections']['password_hashes'] = result['stdout'].strip()
        else:
            self.result['audit_sections']['password_hashes'] = f"Error: {result['stderr']}"

    def audit_network(self):
        """Collect network configuration"""
        print("Collecting network configuration...")
        
        commands = {
            "ip_addresses": "ip addr show || ifconfig",
            "routing": "ip route show || route -n",
            "dns": "cat /etc/resolv.conf",
            "hosts": "cat /etc/hosts",
            "connections": "ss -tunap 2>/dev/null || netstat -tunap 2>/dev/null",
            "listening": "ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null"
        }
        
        section_data = {}
        for key, cmd in commands.items():
            result = self.ssh_exec(cmd)
            if result['success']:
                section_data[key] = result['stdout'].strip()
        
        self.result['audit_sections']['network'] = section_data

    def audit_packages(self):
        """Collect installed packages"""
        print("Collecting installed packages...")
        
        # Try dpkg first, then rpm
        cmd = "if command -v dpkg &>/dev/null; then dpkg -l; elif command -v rpm &>/dev/null; then rpm -qa; else echo 'No supported package manager'; fi"
        
        result = self.ssh_exec(cmd)
        if result['success']:
            self.result['audit_sections']['packages'] = result['stdout'].strip()

    def audit_services(self):
        """Collect running services"""
        print("Collecting services...")
        
        commands = {
            "running": "systemctl list-units --type=service --state=running 2>/dev/null || echo 'systemd not available'",
            "all_services": "systemctl list-units --type=service --all 2>/dev/null || service --status-all 2>/dev/null",
            "enabled": "systemctl list-unit-files --type=service --state=enabled 2>/dev/null || echo 'Cannot list enabled services'"
        }
        
        section_data = {}
        for key, cmd in commands.items():
            result = self.ssh_exec(cmd)
            if result['success']:
                section_data[key] = result['stdout'].strip()
        
        self.result['audit_sections']['services'] = section_data

    def audit_firewall(self):
        """Collect firewall configuration"""
        print("Collecting firewall rules...")
        
        commands = {
            "iptables": "sudo iptables -L -n -v 2>/dev/null || echo 'iptables not available'",
            "ufw": "sudo ufw status verbose 2>/dev/null || echo 'ufw not installed'",
            "firewalld": "sudo firewall-cmd --list-all 2>/dev/null || echo 'firewalld not installed'"
        }
        
        section_data = {}
        for key, cmd in commands.items():
            result = self.ssh_exec(cmd, use_sudo=True)
            if result['success']:
                section_data[key] = result['stdout'].strip()
        
        self.result['audit_sections']['firewall'] = section_data

    def audit_ssh_config(self):
        """Collect SSH configuration"""
        print("Collecting SSH configuration...")
        
        commands = {
            "sshd_config": "sudo cat /etc/ssh/sshd_config 2>/dev/null || echo 'Cannot read sshd_config'",
            "ssh_config": "cat /etc/ssh/ssh_config 2>/dev/null || echo 'Cannot read ssh_config'",
            "authorized_keys": "cat ~/.ssh/authorized_keys 2>/dev/null || echo 'No authorized_keys'"
        }
        
        section_data = {}
        for key, cmd in commands.items():
            result = self.ssh_exec(cmd, use_sudo='sudo' in cmd)
            if result['success']:
                section_data[key] = result['stdout'].strip()
        
        self.result['audit_sections']['ssh_config'] = section_data

    def audit_cron_jobs(self):
        """Collect scheduled tasks"""
        print("Collecting cron jobs...")
        
        cmd = """
        for user in $(cut -f1 -d: /etc/passwd); do
            echo "Crontab for $user:"
            sudo crontab -u $user -l 2>/dev/null || echo 'No crontab'
            echo ''
        done
        echo '--- /etc/crontab ---'
        cat /etc/crontab 2>/dev/null || echo 'No /etc/crontab'
        """
        
        result = self.ssh_exec(cmd, use_sudo=True)
        if result['success']:
            self.result['audit_sections']['cron_jobs'] = result['stdout'].strip()

    def audit_file_permissions(self):
        """Collect critical file permissions"""
        print("Collecting file permissions...")
        
        cmd = """
        echo '--- Critical System Files ---'
        ls -la /etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers 2>/dev/null
        echo ''
        echo '--- SSH Directory ---'
        ls -la /etc/ssh/ 2>/dev/null
        echo ''
        echo '--- Sudoers.d ---'
        sudo ls -la /etc/sudoers.d/ 2>/dev/null || echo 'Cannot access sudoers.d'
        echo ''
        echo '--- SUID/SGID Files (sample) ---'
        sudo find / -type f \\( -perm -4000 -o -perm -2000 \\) -ls 2>/dev/null | head -50 || echo 'Cannot search SUID/SGID'
        """
        
        result = self.ssh_exec(cmd, use_sudo=True)
        if result['success']:
            self.result['audit_sections']['file_permissions'] = result['stdout'].strip()

    def audit_disk_usage(self):
        """Collect disk usage information"""
        print("Collecting disk usage...")
        
        commands = {
            "df": "df -h",
            "mounts": "mount",
            "fstab": "cat /etc/fstab 2>/dev/null || echo 'Cannot read fstab'",
            "block_devices": "lsblk 2>/dev/null || echo 'lsblk not available'"
        }
        
        section_data = {}
        for key, cmd in commands.items():
            result = self.ssh_exec(cmd)
            if result['success']:
                section_data[key] = result['stdout'].strip()
        
        self.result['audit_sections']['disk_usage'] = section_data

    def audit_processes(self):
        """Collect running processes"""
        print("Collecting process list...")
        
        commands = {
            "all_processes": "ps auxf 2>/dev/null || ps aux",
            "top_cpu": "ps aux --sort=-%cpu | head -20",
            "top_memory": "ps aux --sort=-%mem | head -20"
        }
        
        section_data = {}
        for key, cmd in commands.items():
            result = self.ssh_exec(cmd)
            if result['success']:
                section_data[key] = result['stdout'].strip()
        
        self.result['audit_sections']['processes'] = section_data

    def save_output(self):
        """Save audit results to JSON file"""
        try:
            self.audit_dir.mkdir(parents=True, exist_ok=True)
            output_file = self.audit_dir / f"linux-audit-{self.timestamp}.json"
            
            with open(output_file, 'w') as f:
                json.dump(self.result, f, indent=2)
            
            print(f"\n✓ Audit complete!")
            print(f"Output saved to: {output_file}")
            print(f"Audit directory: {self.audit_dir}")
            
            return str(output_file)
        except Exception as e:
            print(f"Error saving output: {e}", file=sys.stderr)
            return None

    def run(self):
        """Execute the full audit"""
        print(f"Starting Linux system audit of: {self.remote_host}")
        print(f"Target IP: {self.remote_ip}\n")
        
        # Test connectivity
        print("Testing SSH connection...")
        test = self.ssh_exec("echo 'Connection successful'")
        if not test['success']:
            print(f"Error: Cannot connect to {self.remote_host}")
            self.result['errors'].append("SSH connection failed")
            self.save_output()
            return False
        print("✓ Connected\n")
        
        # Run all audit sections
        try:
            self.audit_system_info()
            self.audit_users()
            self.audit_password_hashes()
            self.audit_network()
            self.audit_packages()
            self.audit_services()
            self.audit_firewall()
            self.audit_ssh_config()
            self.audit_cron_jobs()
            self.audit_file_permissions()
            self.audit_disk_usage()
            self.audit_processes()
        except KeyboardInterrupt:
            print("\n\nAudit interrupted by user")
            self.result['errors'].append("Audit interrupted")
        except Exception as e:
            print(f"\nError during audit: {e}")
            self.result['errors'].append(str(e))
        
        self.save_output()
        return True


def main():
    parser = argparse.ArgumentParser(
        description='Comprehensive Linux system audit via SSH',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('remote_host', help='Remote host (user@host)')
    parser.add_argument('-k', '--key', help='SSH private key path')
    parser.add_argument('-o', '--output', default='./audit', help='Output directory')
    
    args = parser.parse_args()
    
    auditor = LinuxAuditor(args.remote_host, ssh_key=args.key, output_dir=args.output)
    success = auditor.run()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    import os
    main()

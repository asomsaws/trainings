#!/usr/bin/env python3
"""
Description: Execute commands/scripts on remote hosts through SSH jump hosts
Usage: python ssh_jump_exec.py -j jumphost1[,jumphost2] -t target -c "command"
Dependencies: ssh (OpenSSH 7.3+ for ProxyJump support)
"""

import sys
import subprocess
import json
import argparse
import os
from datetime import datetime
from pathlib import Path
import tempfile


class SSHJumpExecutor:
    def __init__(self, jump_hosts, target_host, command=None, script=None,
                 ssh_key=None, save_output=True, output_dir="./audit"):
        self.jump_hosts = jump_hosts
        self.target_host = target_host
        self.command = command
        self.script = script
        self.ssh_key = ssh_key
        self.save_output = save_output
        self.output_dir = Path(output_dir)
        self.timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        
        # Extract target IP
        self.target_ip = self.get_target_ip()
        self.audit_dir = self.output_dir / self.target_ip
        
        self.result = {
            "operation": "ssh_jump_exec",
            "timestamp": datetime.now().isoformat(),
            "jump_chain": jump_hosts,
            "target_host": target_host,
            "target_ip": self.target_ip,
            "command": command,
            "script": script,
            "executed_by": f"{os.getenv('USER')}@{os.uname().nodename}",
            "success": False,
            "output": "",
            "errors": []
        }

    def get_target_ip(self):
        """Get actual IP of target host"""
        try:
            # Build ProxyJump command
            ssh_cmd = self.build_ssh_command(["hostname -I | awk '{print $1}'"])
            
            result = subprocess.run(
                ssh_cmd,
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0 and result.stdout:
                return result.stdout.strip()
        except:
            pass
        
        # Fallback to target address
        addr = self.target_host.split('@')[-1]
        return addr.split(':')[0]

    def build_ssh_command(self, command_args):
        """Build SSH command with ProxyJump"""
        ssh_cmd = ['ssh']
        
        if self.ssh_key:
            ssh_cmd.extend(['-i', self.ssh_key])
        
        ssh_cmd.extend([
            '-o', 'StrictHostKeyChecking=accept-new',
            '-o', 'ConnectTimeout=10',
            '-J', self.jump_hosts,
            self.target_host
        ])
        
        if isinstance(command_args, list):
            ssh_cmd.extend(command_args)
        else:
            ssh_cmd.append(command_args)
        
        return ssh_cmd

    def test_connectivity(self):
        """Test SSH connection through jump chain"""
        print("Testing connectivity through jump chain...")
        
        try:
            ssh_cmd = self.build_ssh_command(["echo 'Connection successful'"])
            
            result = subprocess.run(
                ssh_cmd,
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                print("✓ Connection successful\n")
                return True
            else:
                print(f"✗ Connection failed")
                self.result['errors'].append(f"Connection test failed: {result.stderr}")
                return False
        except Exception as e:
            print(f"✗ Connection failed: {e}")
            self.result['errors'].append(str(e))
            return False

    def execute_command(self):
        """Execute command on target through jump hosts"""
        print(f"Executing command on {self.target_host}...")
        print("-----------------------------------")
        
        try:
            ssh_cmd = self.build_ssh_command([self.command])
            
            result = subprocess.run(
                ssh_cmd,
                capture_output=True,
                text=True,
                timeout=300
            )
            
            output = result.stdout + result.stderr
            print(output)
            
            self.result['output'] = output
            self.result['exit_code'] = result.returncode
            self.result['success'] = result.returncode == 0
            
            print("-----------------------------------")
            if result.returncode == 0:
                print("✓ Command executed successfully")
            else:
                print(f"✗ Command failed with exit code: {result.returncode}")
            
            return result.returncode == 0
            
        except Exception as e:
            print(f"✗ Error executing command: {e}")
            self.result['errors'].append(str(e))
            return False

    def execute_script(self, keep_script=False):
        """Upload and execute script on target"""
        print(f"Uploading script to {self.target_host}...")
        
        script_name = Path(self.script).name
        remote_script = f"/tmp/{script_name}.{os.getpid()}"
        
        try:
            # Upload script
            scp_cmd = ['scp']
            
            if self.ssh_key:
                scp_cmd.extend(['-i', self.ssh_key])
            
            scp_cmd.extend([
                '-o', 'StrictHostKeyChecking=accept-new',
                '-o', 'ConnectTimeout=10',
                '-J', self.jump_hosts,
                self.script,
                f"{self.target_host}:{remote_script}"
            ])
            
            result = subprocess.run(scp_cmd, capture_output=True, text=True)
            
            if result.returncode != 0:
                print(f"✗ Failed to upload script: {result.stderr}")
                self.result['errors'].append(f"Upload failed: {result.stderr}")
                return False
            
            print("✓ Script uploaded")
            
            # Make executable
            chmod_cmd = self.build_ssh_command([f"chmod +x {remote_script}"])
            subprocess.run(chmod_cmd, capture_output=True)
            
            # Execute script
            print(f"Executing script on {self.target_host}...")
            print("-----------------------------------")
            
            exec_cmd = self.build_ssh_command([remote_script])
            result = subprocess.run(exec_cmd, capture_output=True, text=True, timeout=300)
            
            output = result.stdout + result.stderr
            print(output)
            
            self.result['output'] = output
            self.result['exit_code'] = result.returncode
            self.result['success'] = result.returncode == 0
            self.result['remote_script_path'] = remote_script
            
            print("-----------------------------------")
            
            # Cleanup unless keeping script
            if not keep_script:
                print("Cleaning up...")
                cleanup_cmd = self.build_ssh_command([f"rm -f {remote_script}"])
                subprocess.run(cleanup_cmd, capture_output=True)
                print("✓ Cleanup complete")
            else:
                print(f"Script kept on target: {remote_script}")
            
            if result.returncode == 0:
                print("✓ Script executed successfully")
            else:
                print(f"✗ Script failed with exit code: {result.returncode}")
            
            return result.returncode == 0
            
        except Exception as e:
            print(f"✗ Error executing script: {e}")
            self.result['errors'].append(str(e))
            return False

    def save_output_file(self):
        """Save execution output to JSON file"""
        if not self.save_output:
            return
        
        try:
            self.audit_dir.mkdir(parents=True, exist_ok=True)
            
            if self.command:
                main_cmd = self.command.split()[0].replace('/', '_')
                output_file = self.audit_dir / f"{main_cmd}-{self.timestamp}.json"
            else:
                script_name = Path(self.script).stem
                output_file = self.audit_dir / f"script-{script_name}-{self.timestamp}.json"
            
            with open(output_file, 'w') as f:
                json.dump(self.result, f, indent=2)
            
            print(f"\n✓ Output saved to: {output_file}")
            
        except Exception as e:
            print(f"Error saving output: {e}", file=sys.stderr)

    def run(self, keep_script=False):
        """Execute the SSH jump operation"""
        print("========================================")
        print("  SSH Jump Host Execution")
        print("========================================")
        print(f"Jump Chain: {self.jump_hosts}")
        print(f"Target: {self.target_host} ({self.target_ip})")
        if self.command:
            print(f"Command: {self.command}")
        if self.script:
            print(f"Script: {self.script}")
        if self.save_output:
            print(f"Output Dir: {self.audit_dir}")
        print()
        
        # Test connectivity
        if not self.test_connectivity():
            self.save_output_file()
            return False
        
        # Execute command or script
        if self.command:
            success = self.execute_command()
        elif self.script:
            success = self.execute_script(keep_script)
        else:
            print("Error: No command or script specified")
            return False
        
        # Save output
        self.save_output_file()
        
        print()
        print("========================================")
        print("  Execution Complete")
        print("========================================")
        
        if self.save_output:
            print(f"Output directory: {self.audit_dir}")
        
        return success


def main():
    parser = argparse.ArgumentParser(
        description='Execute commands/scripts through SSH jump hosts',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('-j', '--jump', required=True,
                       help='Comma-separated jump hosts (user@host,user@host)')
    parser.add_argument('-t', '--target', required=True,
                       help='Target host (user@host)')
    parser.add_argument('-c', '--command', help='Command to execute')
    parser.add_argument('-s', '--script', help='Script file to upload and execute')
    parser.add_argument('-k', '--key', help='SSH private key path')
    parser.add_argument('-u', '--upload', action='store_true',
                       help='Keep uploaded script on target')
    parser.add_argument('-n', '--no-save', action='store_true',
                       help='Do not save output to file')
    parser.add_argument('-o', '--output', default='./audit',
                       help='Output directory (default: ./audit)')
    
    args = parser.parse_args()
    
    if not args.command and not args.script:
        print("Error: Either --command or --script must be specified")
        parser.print_help()
        sys.exit(1)
    
    if args.script and not Path(args.script).exists():
        print(f"Error: Script file not found: {args.script}")
        sys.exit(1)
    
    executor = SSHJumpExecutor(
        jump_hosts=args.jump,
        target_host=args.target,
        command=args.command,
        script=args.script,
        ssh_key=args.key,
        save_output=not args.no_save,
        output_dir=args.output
    )
    
    success = executor.run(keep_script=args.upload)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()

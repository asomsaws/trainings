#!/usr/bin/env python3
"""
Description: SSH routing manager for complex multi-hop network topologies  
Usage: python ssh_router.py -r routes.json -t target -c "command"
Dependencies: ssh (OpenSSH 7.3+)
"""

import sys
import subprocess
import json
import argparse
import ipaddress
import os
from datetime import datetime
from pathlib import Path


class SSHRouter:
    def __init__(self, routes_file, target_host, command=None, script=None,
                 ssh_key=None, save_output=True, output_dir="./audit"):
        self.routes_file = routes_file
        self.target_host = target_host
        self.command = command
        self.script = script
        self.ssh_key = ssh_key
        self.save_output = save_output
        self.output_dir = Path(output_dir)
        self.timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        
        self.routes = self.load_routes()
        self.target_ip = self.extract_ip()
        self.jump_chain = self.find_route()
        self.audit_dir = self.output_dir / self.target_ip
        
        self.result = {
            "operation": "ssh_router",
            "timestamp": datetime.now().isoformat(),
            "target_host": target_host,
            "target_ip": self.target_ip,
            "route": self.jump_chain,
            "command": command,
            "script": script,
            "executed_by": f"{os.getenv('USER')}@{os.uname().nodename}",
            "success": False,
            "output": "",
            "errors": []
        }

    def load_routes(self):
        """Load routes from JSON file"""
        try:
            with open(self.routes_file, 'r') as f:
                routes_data = json.load(f)
            
            if 'routes' not in routes_data:
                print(f"Error: 'routes' key not found in {self.routes_file}")
                sys.exit(1)
            
            return routes_data['routes']
        except FileNotFoundError:
            print(f"Error: Routes file not found: {self.routes_file}")
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in routes file: {e}")
            sys.exit(1)

    def extract_ip(self):
        """Extract IP from target host"""
        addr = self.target_host.split('@')[-1]
        addr = addr.split(':')[0]
        
        # Check if it's already an IP
        try:
            ipaddress.ip_address(addr)
            return addr
        except ValueError:
            # Try to resolve hostname
            try:
                import socket
                return socket.gethostbyname(addr)
            except:
                return addr

    def ip_in_network(self, ip, network):
        """Check if IP is in network CIDR"""
        try:
            return ipaddress.ip_address(ip) in ipaddress.ip_network(network)
        except:
            return False

    def find_route(self):
        """Find appropriate route for target IP"""
        default_route = None
        
        for route in self.routes:
            network = route.get('network')
            jump_chain = route.get('via')
            
            if network == 'default':
                default_route = jump_chain
                continue
            
            if network == 'direct':
                continue
            
            # Check if target IP matches this network
            if self.ip_in_network(self.target_ip, network):
                return jump_chain
        
        # Return default route if no match
        if default_route:
            return default_route
        
        print(f"Error: No route found for {self.target_ip}")
        sys.exit(1)

    def list_routes(self):
        """List all configured routes"""
        print("========================================")
        print("  SSH Routes Configuration")
        print("========================================")
        print(f"Routes File: {self.routes_file}\n")
        
        for idx, route in enumerate(self.routes, 1):
            network = route.get('network', 'unknown')
            jump_chain = route.get('via', '')
            description = route.get('description', '')
            
            if network == 'default':
                print(f"Route {idx}: DEFAULT ROUTE")
            else:
                print(f"Route {idx}: {network}")
            
            if description:
                print(f"  Description: {description}")
            
            if jump_chain == 'direct':
                print("  Jump Chain: DIRECT (no jump host)")
            else:
                print(f"  Jump Chain: {jump_chain}")
                
                # Test connectivity
                first_hop = jump_chain.split(',')[0]
                print(f"  Testing... ", end='', flush=True)
                
                try:
                    result = subprocess.run(
                        ['ssh', '-o', 'ConnectTimeout=5', 
                         '-o', 'StrictHostKeyChecking=accept-new',
                         first_hop, 'echo ok'],
                        capture_output=True,
                        timeout=10
                    )
                    if result.returncode == 0:
                        print("✓ Reachable")
                    else:
                        print("✗ Unreachable")
                except:
                    print("✗ Unreachable")
            
            print()
        
        print("========================================")
        print(f"Total routes configured: {len(self.routes)}")
        print("========================================")

    def build_ssh_command(self, command_args, use_jump=True):
        """Build SSH command"""
        ssh_cmd = ['ssh']
        
        if self.ssh_key:
            ssh_cmd.extend(['-i', self.ssh_key])
        
        ssh_cmd.extend([
            '-o', 'StrictHostKeyChecking=accept-new',
            '-o', 'ConnectTimeout=10'
        ])
        
        if use_jump and self.jump_chain != 'direct':
            ssh_cmd.extend(['-J', self.jump_chain])
        
        ssh_cmd.append(self.target_host)
        
        if isinstance(command_args, list):
            ssh_cmd.extend(command_args)
        else:
            ssh_cmd.append(command_args)
        
        return ssh_cmd

    def test_connectivity(self):
        """Test connection through route"""
        print("Testing connectivity...")
        
        try:
            use_jump = self.jump_chain != 'direct'
            ssh_cmd = self.build_ssh_command(["echo 'ok'"], use_jump=use_jump)
            
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
                print("✗ Connection failed")
                self.result['errors'].append("Connection test failed")
                return False
        except Exception as e:
            print(f"✗ Connection failed: {e}")
            self.result['errors'].append(str(e))
            return False

    def execute_command(self):
        """Execute command on target"""
        print(f"Executing command on {self.target_host}...")
        print("-----------------------------------")
        
        try:
            use_jump = self.jump_chain != 'direct'
            ssh_cmd = self.build_ssh_command([self.command], use_jump=use_jump)
            
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
                print(f"✗ Command failed (exit code: {result.returncode})")
            
            return result.returncode == 0
            
        except Exception as e:
            print(f"✗ Error: {e}")
            self.result['errors'].append(str(e))
            return False

    def execute_script(self, keep_script=False):
        """Upload and execute script"""
        print(f"Uploading script to {self.target_host}...")
        
        script_name = Path(self.script).name
        remote_script = f"/tmp/{script_name}.{os.getpid()}"
        
        try:
            # Upload script
            scp_cmd = ['scp']
            
            if self.ssh_key:
                scp_cmd.extend(['-i', self.ssh_key])
            
            scp_cmd.extend(['-o', 'StrictHostKeyChecking=accept-new'])
            
            if self.jump_chain != 'direct':
                scp_cmd.extend(['-o', f'ProxyJump={self.jump_chain}'])
            
            scp_cmd.extend([self.script, f"{self.target_host}:{remote_script}"])
            
            result = subprocess.run(scp_cmd, capture_output=True)
            
            if result.returncode != 0:
                print("✗ Failed to upload script")
                return False
            
            print("✓ Script uploaded")
            
            # Make executable and execute
            use_jump = self.jump_chain != 'direct'
            chmod_cmd = self.build_ssh_command([f"chmod +x {remote_script}"], use_jump=use_jump)
            subprocess.run(chmod_cmd, capture_output=True)
            
            print(f"Executing script on {self.target_host}...")
            print("-----------------------------------")
            
            exec_cmd = self.build_ssh_command([remote_script], use_jump=use_jump)
            result = subprocess.run(exec_cmd, capture_output=True, text=True, timeout=300)
            
            output = result.stdout + result.stderr
            print(output)
            
            self.result['output'] = output
            self.result['exit_code'] = result.returncode
            self.result['success'] = result.returncode == 0
            
            print("-----------------------------------")
            
            # Cleanup
            if not keep_script:
                print("Cleaning up...")
                cleanup_cmd = self.build_ssh_command([f"rm -f {remote_script}"], use_jump=use_jump)
                subprocess.run(cleanup_cmd, capture_output=True)
                print("✓ Cleanup complete")
            
            if result.returncode == 0:
                print("✓ Script executed successfully")
            else:
                print(f"✗ Script failed (exit code: {result.returncode})")
            
            return result.returncode == 0
            
        except Exception as e:
            print(f"✗ Error: {e}")
            self.result['errors'].append(str(e))
            return False

    def save_output_file(self):
        """Save execution output to JSON"""
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
            
            print(f"\n✓ Output: {output_file}")
            
        except Exception as e:
            print(f"Error saving output: {e}", file=sys.stderr)

    def run(self, keep_script=False):
        """Execute the routing operation"""
        print("========================================")
        print("  SSH Router - Auto Route Selection")
        print("========================================")
        print(f"Target Host: {self.target_host}")
        print(f"Target IP: {self.target_ip}")
        
        if self.jump_chain == 'direct':
            print("Route: DIRECT (no jump host)")
        else:
            print(f"Route: {self.jump_chain}")
        
        if self.command:
            print(f"Command: {self.command}")
        if self.script:
            print(f"Script: {self.script}")
        print()
        
        # Test connectivity
        if not self.test_connectivity():
            self.save_output_file()
            return False
        
        # Execute
        if self.command:
            success = self.execute_command()
        elif self.script:
            success = self.execute_script(keep_script)
        else:
            print("Error: No command or script specified")
            return False
        
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
        description='SSH routing with automatic jump chain selection',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('-r', '--routes', required=True,
                       help='Routes configuration JSON file')
    parser.add_argument('-t', '--target', help='Target host (user@host)')
    parser.add_argument('-c', '--command', help='Command to execute')
    parser.add_argument('-s', '--script', help='Script file to execute')
    parser.add_argument('-k', '--key', help='SSH private key path')
    parser.add_argument('-l', '--list', action='store_true',
                       help='List configured routes')
    parser.add_argument('-u', '--upload', action='store_true',
                       help='Keep uploaded script on target')
    parser.add_argument('-n', '--no-save', action='store_true',
                       help='Do not save output')
    parser.add_argument('-o', '--output', default='./audit',
                       help='Output directory')
    
    args = parser.parse_args()
    
    # List routes mode
    if args.list:
        router = SSHRouter(args.routes, 'dummy@localhost')
        router.list_routes()
        sys.exit(0)
    
    # Execution mode
    if not args.target:
        print("Error: --target is required")
        parser.print_help()
        sys.exit(1)
    
    if not args.command and not args.script:
        print("Error: Either --command or --script must be specified")
        parser.print_help()
        sys.exit(1)
    
    router = SSHRouter(
        routes_file=args.routes,
        target_host=args.target,
        command=args.command,
        script=args.script,
        ssh_key=args.key,
        save_output=not args.no_save,
        output_dir=args.output
    )
    
    success = router.run(keep_script=args.upload)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()

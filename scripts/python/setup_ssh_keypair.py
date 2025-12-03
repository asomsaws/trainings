#!/usr/bin/env python3
"""
Description: Generate SSH key pair and configure key-based authentication on remote Linux host
Usage: python setup_ssh_keypair.py <remote_user@remote_host> [options]
Dependencies: ssh, ssh-keygen, ssh-copy-id
"""

import sys
import subprocess
import json
import os
import argparse
from datetime import datetime
from pathlib import Path


class SSHKeyPairSetup:
    def __init__(self, remote_host, key_type='ed25519', key_size=None, key_name=None,
                 key_comment=None, output_dir="./audit"):
        self.remote_host = remote_host
        self.key_type = key_type
        self.key_size = key_size
        self.key_name = key_name or f"id_{key_type}"
        self.key_comment = key_comment or f"{os.getenv('USER')}@{os.uname().nodename}_{datetime.now().strftime('%Y%m%d')}"
        self.ssh_dir = Path.home() / ".ssh"
        self.key_path = self.ssh_dir / self.key_name
        self.output_dir = Path(output_dir)
        self.timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        
        self.result = {
            "operation": "setup_ssh_keypair",
            "timestamp": datetime.now().isoformat(),
            "remote_host": remote_host,
            "key_type": key_type,
            "key_path": str(self.key_path),
            "success": False,
            "steps": [],
            "errors": []
        }

    def log_step(self, step, success, message="", data=None):
        """Log a step in the process"""
        step_info = {
            "step": step,
            "success": success,
            "message": message,
            "timestamp": datetime.now().isoformat()
        }
        if data:
            step_info["data"] = data
        self.result["steps"].append(step_info)

    def log_error(self, error):
        """Log an error"""
        self.result["errors"].append(str(error))

    def create_ssh_dir(self):
        """Create .ssh directory if it doesn't exist"""
        try:
            self.ssh_dir.mkdir(mode=0o700, exist_ok=True)
            self.log_step("create_ssh_dir", True, f"SSH directory ready at {self.ssh_dir}")
            return True
        except Exception as e:
            self.log_error(f"Error creating SSH directory: {e}")
            return False

    def check_existing_key(self):
        """Check if key already exists"""
        if self.key_path.exists():
            self.log_step("check_existing_key", True, f"Key already exists at {self.key_path}")
            return True
        return False

    def generate_key(self):
        """Generate SSH key pair"""
        try:
            cmd = ['ssh-keygen', '-t', self.key_type, '-C', self.key_comment, '-f', str(self.key_path)]
            
            if self.key_size:
                cmd.extend(['-b', str(self.key_size)])
            
            result = subprocess.run(cmd, text=True)
            
            if result.returncode == 0:
                # Set proper permissions
                self.key_path.chmod(0o600)
                Path(f"{self.key_path}.pub").chmod(0o644)
                
                self.log_step("generate_key", True, "SSH key pair generated successfully", {
                    "private_key": str(self.key_path),
                    "public_key": f"{self.key_path}.pub"
                })
                return True
            else:
                self.log_error("Failed to generate SSH key pair")
                return False
        except Exception as e:
            self.log_error(f"Error generating key: {e}")
            return False

    def read_public_key(self):
        """Read the public key content"""
        try:
            pub_key_path = Path(f"{self.key_path}.pub")
            if pub_key_path.exists():
                public_key = pub_key_path.read_text().strip()
                self.result["public_key"] = public_key
                self.log_step("read_public_key", True, "Public key read successfully")
                return public_key
            else:
                self.log_error("Public key file not found")
                return None
        except Exception as e:
            self.log_error(f"Error reading public key: {e}")
            return None

    def copy_key_to_remote(self):
        """Copy public key to remote host"""
        try:
            pub_key_path = f"{self.key_path}.pub"
            
            # Try ssh-copy-id first
            result = subprocess.run(
                ['ssh-copy-id', '-i', pub_key_path, self.remote_host],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                self.log_step("copy_key", True, f"Public key copied to {self.remote_host}")
                return True
            else:
                # Fallback method
                self.log_step("copy_key_ssh_copy_id", False, "ssh-copy-id failed, trying alternative method")
                return self.copy_key_fallback()
        except FileNotFoundError:
            # ssh-copy-id not available
            return self.copy_key_fallback()
        except Exception as e:
            self.log_error(f"Error copying key: {e}")
            return False

    def copy_key_fallback(self):
        """Fallback method to copy key without ssh-copy-id"""
        try:
            pub_key_path = Path(f"{self.key_path}.pub")
            public_key = pub_key_path.read_text()
            
            cmd = f"mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '{public_key}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
            
            result = subprocess.run(
                ['ssh', self.remote_host, cmd],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                self.log_step("copy_key_fallback", True, "Public key copied using fallback method")
                return True
            else:
                self.log_error(f"Failed to copy key: {result.stderr}")
                return False
        except Exception as e:
            self.log_error(f"Error in fallback copy: {e}")
            return False

    def test_connection(self):
        """Test SSH connection with key"""
        try:
            result = subprocess.run(
                ['ssh', '-i', str(self.key_path), '-o', 'BatchMode=yes', 
                 '-o', 'ConnectTimeout=5', self.remote_host, 
                 'echo "SSH key authentication successful"'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                self.log_step("test_connection", True, "Key-based authentication working")
                return True
            else:
                self.log_step("test_connection", False, "Could not verify key-based authentication")
                return False
        except Exception as e:
            self.log_error(f"Error testing connection: {e}")
            return False

    def add_ssh_config(self, host_alias):
        """Add entry to SSH config file"""
        try:
            ssh_config = self.ssh_dir / "config"
            
            # Extract hostname and user
            if '@' in self.remote_host:
                user, hostname = self.remote_host.split('@', 1)
            else:
                user = os.getenv('USER')
                hostname = self.remote_host
            
            config_entry = f"""
# Added by setup_ssh_keypair.py on {datetime.now().strftime('%Y-%m-%d')}
Host {host_alias}
    HostName {hostname}
    User {user}
    IdentityFile {self.key_path}
    IdentitiesOnly yes
"""
            
            with open(ssh_config, 'a') as f:
                f.write(config_entry)
            
            ssh_config.chmod(0o600)
            
            self.log_step("add_ssh_config", True, f"SSH config updated with alias '{host_alias}'")
            return True
        except Exception as e:
            self.log_error(f"Error adding SSH config: {e}")
            return False

    def save_output(self):
        """Save results to JSON file"""
        try:
            self.output_dir.mkdir(parents=True, exist_ok=True)
            remote_clean = self.remote_host.replace('@', '_at_').replace(':', '_')
            output_file = self.output_dir / f"ssh-keypair-{remote_clean}-{self.timestamp}.json"
            
            with open(output_file, 'w') as f:
                json.dump(self.result, f, indent=2)
            
            print(f"\nOutput saved to: {output_file}")
        except Exception as e:
            print(f"Error saving output: {e}", file=sys.stderr)

    def run(self, skip_keygen=False, add_config=None):
        """Execute the SSH key setup process"""
        print(f"Setting up SSH key pair for: {self.remote_host}")
        
        # Create SSH directory
        if not self.create_ssh_dir():
            self.result["success"] = False
            self.save_output()
            return False
        
        # Check for existing key
        key_exists = self.check_existing_key()
        
        # Generate key if needed
        if not key_exists and not skip_keygen:
            if not self.generate_key():
                self.result["success"] = False
                self.save_output()
                return False
        elif key_exists:
            print(f"Using existing key: {self.key_path}")
        
        # Read public key
        if not self.read_public_key():
            self.result["success"] = False
            self.save_output()
            return False
        
        # Copy key to remote
        if not self.copy_key_to_remote():
            self.result["success"] = False
            self.save_output()
            return False
        
        # Test connection
        self.test_connection()
        
        # Add SSH config if requested
        if add_config:
            self.add_ssh_config(add_config)
        
        self.result["success"] = True
        self.save_output()
        
        print(f"\n✓ Success! SSH key-based authentication configured")
        print(f"Key location: {self.key_path}")
        print(f"Connect using: ssh -i {self.key_path} {self.remote_host}")
        
        if add_config:
            print(f"Or simply: ssh {add_config}")
        
        return True


def main():
    parser = argparse.ArgumentParser(
        description='Generate SSH key pair and configure remote authentication',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('remote_host', help='Remote host (user@host)')
    parser.add_argument('-t', '--type', default='ed25519', 
                       choices=['rsa', 'ed25519', 'ecdsa'],
                       help='Key type (default: ed25519)')
    parser.add_argument('-b', '--bits', type=int, help='Key size in bits (for RSA)')
    parser.add_argument('-n', '--name', help='Custom key name')
    parser.add_argument('-c', '--comment', help='Key comment')
    parser.add_argument('-a', '--alias', help='Add SSH config alias')
    parser.add_argument('-o', '--output', default='./audit', help='Output directory for JSON')
    
    args = parser.parse_args()
    
    setup = SSHKeyPairSetup(
        args.remote_host,
        key_type=args.type,
        key_size=args.bits,
        key_name=args.name,
        key_comment=args.comment,
        output_dir=args.output
    )
    
    success = setup.run(add_config=args.alias)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()

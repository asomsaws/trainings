#!/usr/bin/env python3
"""
Description: Create a new user and add them to the sudoers group
Usage: python create_sudo_user.py <username>
Dependencies: Root/sudo privileges required
"""

import sys
import subprocess
import json
import os
import re
from datetime import datetime
from pathlib import Path


class SudoUserCreator:
    def __init__(self, username, output_dir="./audit"):
        self.username = username
        self.output_dir = Path(output_dir)
        self.timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.result = {
            "operation": "create_sudo_user",
            "timestamp": datetime.now().isoformat(),
            "username": username,
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

    def check_root(self):
        """Check if script is run as root"""
        if os.geteuid() != 0:
            self.log_error("Script must be run as root or with sudo")
            return False
        self.log_step("check_root", True, "Running with root privileges")
        return True

    def validate_username(self):
        """Validate username format"""
        pattern = r'^[a-z_][a-z0-9_-]*$'
        if not re.match(pattern, self.username):
            self.log_error(f"Invalid username format: {self.username}")
            return False
        self.log_step("validate_username", True, f"Username '{self.username}' is valid")
        return True

    def user_exists(self):
        """Check if user already exists"""
        try:
            result = subprocess.run(
                ['id', self.username],
                capture_output=True,
                text=True
            )
            exists = result.returncode == 0
            if exists:
                self.log_step("user_exists", True, f"User '{self.username}' already exists")
            return exists
        except Exception as e:
            self.log_error(f"Error checking if user exists: {e}")
            return False

    def create_user(self):
        """Create the user with a home directory"""
        try:
            result = subprocess.run(
                ['useradd', '-m', '-s', '/bin/bash', self.username],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                self.log_step("create_user", True, f"User '{self.username}' created successfully")
                return True
            else:
                self.log_error(f"Failed to create user: {result.stderr}")
                return False
        except Exception as e:
            self.log_error(f"Error creating user: {e}")
            return False

    def set_password(self):
        """Set password for the user (interactive)"""
        try:
            result = subprocess.run(
                ['passwd', self.username],
                text=True
            )
            
            if result.returncode == 0:
                self.log_step("set_password", True, "Password set successfully")
                return True
            else:
                self.log_error("Failed to set password")
                return False
        except Exception as e:
            self.log_error(f"Error setting password: {e}")
            return False

    def get_sudo_group(self):
        """Determine which sudo group exists on the system"""
        try:
            # Check for sudo group (Debian/Ubuntu)
            result = subprocess.run(
                ['getent', 'group', 'sudo'],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                self.log_step("detect_sudo_group", True, "Found 'sudo' group (Debian/Ubuntu)")
                return 'sudo'
            
            # Check for wheel group (RHEL/CentOS)
            result = subprocess.run(
                ['getent', 'group', 'wheel'],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                self.log_step("detect_sudo_group", True, "Found 'wheel' group (RHEL/CentOS)")
                return 'wheel'
            
            self.log_step("detect_sudo_group", False, "No sudo or wheel group found")
            return None
        except Exception as e:
            self.log_error(f"Error detecting sudo group: {e}")
            return None

    def add_to_group(self, group):
        """Add user to specified group"""
        try:
            result = subprocess.run(
                ['usermod', '-aG', group, self.username],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                self.log_step("add_to_group", True, f"User added to '{group}' group")
                return True
            else:
                self.log_error(f"Failed to add user to group: {result.stderr}")
                return False
        except Exception as e:
            self.log_error(f"Error adding user to group: {e}")
            return False

    def create_sudoers_file(self):
        """Create a sudoers file for the user"""
        try:
            sudoers_file = f"/etc/sudoers.d/{self.username}"
            with open(sudoers_file, 'w') as f:
                f.write(f"{self.username} ALL=(ALL:ALL) ALL\n")
            
            os.chmod(sudoers_file, 0o440)
            
            # Validate sudoers file
            result = subprocess.run(
                ['visudo', '-c', '-f', sudoers_file],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                self.log_step("create_sudoers_file", True, f"Sudoers file created at {sudoers_file}")
                return True
            else:
                os.remove(sudoers_file)
                self.log_error(f"Invalid sudoers file, removed: {result.stderr}")
                return False
        except Exception as e:
            self.log_error(f"Error creating sudoers file: {e}")
            return False

    def verify_sudo_access(self):
        """Verify sudo access for the user"""
        try:
            result = subprocess.run(
                ['sudo', '-l', '-U', self.username],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                self.log_step("verify_sudo_access", True, "Sudo access verified")
                return True
            else:
                self.log_step("verify_sudo_access", False, "Could not verify sudo access")
                return False
        except Exception as e:
            self.log_error(f"Error verifying sudo access: {e}")
            return False

    def get_user_info(self):
        """Get user information"""
        try:
            result = subprocess.run(
                ['id', self.username],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                self.result["user_info"] = result.stdout.strip()
                self.log_step("get_user_info", True, "User information retrieved")
        except Exception as e:
            self.log_error(f"Error getting user info: {e}")

    def save_output(self):
        """Save results to JSON file"""
        try:
            self.output_dir.mkdir(parents=True, exist_ok=True)
            output_file = self.output_dir / f"create-sudo-user-{self.username}-{self.timestamp}.json"
            
            with open(output_file, 'w') as f:
                json.dump(self.result, f, indent=2)
            
            print(f"\nOutput saved to: {output_file}")
        except Exception as e:
            print(f"Error saving output: {e}", file=sys.stderr)

    def run(self):
        """Execute the user creation process"""
        print(f"Creating sudo user: {self.username}")
        
        # Check root privileges
        if not self.check_root():
            self.result["success"] = False
            self.save_output()
            return False
        
        # Validate username
        if not self.validate_username():
            self.result["success"] = False
            self.save_output()
            return False
        
        # Check if user exists
        user_existed = self.user_exists()
        
        # Create user if doesn't exist
        if not user_existed:
            if not self.create_user():
                self.result["success"] = False
                self.save_output()
                return False
            
            if not self.set_password():
                self.result["success"] = False
                self.save_output()
                return False
        else:
            print(f"User '{self.username}' already exists. Adding to sudoers...")
        
        # Add to sudo group
        sudo_group = self.get_sudo_group()
        
        if sudo_group:
            if not self.add_to_group(sudo_group):
                self.result["success"] = False
                self.save_output()
                return False
        else:
            # Create sudoers file manually
            if not self.create_sudoers_file():
                self.result["success"] = False
                self.save_output()
                return False
        
        # Verify sudo access
        self.verify_sudo_access()
        
        # Get user info
        self.get_user_info()
        
        self.result["success"] = True
        self.save_output()
        
        print(f"\n✓ Success! User '{self.username}' has been created and granted sudo privileges")
        print("Note: The user may need to log out and back in for group changes to take effect")
        
        return True


def main():
    if len(sys.argv) != 2:
        print("Usage: python create_sudo_user.py <username>")
        print("Example: sudo python create_sudo_user.py john")
        sys.exit(1)
    
    username = sys.argv[1]
    creator = SudoUserCreator(username)
    
    success = creator.run()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()

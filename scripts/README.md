# Scripts

This directory organizes automation scripts by programming language and platform.

## Directory Structure

```
scripts/
├── bash/          # Bash scripts for Linux/Unix systems
├── powershell/    # PowerShell scripts for Windows
└── python/        # Cross-platform Python scripts
```

## Quick Reference

### Bash Scripts (`bash/`)
- **create-sudo-user.sh** - Create users with sudo privileges
- **setup-ssh-keypair.sh** - Generate SSH keys and configure remote authentication

See [bash/README.md](bash/README.md) for detailed documentation.

### PowerShell Scripts (`powershell/`)
*Coming soon - Windows automation scripts*

See [powershell/README.md](powershell/README.md) for guidelines.

### Python Scripts (`python/`)
*Coming soon - Cross-platform automation scripts*

See [python/README.md](python/README.md) for guidelines.

## Usage Guidelines

1. **Choose the appropriate directory** based on your target platform:
   - Linux/Unix → `bash/`
   - Windows → `powershell/`
   - Cross-platform → `python/`

2. **Make scripts executable** (Linux/macOS):
   ```bash
   chmod +x script-name.sh
   ```

3. **Run with appropriate interpreter**:
   ```bash
   # Bash
   ./script-name.sh
   
   # PowerShell
   .\script-name.ps1
   
   # Python
   python script-name.py
   ```

4. **Check individual README files** in each subdirectory for specific script documentation and usage examples.

## Contributing Scripts

When adding new scripts:
1. Place in the correct language directory
2. Follow the header format conventions (see subdirectory READMEs)
3. Include comprehensive error handling
4. Add usage examples and documentation
5. Update the respective subdirectory README.md
6. Test thoroughly before committing

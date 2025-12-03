# Training Repository

A collection of training materials, scripts, and documentation for system administration and automation across Linux and Windows platforms.

## Repository Structure

```
trainings/
├── linux/              # Linux-specific training materials
├── Windows/            # Windows-specific training materials
└── scripts/            # Automation scripts organized by language
    ├── bash/           # Bash scripts for Linux/Unix
    ├── powershell/     # PowerShell scripts for Windows
    └── python/         # Cross-platform Python scripts
```

## Quick Start

### Browse Training Materials
- **Linux**: [linux/README.md](linux/README.md)
- **Windows**: [Windows/README.md](Windows/README.md)

### Explore Scripts
- **Bash Scripts**: [scripts/bash/README.md](scripts/bash/README.md)
  - Create sudo users
  - Setup SSH key-based authentication
- **PowerShell Scripts**: [scripts/powershell/README.md](scripts/powershell/README.md)
- **Python Scripts**: [scripts/python/README.md](scripts/python/README.md)

## Featured Scripts

### Bash (Linux/Unix)

#### User Management
```bash
# Create a new user with sudo privileges
sudo ./scripts/bash/create-sudo-user.sh username
```

#### SSH Key Setup
```bash
# Generate SSH key and configure remote host
./scripts/bash/setup-ssh-keypair.sh user@remote_host

# With custom options
./scripts/bash/setup-ssh-keypair.sh -t rsa -b 4096 admin@server.example.com
```

## Contributing

When adding content to this repository:

1. **Scripts**: Place in the appropriate language directory under `scripts/`
2. **Training Materials**: Add to `linux/` or `Windows/` based on platform
3. **Documentation**: Update relevant README.md files
4. **Follow Conventions**: See [.github/copilot-instructions.md](.github/copilot-instructions.md)

## Guidelines

- Include headers and documentation in all scripts
- Add usage examples and practical demonstrations
- Test scripts before committing
- Keep training materials focused and actionable
- Cross-reference related materials and scripts

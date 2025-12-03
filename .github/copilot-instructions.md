# Copilot Instructions for Trainings Repository

## Repository Purpose

This repository organizes training materials, scripts, and documentation for system administration and automation across multiple platforms and scripting languages.

## Directory Structure

- `linux/` - Linux-specific training materials and documentation
- `Windows/` - Windows-specific training materials and documentation
- `scripts/` - Organized by language/platform:
  - `bash/` - Bash shell scripts for Linux/Unix systems
  - `powershell/` - PowerShell scripts for Windows automation
  - `python/` - Cross-platform Python scripts

## Conventions

### Script Organization

- Place scripts in the appropriate language directory under `scripts/`
- Use descriptive filenames that indicate the script's purpose (e.g., `backup-database.sh`, `deploy-app.ps1`, `monitor-logs.py`)
- Each script should include a header comment block with:
  - Brief description of functionality
  - Usage examples
  - Required dependencies or prerequisites
  - Author and date information

### Training Material Structure

- Training documents go in `linux/` or `Windows/` based on platform
- Use markdown format for documentation
- Include practical examples and command snippets
- Reference related scripts in `scripts/` when applicable

### Script Headers

For Bash scripts:
```bash
#!/usr/bin/env bash
# Description: [What the script does]
# Usage: ./script-name.sh [arguments]
# Dependencies: [Required tools/packages]
```

For PowerShell scripts:
```powershell
<#
.SYNOPSIS
    [Brief description]
.DESCRIPTION
    [Detailed description]
.EXAMPLE
    .\script-name.ps1 -Parameter Value
#>
```

For Python scripts:
```python
#!/usr/bin/env python3
"""
Description: [What the script does]
Usage: python script-name.py [arguments]
Dependencies: [pip packages if any]
"""
```

## Development Workflow

- Test scripts in isolated environments before committing
- Include error handling and input validation
- Use platform-appropriate path separators and conventions
- Document any external dependencies or system requirements

## Creating New Content

When adding training materials:
1. Determine target platform (Linux/Windows/cross-platform)
2. Place documentation in appropriate directory
3. Add supporting scripts to `scripts/[language]/`
4. Cross-reference between docs and scripts
5. Ensure examples are tested and functional

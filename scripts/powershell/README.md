# PowerShell Scripts

This directory contains PowerShell scripts for Windows system administration and automation tasks.

## Available Scripts

*No scripts available yet. Check back later for Windows automation scripts.*

---

## Script Guidelines

When adding PowerShell scripts to this directory:

1. **Use proper script headers:**
   ```powershell
   <#
   .SYNOPSIS
       Brief description
   .DESCRIPTION
       Detailed description
   .PARAMETER ParameterName
       Description of parameter
   .EXAMPLE
       .\script-name.ps1 -Parameter Value
   .NOTES
       Author: Name
       Date: YYYY-MM-DD
   #>
   ```

2. **Follow best practices:**
   - Use approved verbs (Get-, Set-, New-, Remove-, etc.)
   - Include parameter validation
   - Implement proper error handling with Try/Catch
   - Use Write-Verbose for detailed logging
   - Set execution policy requirements if needed

3. **Document in this README:**
   - Script name and purpose
   - Usage examples
   - Required parameters
   - Prerequisites and dependencies
   - Any special permissions needed

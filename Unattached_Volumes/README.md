# README

[CHANGE LOG](./CHANGELOG.md)

## [Get-UnattachedVolumes.ps1](Get-UnattachedVolumes.ps1)
- The script uses basic authentication. SSO user accounts and refresh tokens are not supported.
- PowerShell or [PowerShell CORE](https://github.com/PowerShell/PowerShell) is required
- Uses the Governance module to collect all child projects in the Organization
- Output as CSV in current directory
  - All Volumes that are no longer attached to instances
# README

## Get-OrgUtilizationData.ps1
- The script uses basic authentication. SSO user accounts and refresh tokens are not supported.
- PowerShell or [PowerShell CORE](https://github.com/PowerShell/PowerShell) is required
- Uses the Governance module to collect all child projects in the Organization
- Beginning and end time frame can be entered as just dates, which will set a time of midnight, or fully qualified dates and times.
- Output as CSV in current directory
  - Collects RightLink monitoring data for instances and calculates maximum and average utilization for CPU and memory between two dates.

## Get-VMInformation.ps1
- The script uses basic authentication. SSO user accounts and refresh tokens are not supported.
- PowerShell or [PowerShell CORE](https://github.com/PowerShell/PowerShell) is required
- Uses the Governance module to collect all child projects in the Organization
- Output as CSV in current directory
  - Fields: account, cloud, instance name, vm id, public and private ips, server state, os platform, resource group if any, availability set if any, and tags
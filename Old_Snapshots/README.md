# README

## Get-OldSnapshots.ps1
- The script uses basic authentication. SSO user accounts and refresh tokens are not supported.
- PowerShell or [PowerShell CORE](https://github.com/PowerShell/PowerShell) is required
- Uses the Governance module to collect all child projects in the Organization
- Output as CSV in current directory
  - All Volume Snapshots whose created_at date is older than the input date specified by the user executing this script
- Known Limitations
  - ARM Snapshots likely won't appear in this report unless they meet the age requirement.  This is because if an ARM volume is deleted after a snapshot has been taken, the volume is still reported as an available resource.


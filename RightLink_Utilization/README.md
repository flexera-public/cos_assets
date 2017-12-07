# README
- `rsc` is required to run this script. It can be downloaded from [GitHub - rightscale/rsc](https://github.com/rightscale/rsc)
- We attempt to locate `rsc` by searching for it in $PWD, $HOME, '/usr/local/bin', '/opt/bin/', and 'C:\Program Files\RightScale\RightLink'
- In these scripts, `rsc` uses basic authentication, so SSO user accounts may not be used to authenticate.
- PowerShell or [PowerShell CORE](https://github.com/PowerShell/PowerShell) is required
- Get-VMInformation.ps1 - powershell script that gets account, cloud, instance name, vm id, public and private ips, server state, os platform, resource group if any, availability set if any, and tags

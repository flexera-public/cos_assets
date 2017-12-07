# Get-UnattachedVolumes Script

- PowerShell[https://github.com/PowerShell/PowerShell] or PowerShell CORE is required
- `rsc` is required to run this script. It can be downloaded from [GitHub - rightscale/rsc](https://github.com/rightscale/rsc)
- We attempt to locate `rsc` by searching for it in $PWD, $HOME, '/usr/local/bin', '/opt/bin/', and 'C:\Program Files\RightScale\RightLink'
- In these scripts, `rsc` uses basic authentication, so SSO user accounts may not be used to authenticate. 

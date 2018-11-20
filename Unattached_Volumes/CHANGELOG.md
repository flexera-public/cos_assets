# CHANGELOG

## [Get-UnattachedVolumes.ps1](Get-UnattachedVolumes.ps1)
- Version: 3.0.1
    - RSC binary no longer required
    - Added PowerShell native parameter support
    - Added API call redirection handling, no longer need to specify endpoint
    - Removed call to find child accounts via CM 1.5 API, enterprise_manager role no longer required
    - Child projects in an Organization are now discovered via Governance API based on users access, requires observer at the Org level
    - Bumped minimum required PowerShell version up to 4
    - Added a clean memory function to aid in testing in an IDE/ISE
    - Unified functionality and output across all PowerShell COS scripts
    - Added cmdlet binding support and redirected most console output to verbose and warning streams

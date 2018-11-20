# Source: https://github.com/rs-services/cos_assets
#
# Version: 1.0
#

[CmdletBinding()]
param(
    [System.Management.Automation.PSCredential]$RSCredential,
    [alias("ReportName")]
    [string]$CustomerName,
    [string]$Endpoint = "us-3.rightscale.com",
    [string]$OrganizationID,
    [alias("ParentAccount")]
    [string[]]$Accounts,
    [datetime]$Date,
    [bool]$ExportToCsv = $true
)

## Store all the start up variables so you can clean up when the script finishes.
if ($startupVariables) { 
    try {
        Remove-Variable -Name startupVariables -Scope Global -ErrorAction SilentlyContinue
    }
    catch { }
}
New-Variable -force -name startupVariables -value ( Get-Variable | ForEach-Object { $_.Name } ) 

## Check Runtime environment
if($PSVersionTable.PSVersion.Major -lt 4) {
    Write-Error "This script requires at least PowerShell 4.0."
    EXIT 1
}

#if(!(Test-NetConnection -ComputerName "login.rightscale.com" -Port 443)) {
#    Write-Error "Unable to contact login.rightscale.com. Check you internet connection."
#    EXIT 1
#}

## Create functions
Function Clean-Memory {
    $scriptVariables = Get-Variable | Where-Object { $startupVariables -notcontains $_.Name }
    ForEach($scriptVariable in $scriptVariables) {
        try {
            Remove-Variable -Name $($scriptVariable.Name) -Force -Scope Global -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        }
        catch { }
    }
}

## Prompt for missing parameters with meaningful messages and verify
if($RSCredential -eq $null) {
    $RSCredential = Get-Credential -Message "Enter your RightScale credentials"
    if($RSCredential -eq $null) {
        Write-Warning "You must enter your credentials!"
        EXIT 1
    }
}

if($CustomerName.Length -eq 0) {
    $CustomerName = Read-Host "Enter Customer/Report Name"
    if($CustomerName.Length -eq 0) {
        Write-Warning "You must supply a Customer/Report Name"
        EXIT 1
    }
}

if($Endpoint.Length -eq 0) {
    $Endpoint = Read-Host "Enter RS API endpoint (Example: us-3.rightscale.com)"
    if($Endpoint.Length -eq 0) {
        Write-Warning "You must supply an endpoint"
        EXIT 1
    }
}

if($OrganizationID.Length -eq 0) {
    $OrganizationID = Read-Host "Enter the Organization ID to gather details from all child accounts. Enter 0 or Leave blank to skip"
    if($OrganizationID.Length -eq 0) {
        $OrganizationID = 0
    }
}

if($Accounts.Count -eq 0) {
    $Accounts = Read-Host "Enter comma separated list of RS Account Number(s), or Parent Account number if Organization ID was specified (Example: 1234,4321,1111)"
    if($Accounts.Length -eq 0) {
        Write-Warning "You must supply at least 1 account!"
        EXIT 1
    }
}

if(($Date -eq $null) -or ($Date -eq '')) {
    $Date = Read-Host "Input date for newest allowed volume snapshots (Format: YYYY/MM/DD)"
    if($Accounts.Length -eq 0) {
        Write-Warning "You must supply at date!"
        EXIT 1
    }
}

$date_result = 0
if (!([datetime]::TryParse($Date,$null,"None",[ref]$date_result))) {
    Write-Warning "Date value not in correct format."
    EXIT 1
}

## Start Main Script
Write-Output "COS Storage Scripts Start Time: $(Get-Date)"

Write-Output "Running 'Get-UnattachedVolumes' Script..."
./Unattached_Volumes/Get-UnattachedVolumes.ps1 -RSCredential $RSCredential -ReportName $CustomerName -Endpoint $Endpoint -OrganizationID $OrganizationID -ParentAccount $Accounts -ExportToCsv $true

Write-Output "Running 'Get-OldSnapshots' Script..."
./Old_Snapshots/Get-OldSnapshots.ps1 -RSCredential $RSCredential -ReportName $CustomerName -Endpoint $Endpoint -OrganizationID $OrganizationID -ParentAccount $Accounts -Date $Date -ExportToCsv $true

if(($DebugPreference -eq "SilentlyContinue") -or ($PSBoundParameters.ContainsKey('Debug'))) {
    ## Clear out any variables that were created
    # Useful for testing in an IDE/ISE, shouldn't be neccesary for running the script normally
    Write-Verbose "Clearing variables from memory..."
    Clean-Memory
}

Write-Output "COS Storage Scripts End Time: $(Get-Date)"

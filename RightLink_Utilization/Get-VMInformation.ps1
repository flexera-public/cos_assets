# This script assumes that the rsc executable is in the working directory
# The output of this script will be a CSV created in the working directory
# If a parent account/org account number is provided, it will attempt to gather metrics from all child accounts.
# Requires enterprise_manager on the parent and observer on the child accounts
# Beginning and end time fram can be enters as just dates, which will set a time of midnight, or fully qualified dates and times.

$customer_name = Read-Host "Enter Customer Name"
$email = Read-Host "Enter RS email address" # email address associated with RS user
$password = Read-Host "Enter RS Password" # RS password
$endpoint = Read-Host "Enter RS API endpoint (us-3.rightscale.com -or- us-4.rightscale.com)" # us-3.rightscale.com -or- us-4.rightscale.com
$accounts = Read-Host "Enter comma seperated list of RS Account Number(s) or the Parent Account number. Example: 1234,4321,1111" # RS account numbers

# The Monitoring metrics data call expects a start and end time in the form of seconds from now (0)
# Example: To collect metrics for the last 5 minutes, you would specify "start = -300" and "end = 0"
# Need to convert time and date inputs into seconds from now
$currentTime = Get-Date
Write-Output "Script Start Time: $currentTime"

# Convert $accounts to array and determine child accounts
$accounts = $accounts.Split(",")
if($accounts.Count -eq 1) {
    # Assume if only 1 account it is potentially a Parent(Organization) Account
    # Try to collect Child(Projects) accounts
    $childAccountsResult = ./rsc -a $accounts --host=$endpoint --email=$email --pwd=$password cm15 index /api/child_accounts 2>$null | ConvertFrom-Json
    if($childAccountsResult) {
        $parentAccount = $accounts
        $childAccounts = $childAccountsResult.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href | Split-Path -Leaf
        $accounts = $accounts + $childAccounts
        Write-Host "Child accounts of $parentAccount have been identified: $childAccounts"
    }
    else {
        # No child accounts, nothing to do
        Write-Host "No child accounts identified."
    }
}

$instancesDetail = @()
# For each account
foreach ($account in $accounts) {
    # Get Clouds
    $clouds = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 index /api/clouds | ConvertFrom-Json
    if (!($clouds)) {
        Write-Host "$account : No clouds registered to this account."
        CONTINUE
    }
    else {
        foreach ($cloud in $clouds) {
            $cloudHref = $cloud.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href
            $cloudId = $cloudHref | Split-Path -Leaf
            $cloudName = $cloud.display_name

            # Get instances. Use extended view so we get an instance_type href.
            $instances = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 index $cloudHref/instances "view=extended" | ConvertFrom-Json
            if(!($instances)) {
                Write-Host "$account : $cloudId : No running instances : $cloudName"
                CONTINUE
            }
            else {
                Write-Host "$account : $cloudId : Getting running instances : $cloudName"
                
                foreach ($instance in $instances) {
                    $instanceHref = $instance.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty "href"
                    $instanceUid = $instance.resource_uid
                   
                    $taginfo = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 by_resource /api/tags/by_resource resource_hrefs[]=$instanceHref| ConvertFrom-Json

                    $object = New-Object -TypeName PSObject
                    $object | Add-Member -MemberType NoteProperty -Name "Account" -Value $account
                    $object | Add-Member -MemberType NoteProperty -Name "Cloud" -Value $cloudName
                    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $instance.name
                    $object | Add-Member -MemberType NoteProperty -Name "VM_ID" -Value $instanceUid
                    $object | Add-Member -MemberType NoteProperty -Name "Private_IPs" -Value ($instance.private_ip_addresses -join " ")
                    $object | Add-Member -MemberType NoteProperty -Name "Public_IPs" -Value ($instance.public_ip_addresses -join " ")
                    $object | Add-Member -MemberType NoteProperty -Name "State" -Value $instance.state
                    $object | Add-Member -MemberType NoteProperty -Name "OS_Platform" -Value $instance.os_platform
                    $object | Add-Member -MemberType NoteProperty -Name "Resource_Group" -Value $instance.cloud_specific_attributes.resource_group
                    $object | Add-Member -MemberType NoteProperty -Name "Avaibility_Set" -Value $instance.cloud_specific_attributes.availability_set
                    $object | Add-Member -MemberType NoteProperty -Name "Tags" -Value ($taginfo.tags.name -join " ")
                    $instancesDetail += $object
                }
            }
        }
    }           
}

if ($instancesDetail.count -gt 0){
    $csv_time = Get-Date -Format dd-MMM-yyyy_hhmmss
    $instancesDetail | Export-Csv -Path "./$($customer_name)_IPAddressesData_and_Tags_$($csv_time).csv" -NoTypeInformation
}

Write-Host "Script End Time: $(Get-Date)"
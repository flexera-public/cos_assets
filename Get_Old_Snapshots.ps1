# This script assumes that rsc.exe is in the working directory
# The output of this script will be:
#   1) All Volume Snapshots whose parent Volume is no longer present
#   2) All Volume Snapshots whose created_at date is older than the input date specified by the user executing this script
#
# AWS Snapshots will include Snapshots that have been SHARED with the AWS Account connected to the target RightScale account.  Use the Cloud_Specific_Attributes field to filter by AWS Account.
# ARM Snapshots likely won't appear in this report unless they meet the age requirement.  This is because: if an ARM volume is deleted after a snapshot has been taken, the volume is still reported as an available resource.

$customer_name = Read-Host "Enter Customer Name"
$email = Read-Host "Enter RS email address" # email address associated with RS user
$password = Read-Host "Enter RS Password" # RS password
$endpoint = Read-Host "Enter RS API endpoint (us-3.rightscale.com -or- us-4.rightscale.com)" # us-3.rightscale.com -or- us-4.rightscale.com
$accounts_input = Read-Host "Enter comma seperated list of RS Account Number(s) - AWS Account number. Example: 1234-012345678,4321-9723732723,1111,9999-876523832" # RS account number with AWS account number if applicable
$date = Read-Host "Input date for newest allowed volume snapshots (format: YYYY/MM/DD).  Note: snapshots created on or after this date will not be targeted unless the parent volume no longer exists."

$accounts = @()
$accounts_input = $accounts_input.Split(",")
foreach($account in $accounts_input) {
    $object = $null
    $object = New-Object psobject
    $object | Add-Member -MemberType NoteProperty -Name "RSAccount" -Value $account.Split("-")[0]
    $object | Add-Member -MemberType NoteProperty -Name "AWSAccount" -Value $account.Split("-")[1]
    $accounts += $object
}

$all_snaps_object = @()
$date_result = 0
if (!([datetime]::TryParse($date,$null,"None",[ref]$date_result))) {
    Write-Warning "Date value not in correct format. Exiting.."
} else {
    Write-Output "Start time: $(Get-Date)"
    $csv_time = Get-Date -Format dd-MMM-yyyy_hhmmss
    $my_date = Get-Date $date
    foreach ($account in $accounts) {
        
        Write-Output "$($account.RSAccount) - Getting Clouds"
        $clouds = ./rsc --email $email --pwd $password --host $endpoint --account $($account.RSAccount) --timeout=1200 cm15 index clouds | ConvertFrom-Json
        
        $cloud_hash = @{}
        foreach ($cloud in $clouds) {
            $cloud_hash.Add($(($cloud.links | Where-Object rel -eq self).href), $cloud.display_name)
        }

        Write-Output "$($account.RSAccount) - Getting Volume Details"
        $all_vol = @()
        foreach ($cloud in $clouds) { 
            Write-Output "$($account.RSAccount) - Cloud: $($cloud.display_name)"
            if ($($cloud.links | Where-Object rel -eq volumes)) {
                $vol = @()
                $vol = ./rsc --email $email --pwd $password --host $endpoint --account $($account.RSAccount) --timeout=1200 cm15 index $($cloud.links | Where-Object rel -eq volumes).href | ConvertFrom-Json
                $all_vol += $vol 
            }
        }

        $vol_hrefs = @($($all_vol.links | Where-Object rel -eq self).href)

        Write-Output "$($account.RSAccount) - Getting Snapshot Details"
        $all_snaps = @()
        [System.Collections.ArrayList]$modified_snaps = @()
        foreach ($cloud in $clouds) {  
            Write-Output "$($account.RSAccount) - Cloud: $($cloud.display_name)"
            if ($($cloud.links | Where-Object rel -eq volume_snapshots)) {
                if (($cloud.display_name -like "AWS*") -and ($account.AWSAccount -ne $null)) {
                    $snaps = @()
                    $snaps = ./rsc --email $email --pwd $password --host $endpoint --account $($account.RSAccount) --timeout=1200 cm15 index $($cloud.links | Where-Object rel -eq volume_snapshots).href "filter[]=aws_owner_id==$($account.AWSAccount)" | ConvertFrom-Json
                    $all_snaps += $snaps 
                    $modified_snaps += $snaps
                } else {
                    $snaps = @()
                    $snaps = ./rsc --email $email --pwd $password --host $endpoint --account $($account.RSAccount) --timeout=1200 cm15 index $($cloud.links | Where-Object rel -eq volume_snapshots).href | ConvertFrom-Json
                    $all_snaps += $snaps 
                    $modified_snaps += $snaps
                }
            }
        }

        Write-Output "$($account.RSAccount) - Total Snapshots Discovered: $($all_snaps.Count)"

        $target_snaps = @()
        foreach ($snap in $all_snaps) {
            if ($vol_hrefs -notcontains $($snap.links | Where-Object rel -eq parent_volume).href) { 
                $object = $null
                $object = New-Object psobject
                $object | Add-Member -MemberType NoteProperty -Name "Account" -Value $account.RSAccount
                $object | Add-Member -MemberType NoteProperty -Name "Cloud" -Value $cloud_hash.Item($($snap.links | Where-Object rel -eq cloud).href)
                $object | Add-Member -MemberType NoteProperty -Name "Name" -Value $snap.name
                $object | Add-Member -MemberType NoteProperty -Name "Resource_UID" -Value $snap.resource_uid 
                $object | Add-Member -MemberType NoteProperty -Name "Size" -Value $snap.size 
                $object | Add-Member -MemberType NoteProperty -Name "Description" -Value $snap.description 
                $object | Add-Member -MemberType NoteProperty -Name "Created_At" -Value $snap.created_at 
                $object | Add-Member -MemberType NoteProperty -Name "Updated_At" -Value $snap.updated_at 
                $object | Add-Member -MemberType NoteProperty -Name "Cloud_Specific_Attributes" -Value $snap.cloud_specific_attributes 
                $object | Add-Member -MemberType NoteProperty -Name "State" -Value $snap.state 
                $target_snaps += $object
                $modified_snaps.Remove($snap)
            }
        }
                                                  
        Write-Output "$($account.RSAccount) - Snapshots w/o an active Parent Volume: $($target_snaps.Count)"

        $snaps_by_date = 0
        foreach ($snap in $modified_snaps) {
            $snap_date = $null
            $snap_date = Get-Date $snap.created_at
            if ($snap_date -lt $my_date) {
                $object = $null
                $object = New-Object psobject
                $object | Add-Member -MemberType NoteProperty -Name "Account" -Value $account.RSAccount
                $object | Add-Member -MemberType NoteProperty -Name "Cloud" -Value $cloud_hash.Item($($snap.links | Where-Object rel -eq cloud).href)
                $object | Add-Member -MemberType NoteProperty -Name "Name" -Value $snap.name
                $object | Add-Member -MemberType NoteProperty -Name "Resource_UID" -Value $snap.resource_uid 
                $object | Add-Member -MemberType NoteProperty -Name "Size" -Value $snap.size 
                $object | Add-Member -MemberType NoteProperty -Name "Description" -Value $snap.description 
                $object | Add-Member -MemberType NoteProperty -Name "Created_At" -Value $snap.created_at 
                $object | Add-Member -MemberType NoteProperty -Name "Updated_At" -Value $snap.updated_at 
                $object | Add-Member -MemberType NoteProperty -Name "Cloud_Specific_Attributes" -Value $snap.cloud_specific_attributes 
                $object | Add-Member -MemberType NoteProperty -Name "State" -Value $snap.state 
                $target_snaps += $object
                $snaps_by_date++
            }
        }

        Write-Output "$($account.RSAccount) - Additional snapshots that do not meet the date requirements: $snaps_by_date "
        $all_snaps_object += $target_snaps
    }
}
$csv = "$($customer_name)_snapshots_$($csv_time).csv"
$all_snaps_object | Export-Csv "./$csv" -NoTypeInformation
Write-Output "CSV File: $csv"
Write-Output "End time: $(Get-Date)"

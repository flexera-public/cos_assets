# This script produces a CSV with information regarding instances in the provided RightScale accounts
# If only a parent account/org account number is provided it will attempt to gather metrics from all child accounts.
# This script requires enterprise_manager permissions on the parent and observer permissions on the child accounts

# Known Issues:
# 1. If a client provides a comma separated list of RS account numbers that have different
#    endpoints, this script will fail to run because it cannot properly setup the web sessions.

## Check Runtime environment
if ($PSVersionTable.PSVersion.Major -lt 3) {
    throw "This script requires at least PowerShell 3.0."
}

## Gather information
$rscreds = Get-Credential
$customer_name = Read-Host "Enter Customer Name"
$endpoint = Read-Host "Enter RS API endpoint (us-3.rightscale.com -or- us-4.rightscale.com)"
$accounts = Read-Host "Enter comma separated list of RS Account Number(s) or the Parent Account number. Example: 1234,4321,1111"

## Instantiate variables
$parent_provided = $false
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("X_API_VERSION","1.5")
$webSessions = @{}
$gAccounts = @{}
$instancesDetail = @()

## Create functions
# Establish sessions with RightScale
function establish_rs_session($account)
    {
        $endpoint = $gAccounts["$account"]['endpoint']

        try {
            # Establish a session with RightScale, given an account number
            Invoke-RestMethod -Uri https://$endpoint/api/session -Headers $headers -Method POST -SessionVariable tmpvar -ContentType application/x-www-form-urlencoded -Body "email=$($rscreds.UserName)&password=$($rscreds.GetNetworkCredential().Password)&account_href=/api/accounts/$account" 1>/dev/null
            $webSessions["$account"] = $tmpvar
        } catch {
            Write-Host "Unable to establish a session for account: " $account
            Write-Host "StatusCode: " $_.Exception.Response.StatusCode.value__
            exit 1
        }
    }

# Retrieve account information from RightScale
function retrieve_rs_account_info($account)
    {
        # If a session hasn't been established yet, set one up.
        if($webSessions.Keys -notcontains $account) { establish_rs_session -account $account }

        $endpoint = $gAccounts["$account"]['endpoint']

        try {
            # Gather information regarding the given RightScale account.
            $accountResults = Invoke-RestMethod -Uri https://$endpoint/api/accounts/$account -Headers $headers -Method GET -WebSession $webSessions["$account"] -Body "email=$($rscreds.UserName)&password=$($rscreds.GetNetworkCredential().Password)&account_href=/api/accounts/$account"
            # This retrieves and stores information about the account's owner and endpoint.
            $gAccounts["$account"]['owner'] = "$($accountResults.links | Where-Object { $_.rel -eq 'owner' } | Select-Object -ExpandProperty href | Split-Path -Leaf)"
            $gAccounts["$account"]['endpoint'] = "us-$($accountResults.links | Where-Object { $_.rel -eq 'cluster' } | Select-Object -ExpandProperty href | Split-Path -Leaf).rightscale.com"
        } catch {
            Write-Host "Unable to retrieve account information regarding account: " $account
            Write-Host "StatusCode: " $_.Exception.Response.StatusCode.value__
            exit 1
        }
    }

# The Monitoring metrics data call expects a start and end time in the form of seconds from now (0)
# Example: To collect metrics for the last 5 minutes, you would specify "start = -300" and "end = 0"
# Need to convert time and date inputs into seconds from now
$currentTime = Get-Date
Write-Output "Script Start Time: $currentTime"

# Convert the comma separated $accounts into a unique array of accounts
$accounts = $accounts.Split(",") | Get-Unique

## Gather all account information available and set up sessions
# Assume if only 1 account was provided, it could be a Parent(Organization) Account
# Try to collect Child(Projects) accounts
if($accounts.Count -eq 1) {
    try {
        # Assume that $accounts contains only a parent account, and attempt to extract its children
        $parentAccount = $accounts
        # Kickstart the account attributes by giving it the endpoint provided by the user
        $gAccounts["$parentAccount"] = @{'endpoint'="$endpoint"}
        # Establish a session with and gather information about the provided account
        retrieve_rs_account_info -account $parentAccount
        # Attempt to pull a list of child accounts (and their account attributes)
        $childAccountsResult = Invoke-RestMethod -Uri https://$($gAccounts["$parentAccount"]['endpoint'])/api/child_accounts -Headers $headers -Method GET -WebSession $webSessions["$parentAccount"] -Body "email=$($rscreds.UserName)&password=$($rscreds.GetNetworkCredential().Password)&account_href=/api/accounts/$parentAccount"
        # Organize and store child account attributes
        foreach($childAccount in $childAccountsResult)
        {
            $accountNum = $childAccount.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href | Split-Path -Leaf
            $gAccounts["$accountNum"] += @{
                                           'endpoint'="us-$($childAccount.links | Where-Object { $_.rel -eq 'cluster' } | Select-Object -ExpandProperty href | Split-Path -Leaf).rightscale.com";
                                           'owner'="$($childAccount.links | Where-Object { $_.rel -eq 'owner' } | Select-Object -ExpandProperty href | Split-Path -Leaf)"
                                           }
        }
        # Parse the output and turn it into an array of child accounts
        $childAccounts = $childAccountsResult.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href | Split-Path -Leaf
        # If anything had errored out prior to here, we would not get to this line, so we are confident that we were provided a parent account
        $parent_provided = $true
        # Establish sessions with and gather information about all of the child accounts individually
        foreach ($childAccount in $childAccounts) {
            retrieve_rs_account_info -account $childAccount
        }
        # Add the newly enumerated child accounts back to the list of accounts
        $accounts = $accounts + $childAccounts
        Write-Host "Child accounts of $parentAccount have been identified: $childAccounts"
    } catch {
        # Issue while attempting to pull child accounts, assume this is not a parent account
        Write-Host "No child accounts identified."
    }
}

if(!$parent_provided) {
    # We were provided multiple accounts, or the single account we got wasn't a parent
    foreach ($account in $accounts) {
        # Kickstart the account attributes by giving it the endpoint provided by the user
        $gAccounts["$account"] = @{'endpoint'="$endpoint"}

        # Attempt to establish sessions with the provided accounts and gather the relevant information
        retrieve_rs_account_info -account $account
    }
}

## Retrieve information about each known account
foreach ($account in $gAccounts.Keys) {
    # For a given account, retrieve its clouds
    try {
        $clouds = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])/api/clouds -Headers $headers -Method GET -WebSession $webSessions["$account"] -Body "email=$($rscreds.UserName)&password=$($rscreds.GetNetworkCredential().Password)&account_href=/api/accounts/$account"
    } catch {
        Write-Host "Unable to pull clouds from $account, it is possible that there are no clouds registered to this account or there is a permissioning issue."
        CONTINUE
    }

    foreach ($cloud in $clouds) {
        $cloudHref = $($cloud.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href)
        $cloudId = $cloudHref | Split-Path -Leaf
        $cloudName = $cloud.display_name

        # Get instances within the respective cloud
        try {
            # Notes:
            # - As of 2018-01-25, because $cloudHref contains a leading /, if we put a / between the endpoint and $cloudHref variables below we will get a 404
            $instances = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])$cloudHref/instances -Headers $headers -Method GET -WebSession $webSessions["$account"] -Body "email=$($rscreds.UserName)&password=$($rscreds.GetNetworkCredential().Password)&account_href=/api/accounts/$account&view=extended"
        } catch {
            Write-Host "Unable to pull instances from $cloudId"
            Write-Host "StatusCode: " $_.Exception.Response.StatusCode.value__
            exit 1
        }
        if (!$instances) {
            Write-Host "$account : $cloudId - $cloudName : No instances"
            CONTINUE
        } else {
            Write-Host "$account : $cloudId - $cloudName : Getting instances..."

            # Get instance tags for each instance
            foreach ($instance in $instances) {
                Write-Host "$account : $cloudId - $cloudName : $($instance.name)"
                $instanceHref = $instance.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty "href"
                try {
                    $taginfo = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])/api/tags/by_resource -Headers $headers -Method POST -WebSession $webSessions["$account"] -ContentType application/x-www-form-urlencoded -Body "email=$($rscreds.UserName)&password=$($rscreds.GetNetworkCredential().Password)&account_href=/api/accounts/$account&resource_hrefs[]=$instanceHref"
                } catch {
                    Write-Host "Unable to pull tag information regarding $($instance.name)"
                    Write-Host "StatusCode: " $_.Exception.Response.StatusCode.value__
                    exit 1
                }

                $object = New-Object -TypeName PSObject
                $object | Add-Member -MemberType NoteProperty -Name "Account" -Value $account
                $object | Add-Member -MemberType NoteProperty -Name "Cloud" -Value $cloudName
                $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $instance.name
                $object | Add-Member -MemberType NoteProperty -Name "VM_ID" -Value $instance.resource_uid
                $object | Add-Member -MemberType NoteProperty -Name "Private_IPs" -Value ($instance.private_ip_addresses -join " ")
                $object | Add-Member -MemberType NoteProperty -Name "Public_IPs" -Value ($instance.public_ip_addresses -join " ")
                $object | Add-Member -MemberType NoteProperty -Name "State" -Value $instance.state
                $object | Add-Member -MemberType NoteProperty -Name "OS_Platform" -Value $instance.os_platform
                $object | Add-Member -MemberType NoteProperty -Name "Resource_Group" -Value $instance.cloud_specific_attributes.resource_group
                $object | Add-Member -MemberType NoteProperty -Name "Availability_Set" -Value $instance.cloud_specific_attributes.availability_set
                $object | Add-Member -MemberType NoteProperty -Name "Tags" -Value ($taginfo.tags.name -join " ")
                $instancesDetail += $object
            }
        }
    }
}

if ($instancesDetail.count -gt 0){
    $csv_time = Get-Date -Format dd-MMM-yyyy_hhmmss
    $instancesDetail | Export-Csv -Path "./$($customer_name)_VMInformation_$($csv_time).csv" -NoTypeInformation
}

Write-Host "Script End Time: $(Get-Date)"

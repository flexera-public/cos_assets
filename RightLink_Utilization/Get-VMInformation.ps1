# This script produces a CSV with information regarding instances in the provided RightScale accounts
# If only a parent account/org account number is provided it will attempt to gather metrics from all child accounts.
# This script requires enterprise_manager permissions on the parent and observer permissions on the child accounts

# Known Issues:
# 1. If a client provides a comma separated list of RS account numbers that have different
#    endpoints, this script will fail to run because it cannot properly setup the web sessions.

[CmdletBinding()]
param(
    [System.Management.Automation.PSCredential]$RSCredential,
    [string]$CustomerName,
    [string]$Endpoint,
    [string[]]$Accounts,
    [bool]$ExportToCsv = $true
)

## Check Runtime environment
if ($PSVersionTable.PSVersion.Major -lt 3) {
    throw "This script requires at least PowerShell 3.0."
}

if ($RSCredential -eq $null) {
    $RSCredential = Get-Credential -Message "Enter your RightScale credentials"
}

if($CustomerName -eq '') {
    $CustomerName = Read-Host "Enter Customer Name"
}

if($Endpoint -eq '') {
    $Endpoint = Read-Host "Enter RS API endpoint (Example: us-3.rightscale.com)"
}

if($Accounts.count -eq 0) {
    $Accounts = Read-Host "Enter comma separated list of RS Account Number(s) or the Parent Account number (Example: 1234,4321,1111)"
}

## Instantiate variables
$parent_provided = $false
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("X_API_VERSION","1.5")
$webSessions = @{}
$gAccounts = @{}
$instancesDetail = [System.Collections.ArrayList]@()

## Create functions
# Establish sessions with RightScale
function establish_rs_session($account) {
    $endpoint = $gAccounts["$account"]['endpoint']

    try {
        # Establish a session with RightScale, given an account number
        Write-Verbose "$account : Establishing a web session via $endpoint..."
        Invoke-RestMethod -Uri "https://$endpoint/api/session" -Headers $headers -Method POST -SessionVariable tmpvar -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account" -MaximumRedirection 0 | Out-Null
        $webSessions["$account"] = $tmpvar
        RETURN $true
    }
    catch {
        if($_.Exception.Response.StatusCode.value__ -eq 302) {
            # Request is redirected if the incorrect endpoint is used
            $newEndpoint = $_.exception.response.headers.location.host
            Write-Verbose "$account : Request redirected to $newEndpoint"
            try {
                Write-Verbose "$account : Establishing a web session via $newEndpoint..."
                Invoke-RestMethod -Uri "https://$newEndpoint/api/session" -Headers $headers -Method POST -SessionVariable tmpvar -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account" -MaximumRedirection 0 | Out-Null
                $webSessions["$account"] = $tmpvar
                $gAccounts["$account"]['endpoint'] = $newEndpoint
                RETURN $true
            }
            catch {
                Write-Warning "$account : Unable to establish a session!"
                Write-Warning "$account : StatusCode: " $_.Exception.Response.StatusCode.value__
                RETURN $false
            }
        }
        else {
            Write-Warning "$account : Unable to establish a session!"
            Write-Warning "$account : StatusCode: " $_.Exception.Response.StatusCode.value__
            RETURN $false
        }
    }
}

# Retrieve account information from RightScale
function retrieve_rs_account_info($account) {
    # If a session hasn't been established yet, set one up.
    if($webSessions.Keys -notcontains $account) { 
        $sessionResult = establish_rs_session -account $account
        if ($sessionResult -eq $false) {
            RETURN $false
        }
    }

    $endpoint = $gAccounts["$account"]['endpoint']

    try {
        # Gather information regarding the given RightScale account.
        Write-Verbose "$account : Retrieving account information..."
        $accountResults = Invoke-RestMethod -Uri https://$endpoint/api/accounts/$account -Headers $headers -Method GET -WebSession $webSessions["$account"]
        # This retrieves and stores information about the account's owner and endpoint.
        $gAccounts["$account"]['owner'] = "$($accountResults.links | Where-Object { $_.rel -eq 'owner' } | Select-Object -ExpandProperty href | Split-Path -Leaf)"
        $cluster = $accountResults.links | Where-Object { $_.rel -eq 'cluster' } | Select-Object -ExpandProperty href | Split-Path -Leaf
        if($cluster -eq 10) {
            $accountEndpoint = "telstra-$cluster.rightscale.com"
        }
        else {
            $accountEndpoint = "us-$cluster.rightscale.com"
        }
        $gAccounts["$account"]['endpoint'] = $accountEndpoint
        RETURN $true
    } catch {
        Write-Warning "$account : Unable to retrieve account information!"
        Write-Warning "$account : StatusCode: " $_.Exception.Response.StatusCode.value__
        RETURN $false
    }
}

# The Monitoring metrics data call expects a start and end time in the form of seconds from now (0)
# Example: To collect metrics for the last 5 minutes, you would specify "start = -300" and "end = 0"
# Need to convert time and date inputs into seconds from now
$currentTime = Get-Date
Write-Verbose "Script Start Time: $currentTime"
$csvTime = Get-Date -Date $currentTime -Format dd-MMM-yyyy_hhmmss

# Convert the comma separated $accounts into a unique array of accounts
if($accounts -like '*,*') {
    [string[]]$accounts = $accounts.Split(",") | Get-Unique
}

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
        $accountInfoResult = retrieve_rs_account_info -account $parentAccount
        if($accountInfoResult -eq $false) { EXIT 1 }
        # Attempt to pull a list of child accounts (and their account attributes)
        $childAccountsResult = Invoke-RestMethod -Uri "https://$($gAccounts["$parentAccount"]['endpoint'])/api/child_accounts?account_href=/api/accounts/$parentAccount" -Headers $headers -Method GET -WebSession $webSessions["$parentAccount"]
        if($childAccountsResult.count -gt 0) {
            $child_accounts_present = $true
            # Organize and store child account attributes
            foreach($childAccount in $childAccountsResult)
            {
                $accountNum = $childAccount.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href | Split-Path -Leaf
                $cluster = $childAccount.links | Where-Object { $_.rel -eq 'cluster' } | Select-Object -ExpandProperty href | Split-Path -Leaf
                if($cluster -eq 10) {
                    $accountEndpoint = "telstra-$cluster.rightscale.com"
                }
                else {
                    $accountEndpoint = "us-$cluster.rightscale.com"
                }
                $gAccounts["$accountNum"] += @{
                    'endpoint'=$accountEndpoint;
                    'owner'="$($childAccount.links | Where-Object { $_.rel -eq 'owner' } | Select-Object -ExpandProperty href | Split-Path -Leaf)"
                }
            }
            # Parse the output and turn it into an array of child accounts
            $childAccounts = $childAccountsResult.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href | Split-Path -Leaf
            # If anything had errored out prior to here, we would not get to this line, so we are confident that we were provided a parent account
            $parent_provided = $true
            # Establish sessions with and gather information about all of the child accounts individually
            foreach ($childAccount in $childAccounts) {
                $childAccountInfoResult = retrieve_rs_account_info -account $childAccount
                if($childAccountsResult -eq $false) {
                    # To continue, we need to remove it from the hash and the array
                    $gAccounts.Remove($childAccount)
                    $childAccounts = $childAccounts | Where-Object {$_ -ne $childAccount}
                }
            }
            # Add the newly enumerated child accounts back to the list of accounts
            $accounts = $accounts + $childAccounts
            Write-Verbose "$parentAccount : Child accounts have been identified: $childAccounts"
        }
        else {
            # No child accounts
            $parent_provided = $false
            $child_accounts_present = $false
            Write-Verbose "$parentAccount : No child accounts identified."
        }
    } catch {
        # Issue while attempting to pull child accounts, assume this is not a parent account
        $parent_provided = $false
        $child_accounts_present = $false
        Write-Verbose "$parentAccount : No child accounts identified."
    }
}

if(!$parent_provided -and $accounts.count -gt 1) {
    # We were provided multiple accounts, or the single account we got wasn't a parent
    foreach ($account in $accounts) {
        # Kickstart the account attributes by giving it the endpoint provided by the user
        $gAccounts["$account"] = @{'endpoint'="$endpoint"}

        # Attempt to establish sessions with the provided accounts and gather the relevant information
        $accountInfoResult = retrieve_rs_account_info -account $account
        if($accountInfoResult -eq $false) {
            # To continue, we need to remove it from the hash and the array
            $gAccounts.Remove($account)
            $accounts = $accounts | Where-Object {$_ -ne $account}
        }
    }
}

if($gAccounts.Keys.count -eq 0) {
    Write-Warning "No accounts left to use!"
    EXIT 1
}

## Retrieve information about each known account
foreach ($account in $gAccounts.Keys) {
    # Account Name
    try {
        $accountName = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])/api/accounts/$account" -Headers $headers -Method GET -WebSession $webSessions["$account"] | Select-Object -ExpandProperty name
    }
    catch {
        Write-Warning "$account : ERROR - Unable to retrieve account name!"
        Write-Warning "$account : ERROR - StatusCode: " $_.Exception.Response.StatusCode.value__
        $accountName = "Unknown"
    }

    # Get Clouds
    try {
        $clouds = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])/api/clouds?account_href=/api/accounts/$account" -Headers $headers -Method GET -WebSession $webSessions["$account"]
    } 
    catch {
        Write-Warning "$account : ERROR - Unable to retrieve clouds! It is possible that there are no clouds registered to this account or there is a permissioning issue."
        Write-Warning "$account : ERROR - StatusCode: " $_.Exception.Response.StatusCode.value__
        CONTINUE
    }

    if((($clouds.display_name -like "AWS*").count -gt 0) -or
        (($clouds.display_name -like "Azure*").count -gt 0) -or
        (($clouds.display_name -like "Google*").count -gt 0)){
        # Account has AWS, Azure, or Google connected, get the Account ID
        Write-Verbose "$account : AWS, Azure, or Google Clouds Connected - Retrieving Account IDs..."
        $originalAPIVersion = $webSessions["$account"].Headers["X_API_VERSION"]
        $webSessions["$account"].Headers.Remove("X_API_VERSION") | Out-Null
        
        try {
            $cloudAccounts = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])/api/cloud_accounts" -Headers @{"X-Api-Version"="1.6";"X-Account"=$account} -Method GET -WebSession $webSessions["$account"]
        }
        catch {
            Write-Warning "$account : ERROR - Unable to retrieve cloud account IDs!"
            Write-Warning "$account : ERROR - StatusCode: " $_.Exception.Response.StatusCode.value__
        }

        $webSessions["$account"].Headers.Remove("X-Api-Version") | Out-Null
        $webSessions["$account"].Headers.Remove("X-Account") | Out-Null
        $webSessions["$account"].Headers.Add("X_API_VERSION",$originalAPIVersion)

        if($cloudAccounts){
            $cloudAccountIds = $cloudAccounts | Select-Object @{Name='href';Expression={$_.links.cloud.href}},tenant_uid
        }
    }
    else {
        $cloudAccountIds = $null
    }

    foreach ($cloud in $clouds) {
        $instances = @()
        $cloudName = $cloud.display_name
        $cloudHref = $($cloud.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href)
        
        # Get instances within the respective cloud
        try {
            $instances = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])$cloudHref/instances?view=extended -Headers $headers -Method GET -WebSession $webSessions["$account"]
        } 
        catch {
            Write-Warning "$account : $cloudName : ERROR - Unable to retrieve instances!"
            Write-Warning "$account : $cloudName : ERROR - StatusCode: " $_.Exception.Response.StatusCode.value__
            CONTINUE
        }

        if (!$instances) {
            Write-Verbose "$account : $cloudName : No instances"
            CONTINUE
        } 
        else {
            Write-Verbose "$account : $cloudName : Getting instances..."

            # Get instance tags for each instance
            foreach ($instance in $instances) {
                Write-Verbose "$account : $cloudName : $($instance.name)"
                $instanceHref = $instance.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty "href"
                try {
                    $taginfo = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])/api/tags/by_resource -Headers $headers -Method POST -WebSession $webSessions["$account"] -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account&resource_hrefs[]=$instanceHref"
                } 
                catch {
                    Write-Warning "$account : $cloudName : $($instance.name) : ERROR - Unable to pull tag information"
                    Write-Warning "$account : $cloudName : $($instance.name) : ERROR - StatusCode: " $_.Exception.Response.StatusCode.value__
                }

                $object = [pscustomobject]@{
                "Account_ID"        = $account;
                "Account_Name"      = $accountName;
                "Cloud_Account_ID"  = $($cloudAccountIds | Where-Object {$_.href -eq $cloudHref} | Select-Object -ExpandProperty tenant_uid);
                "Cloud"             = $cloudName;
                "Instance_Name"     = $instance.name;
                "Resource_UID"      = $instance.resource_uid;
                "Private_IPs"       = ($instance.private_ip_addresses -join " ");
                "Public_IPs"        = ($instance.public_ip_addresses -join " ");
                "State"             = $instance.state;
                "OS_Platform"       = $instance.os_platform;
                "Resource_Group"    = $instance.cloud_specific_attributes.resource_group;
                "Availability_Set"  = $instance.cloud_specific_attributes.availability_set;
                "Href"              = $instanceHref;
                "Tags"              = "`"$($taginfo.tags.name -join '","')`"";
                }
                $instancesDetail += $object
            }
        }
    }
}

if($instancesDetail.count -gt 0) {
    if($ExportToCsv) {
        $csv = "$($CustomerName)_VMInformation_$($csvTime).csv"
        $instancesDetail | Export-Csv "./$csv" -NoTypeInformation
        $csvFilePath = (Get-ChildItem $csv).FullName
        Write-Host "CSV File: $csvFilePath"
    }
    else {
        $instancesDetail
    }
}
else {
    Write-Host "No Instances Found"
}
Write-Verbose "End time: $(Get-Date)"
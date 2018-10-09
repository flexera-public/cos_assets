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
$child_accounts_present = $false
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("X_API_VERSION","1.5")
$webSessions = @{}
$gAccounts = @{}
$allVolumesObject = [System.Collections.ArrayList]@()

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

$currentTime = Get-Date
Write-Verbose "Script Start Time: $currentTime"
$csvTime = Get-Date -Date $currentTime -Format dd-MMM-yyyy_hhmmss

# Convert the comma separated $accounts into a unique array of accounts
if($accounts -like '*,*') {
    [string[]]$accounts = $accounts.Split(",") | Get-Unique
}

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

foreach ($account in $accounts) {
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
        $cloudName = $cloud.display_name
        $cloudHref = $cloud.links | Where-Object {$_.rel -eq 'self'} | Select-Object -ExpandProperty href

        if($cloudName -like "AzureRM*") {
            try {
                $volumeTypes = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])$($cloud.links | Where-Object { $_.rel -eq 'volume_types' } | Select-Object -ExpandProperty href)" -Headers $headers -Method GET -WebSession $webSessions["$account"]
            }
            catch {
                Write-Warning "$account : $cloudName : ERROR - Unable to retrieve volumes types!"
                Write-Warning "$account : $cloudName : ERROR - StatusCode: " $_.Exception.Response.StatusCode.value__
            }
            $volumeTypes = $volumeTypes | Select-Object name, resource_uid, @{n='href';e={$_.links | Where-Object {$_.rel -eq 'self'}| Select-Object -ExpandProperty href}}
        }

        if ($($cloud.links | Where-Object { $_.rel -eq 'volumes'})) {                                                                              
            $volumes = @()
            Write-Verbose "$account : $cloudName : Getting Volumes..."

            try {
                $volumes = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])$cloudHref/volumes?view=extended" -Headers $headers -Method GET -WebSession $webSessions["$account"]
            }
            catch {
                Write-Warning "$account : $cloudName : ERROR - Unable to retrieve volumes!"
                Write-Warning "$account : $cloudName : ERROR - StatusCode: " $_.Exception.Response.StatusCode.value__
                CONTINUE
            }

            if(!($volumes)) {
                Write-Verbose "$account : $cloudName : No Volumes Found!"
                CONTINUE
            }
            else {
                foreach ($volume in $volumes) {
                    if (($volume.status -eq "available") -and ($volume.resource_uid -notlike "*system@Microsoft.Compute/Images/*") -and ($volume.resource_uid -notlike "*@images*")) {
                        Write-Verbose "$account : $cloudName : $($volume.name) : Unattached"
                        $volumeHref = $($volume.links | Where-Object rel -eq "self").href
                        try {
                            $volumeTags = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])/api/tags/by_resource -Headers $headers -Method POST -WebSession $webSessions["$account"] -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account&resource_hrefs[]=$volumeHref"
                        }
                        catch {
                            Write-Warning "$account : $cloudName : $($volume.name) : ERROR - Unable to retrieve Volume tags!"
                            Write-Warning "$account : $cloudName : $($volume.name) : ERROR - StatusCode: " $_.Exception.Response.StatusCode.value__
                        }
                        
                        if($cloudName -like "AzureRM*") {
                            $volumeTypeHref = $volume.links | Where-Object { $_.rel -eq "volume_type" } | Select-Object -ExpandProperty href
                            $placementGroupHref = $volume.links | Where-Object { $_.rel -eq "placement_group" } | Select-Object -ExpandProperty href
                            
                            if($placementGroupHref) {
                                $placementGroupTags = @()
                                $armDiskType = "Unmanaged"
                                try {
                                    $placementGroup = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])$($placementGroupHref)?view=extended" -Headers $headers -Method GET -WebSession $webSessions["$account"]
                                }
                                catch {
                                    Write-Warning "$account : $cloudName : $($volume.name) : ERROR - Unable to retrieve Placement Group!"
                                    Write-Warning "$account : $cloudName : $($volume.name) : ERROR - StatusCode: " $_.Exception.Response.StatusCode.value__
                                }
                                
                                if ($placementGroup) {
                                    $armStorageType = $placementGroup.cloud_specific_attributes.account_type
                                    $armResourceGroup = $placementGroup.cloud_specific_attributes.'Resource Group'
                                    try {
                                        $placementGroupTags = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])/api/tags/by_resource -Headers $headers -Method POST -WebSession $webSessions["$account"] -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account&resource_hrefs[]=$placementGroupHref"
                                    }
                                    catch {
                                        Write-Warning "$account : $cloudName : $($volume.name) : ERROR - Unable to retrieve Placement Group tags!"
                                        Write-Warning "$account : $cloudName : $($volume.name) : ERROR - StatusCode: " $_.Exception.Response.StatusCode.value__
                                    }
                                }
                                else {
                                    Write-Warning "$account : $cloudName : $($volume.name) : Unable to retrieve Placement Group!"
                                    $armStorageType = "ERROR"
                                    $armResourceGroup = "Unknown"
                                }
                                $armStorageAccountName = $volume.placement_group.name
                                $volumeTags = $volumeTags + $placementGroupTags
                            }
                            elseif($volumeTypeHref) {
                                $armDiskType = "Managed"
                                $armStorageType = $volumeTypes | Where-Object { $_.href -eq $volumeTypeHref } | Select-Object -ExpandProperty name
                                $armResourceGroup = "Unknown"
                                $armStorageAccountName = "N/A"
                            }
                            else {
                                $armDiskType = "Unknown"
                                $armStorageType = "Unknown"
                                $armStorageAccountName = "Unknown"
                                $armResourceGroup = "Unknown"
                            }
                        }
                        elseif ($cloudName -like "Azure*") {
                            $armDiskType = "Unmanaged"
                            $armStorageType = "Classic"
                            $armStorageAccountName = $volume.placement_group.name
                            $armResourceGroup = "N/A"

                            if(!($armStorageAccountName)) {
                                $armStorageAccountName = "Unknown"
                            }
                        }
                        else {
                            $armDiskType = "N/A"
                            $armStorageType = "N/A"
                            $armStorageAccountName = "N/A"
                            $armResourceGroup = "N/A"
                        }

                        $object = [pscustomobject]@{
                            "Account_ID"                = $account;
                            "Account_Name"              = $accountName;
                            "Cloud_Account_ID"          = $($cloudAccountIds | Where-Object {$_.href -eq $cloudHref} | Select-Object -ExpandProperty tenant_uid);
                            "Cloud"                     = $cloudName;
                            "Volume_Name"               = $volume.name;
                            "Description"               = $volume.description;
                            "Resource_UID"              = $volume.resource_uid;
                            "Volume_Type_Href"          = $volume.volume_type_href;
                            "IOPS"                      = $volume.iops;
                            "Size"                      = $volume.size;
                            "Status"                    = $volume.status;
                            "Azure_Disk_Type"           = $armDiskType;
                            "Azure_Storage_Type"        = $armStorageType;
                            "Azure_Storage_Account"     = $armStorageAccountName;
                            "Azure_Resource_Group"      = $armResourceGroup;
                            "Created_At"                = $volume.created_at;
                            "Updated_At"                = $volume.updated_at;
                            "Cloud_Specific_Attributes" = $volume.cloud_specific_attributes;
                            "Href"                      = $volumeHref;
                            "Tags"                      = "`"$($volumeTags.tags.name -join '","')`"";
                        }
                        $allVolumesObject += $object
                    }
                    else {
                        Write-Verbose "$account : $cloudName : $($volume.name) - $($volume.resource_uid) : Attached"
                    }
                }
            }
        }
    }
}

if ($allVolumesObject.count -gt 0){
    if($ExportToCsv) {
        $csv = "$($CustomerName)_unattached-volumes_$($csvTime).csv"
        $allVolumesObject | Export-Csv "./$csv" -NoTypeInformation
        $csvFilePath = (Get-ChildItem $csv).FullName
        Write-Host "CSV File: $csvFilePath"
    }
    else {
        $allVolumesObject
    }
}
else {
    Write-Host "No Unattached Volumes Found!"
}
Write-Verbose "Script End Time: $(Get-Date)"
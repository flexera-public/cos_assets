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
$allVolumesObject = [System.Collections.ArrayList]@()
$unattachedVolumes = @()

## Create functions
# Establish sessions with RightScale
function establish_rs_session($account) {
    $endpoint = $gAccounts["$account"]['endpoint']

    try {
        # Establish a session with RightScale, given an account number
        Write-Host "$account : Establishing a web session..."
        Invoke-RestMethod -Uri "https://$endpoint/api/session" -Headers $headers -Method POST -SessionVariable tmpvar -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account" | Out-Null
        $webSessions["$account"] = $tmpvar
    } catch {
        Write-Host "$account : Unable to establish a session!"
        Write-Host "$account : StatusCode: " $_.Exception.Response.StatusCode.value__
        exit 1
    }
}

# Retrieve account information from RightScale
function retrieve_rs_account_info($account) {
    # If a session hasn't been established yet, set one up.
    if($webSessions.Keys -notcontains $account) { establish_rs_session -account $account }

    $endpoint = $gAccounts["$account"]['endpoint']

    try {
        # Gather information regarding the given RightScale account.
        Write-Host "$account : Retrieving account information..."
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
    } catch {
        Write-Host "$account : Unable to retrieve account information!"
        Write-Host "$account : StatusCode: " $_.Exception.Response.StatusCode.value__
        exit 1
    }
}

$currentTime = Get-Date
Write-Host "Script Start Time: $currentTime"
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
            retrieve_rs_account_info -account $parentAccount
            # Attempt to pull a list of child accounts (and their account attributes)
            $childAccountsResult = Invoke-RestMethod -Uri "https://$($gAccounts["$parentAccount"]['endpoint'])/api/child_accounts?account_href=/api/accounts/$parentAccount" -Headers $headers -Method GET -WebSession $webSessions["$parentAccount"]
            if($childAccountsResult.count -gt 0) {
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
                    retrieve_rs_account_info -account $childAccount
                }
                # Add the newly enumerated child accounts back to the list of accounts
                $accounts = $accounts + $childAccounts
                Write-Host "$parentAccount : Child accounts have been identified: $childAccounts"
            }
            else {
                # No child accounts
                $parent_provided = $false
                Write-Host "$parentAccount : No child accounts identified."
            }
        } catch {
            # Issue while attempting to pull child accounts, assume this is not a parent account
            Write-Host "$parentAccount : No child accounts identified."
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

foreach ($account in $accounts) {
    $targetVolumes = [System.Collections.ArrayList]@()
    $account = $account.Trim()
    
    # Account Name
    $accountName = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])/api/accounts/$account" -Headers $headers -Method GET -WebSession $webSessions["$account"] | Select-Object -ExpandProperty name
    
    # Get Clouds
    try {
        $clouds = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])/api/clouds?account_href=/api/accounts/$account" -Headers $headers -Method GET -WebSession $webSessions["$account"]
    } 
    catch {
        Write-Host "$account : Unable to pull clouds! It is possible that there are no clouds registered to this account or there is a permissioning issue."
        CONTINUE
    }

    if((($clouds.display_name -like "AWS*").count -gt 0) -or
        (($clouds.display_name -like "Azure*").count -gt 0) -or
        (($clouds.display_name -like "Google*").count -gt 0)){
        # Account has AWS, Azure, or Google connected, get the Account ID
        Write-Host "$account : AWS, Azure, or Google Clouds Connected - Retrieving Account IDs..."
        $originalAPIVersion = $webSessions["$account"].Headers["X_API_VERSION"]
        $webSessions["$account"].Headers.Remove("X_API_VERSION") | Out-Null
        $cloudAccounts = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])/api/cloud_accounts" -Headers @{"X-Api-Version"="1.6";"X-Account"=$account} -Method GET -WebSession $webSessions["$account"]
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
            $volumeTypes = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])$($cloud.links | Where-Object { $_.rel -eq 'volume_types' } | Select-Object -ExpandProperty href)" -Headers $headers -Method GET -WebSession $webSessions["$account"]
            $volumeTypes = $volumeTypes | Select-Object name, resource_uid, @{n='href';e={$_.links | Where-Object {$_.rel -eq 'self'}| Select-Object -ExpandProperty href}}
        }

        if ($($cloud.links | Where-Object { $_.rel -eq 'volumes'})) {                                                                              
            $volumes = @()
            Write-Host "$account : $cloudName : Getting Volumes..."
            $volumes = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])$cloudHref/volumes?view=extended" -Headers $headers -Method GET -WebSession $webSessions["$account"]
            
            if(!($volumes)) {
                Write-Host "$account : $cloudName : No Volumes Found!"
                CONTINUE
            }
            else {
                foreach ($volume in $volumes) {
                    if (($volume.status -eq "available") -and ($volume.resource_uid -notlike "*system@Microsoft.Compute/Images/*") -and ($volume.resource_uid -notlike "*@images*")) {
                        Write-Host "$account : $cloudName : $($volume.name) - $($volume.resource_uid) : Unattached"
                        $volumeHref = $($volume.links | Where-Object rel -eq "self").href
                        $volumeTags = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])/api/tags/by_resource -Headers $headers -Method POST -WebSession $webSessions["$account"] -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account&resource_hrefs[]=$volumeHref"
                        
                        if($cloudName -like "AzureRM*") {
                            $volumeTypeHref = $volume.links | Where-Object { $_.rel -eq "volume_type" } | Select-Object -ExpandProperty href
                            $placementGroupHref = $volume.links | Where-Object { $_.rel -eq "placement_group" } | Select-Object -ExpandProperty href
                            
                            if($placementGroupHref) {
                                $placementGroupTags = @()
                                $armDiskType = "Unmanaged"
                                $placementGroup = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])$($placementGroupHref)?view=extended" -Headers $headers -Method GET -WebSession $webSessions["$account"]
                                
                                if ($placementGroup) {
                                    $armStorageType = $placementGroup.cloud_specific_attributes.account_type
                                    $armResourceGroup = $placementGroup.cloud_specific_attributes.'Resource Group'
                                    $placementGroupTags = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])/api/tags/by_resource -Headers $headers -Method POST -WebSession $webSessions["$account"] -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account&resource_hrefs[]=$placementGroupHref"
                                }
                                else {
                                    Write-Host "$account : $cloudName : $($volume.name) - $($volume.resource_uid) : ERROR retrieving Placement Group!!"
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

                        $object = New-Object -TypeName PSObject
                        $object | Add-Member -MemberType NoteProperty -Name "RS_Account_ID" -Value $account
                        $object | Add-Member -MemberType NoteProperty -Name "Cloud_Account_ID" -Value $($cloudAccountIds | Where-Object {$_.href -eq $cloudHref} | Select-Object -ExpandProperty tenant_uid)
                        $object | Add-Member -MemberType NoteProperty -Name "Cloud" -Value $cloudName
                        $object | Add-Member -MemberType NoteProperty -Name "Volume_Name" -Value $volume.name
                        $object | Add-Member -MemberType NoteProperty -Name "Description" -Value $volume.description
                        $object | Add-Member -MemberType NoteProperty -Name "Volume_Type_Href" -Value $volume.volume_type_href
                        $object | Add-Member -MemberType NoteProperty -Name "IOPS" -Value $volume.iops
                        $object | Add-Member -MemberType NoteProperty -Name "Resource_UID" -Value $volume.resource_uid
                        $object | Add-Member -MemberType NoteProperty -Name "Size"-Value $volume.size
                        $object | Add-Member -MemberType NoteProperty -Name "Status" -Value $volume.status
                        $object | Add-Member -MemberType NoteProperty -Name "Azure_Disk_Type"-Value $armDiskType
                        $object | Add-Member -MemberType NoteProperty -Name "Azure_Storage_Type" -Value $armStorageType
                        $object | Add-Member -MemberType NoteProperty -Name "Azure_Storage_Account" -Value $armStorageAccountName
                        $object | Add-Member -MemberType NoteProperty -Name "Azure_Resource_Group" -Value $armResourceGroup
                        $object | Add-Member -MemberType NoteProperty -Name "Created_At" -Value $volume.created_at
                        $object | Add-Member -MemberType NoteProperty -Name "Updated_At" -Value $volume.updated_at
                        $object | Add-Member -MemberType NoteProperty -Name "Cloud_Specific_Attributes" -Value $volume.cloud_specific_attributes
                        $object | Add-Member -MemberType NoteProperty -Name "Href" -Value $volumeHref
                        $object | Add-Member -MemberType NoteProperty -Name "Tags" -Value "`"$($volumeTags.tags.name -join '","')`""
                        $targetVolumes += $object
                    }
                    #else {
                    #    Write-Host "$account : $cloudName : $($volume.name) - $($volume.resource_uid) : Attached"
                    #}
                }
            }
        }
    }
    $allVolumesObject += $targetVolumes
}

if ($allVolumesObject.count -gt 0){
    if($ExportToCsv) {
        $csv = "$($CustomerName)_unattached-volumes_$($csvTime).csv"
        $allVolumesObject | Export-Csv "./$csv" -NoTypeInformation
        Write-Host "CSV File: $csv"
    }
    else {
        $allVolumesObject
    }
}
else {
    Write-Host "No unattached volumes found!"
}
Write-Host "Script End Time: $(Get-Date)"
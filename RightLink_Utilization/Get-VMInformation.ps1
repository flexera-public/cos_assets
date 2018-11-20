# Source: https://github.com/rs-services/cos_assets
#
# Version: 3.1
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
    [bool]$ReportAttachedDisks,
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

# Establish sessions with RightScale
function establish_rs_session($account) {

    $endpoint = $gAccounts["$account"]['endpoint']
    
    # Establish a session with RightScale, given an account number
    try {
        Write-Verbose "$account : Establishing a web session via $endpoint..."
        $response = Invoke-WebRequest -Uri "https://$endpoint/api/session" -Headers $headers -Method POST -SessionVariable tmpvar -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account" -MaximumRedirection 0 -ErrorAction Ignore
        if($response.StatusCode -eq $null) {
            Write-Warning "$account : Unable to establish a session! StatusCode not present"
            RETURN $false
        }
        elseif($response.StatusCode -eq 204) {
            $webSessions["$account"] = $tmpvar
            RETURN $true
        }
        elseif($response.StatusCode -eq 302) {
            # Request is redirected if the incorrect endpoint is used
            $newEndpoint = $response.Headers.Location.Replace('https://','').Split('/')[0]
            Write-Verbose "$account : Request redirected to $newEndpoint"
            Write-Verbose "$account : Establishing a web session via $newEndpoint..."
            $response2 = Invoke-WebRequest -Uri "https://$newEndpoint/api/session" -Headers $headers -Method POST -SessionVariable tmpvar -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account" -MaximumRedirection 0 # -ErrorAction Ignore
            if($response2.StatusCode -eq 204) {
                $webSessions["$account"] = $tmpvar
                $gAccounts["$account"]['endpoint'] = $newEndpoint
                RETURN $true
            }
            else {
                Write-Warning "$account : Unable to establish a session! StatusCode: $($response2.StatusCode)"
                RETURN $false
            }
        }
        else {
            Write-Warning "$account : Unable to establish a session! StatusCode: $($response.StatusCode)"
            RETURN $false
        }
    }
    catch {
        if($_.Exception.Response.StatusCode.value__ -eq 302) {
            # Request is redirected if the incorrect endpoint is used
            $newEndpoint = $_.exception.response.headers.location.host
            Write-Verbose "$account : Request redirected to $newEndpoint"
            try {
                Write-Verbose "$account : Establishing a web session via $newEndpoint..."
                Invoke-WebRequest -Uri "https://$newEndpoint/api/session" -Headers $headers -Method POST -SessionVariable tmpvar -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account" -MaximumRedirection 0 -ErrorAction Ignore
                $webSessions["$account"] = $tmpvar
                $gAccounts["$account"]['endpoint'] = $newEndpoint
                RETURN $true
            }
            catch {
                Write-Warning "$account : Unable to establish a session! StatusCode: $($_.Exception.Response.StatusCode.value__)"
                RETURN $false
            }
        }
        else {
            Write-Warning "$account : Unable to establish a session! StatusCode: $($_.Exception.Response.StatusCode.value__)"
            RETURN $false
        }
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

if($ReportAttachedDisks -eq $null) {
    $ReportAttachedDisks = Read-Host "Report on attached disks? Yes/No"
    if($ReportAttachedDisks -eq 'yes' -or 'y') {
        $ReportAttachedDisks = $true
    }
    elseif($ReportAttachedDisks -eq 'no' -or 'n') {
        $ReportAttachedDisks = $false
    }
    else {
        $ReportAttachedDisks -eq $false
    }
}

if($Accounts.Count -eq 0) {
    $Accounts = Read-Host "Enter comma separated list of RS Account Number(s), or Parent Account number if Organization ID was specified (Example: 1234,4321,1111)"
    if($Accounts.Length -eq 0) {
        Write-Warning "You must supply at least 1 account!"
        EXIT 1
    }
}

## Instantiate common variables
$parent_provided = $false
$child_accounts_present = $false
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("X_API_VERSION","1.5")
$webSessions = @{}
$gAccounts = @{}
$currentTime = Get-Date
$csvTime = Get-Date -Date $currentTime -Format dd-MMM-yyyy_hhmmss

## Instantiate script specific variables
$instancesDetail = [System.Collections.ArrayList]@()

## Start Main Script
Write-Verbose "Script Start Time: $currentTime"

# Convert the comma separated $accounts into a unique array of accounts
if($accounts -like '*,*') {
    [string[]]$accounts = $accounts.Split(",")
}

# Ensure there are no duplicates
[string[]]$accounts = $accounts.Trim() | Sort-Object | Get-Unique

## Gather all account information available and set up sessions
# Assume if only 1 account was provided, it could be a Parent(Organization) Account
# Try to collect Child(Projects) accounts
if(($accounts.Count -eq 1) -and ($OrganizationID.length -gt 0) -and ($OrganizationID -ne 0)) {
    try {
        # Assume that $accounts contains only a parent account, and attempt to extract its children
        $parentAccount = $accounts
        # Kickstart the account attributes by giving it the endpoint provided by the user
        $gAccounts["$parentAccount"] = @{'endpoint'="$endpoint"}
        # Establish a session with and gather information about the provided account
        $accountInfoResult = establish_rs_session -account $parentAccount
        if($accountInfoResult -eq $false) { EXIT 1 }
        # Attempt to pull a list of child accounts (and their account attributes)
        $response = Invoke-RestMethod -Uri "https://$($gAccounts["$parentAccount"]['endpoint'])/api/sessions?view=whoami" -Headers $headers -Method GET -WebSession $webSessions["$parentAccount"] -ContentType application/x-www-form-urlencoded
        $userId = ($response.links | Where-Object {$_.rel -eq "user"} | Select-Object -ExpandProperty href).Split('/')[-1]
        $originalAPIVersion = $webSessions["$parentAccount"].Headers["X_API_VERSION"]
        $webSessions["$parentAccount"].Headers.Remove("X_API_VERSION") | Out-Null
        $userAccessResult = Invoke-RestMethod -Uri "https://governance.rightscale.com/grs/users/$userId/projects" -Headers @{"X-API-Version"="2.0"} -Method GET -WebSession $webSessions["$parentAccount"]
        $webSessions["$parentAccount"].Headers.Remove("X-API-Version") | Out-Null
        $webSessions["$parentAccount"].Headers.Add("X_API_VERSION",$originalAPIVersion)
        $childAccountsResult = $userAccessResult | Where-Object {$_.links.org.id -eq $OrganizationID} | Where-Object {$_.id -notmatch $parentAccount}
        if($childAccountsResult.count -gt 0) {
            $childAccounts = [System.Collections.ArrayList]@()
            $child_accounts_present = $true
            # Organize and store child account attributes
            foreach($childAccountResult in $childAccountsResult) {
                $accountNum = $childAccountResult.id
                $accountEndpoint = $childAccountResult.legacy.account_url.replace('https://','').split('/')[0]
                $gAccounts["$accountNum"] += @{
                    'endpoint'=$accountEndpoint
                }
                # Establish sessions with and gather information about all of the child accounts individually
                $childAccountInfoResult = establish_rs_session -account $accountNum
                if($childAccountInfoResult -eq $false) {
                    # To continue, we need to remove it from the hash
                    $gAccounts.Remove("$accountNum")
                }
                else {
                    #Otherwise add it to the childAccounts array
                    $childAccounts += $accountNum
                }
            }
            # If anything had errored out prior to here, we would not get to this line, so we are confident that we were provided a parent account
            $parent_provided = $true
            # Add the newly enumerated child accounts back to the list of accounts
            $accounts = $gAccounts.Keys
            if($childAccounts.Count -gt 0) {
                Write-Verbose "$parentAccount : Child accounts have been identified: $childAccounts"
            }
            else {
                Write-Warning "$parentAccount : Child accounts have been identified, but they could not be authenticated to"
            }
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

if(!$parent_provided -and $accounts.count -gt 0) {
    # We were provided multiple accounts, or the single account we got wasn't a parent
    foreach ($account in $accounts) {
        if(!($webSessions["$account"])) {
            # Kickstart the account attributes by giving it the endpoint provided by the user
            $gAccounts["$account"] = @{'endpoint'="$endpoint"}

            # Attempt to establish sessions with the provided accounts and gather the relevant information
            $accountInfoResult = establish_rs_session -account $account
            if($accountInfoResult -eq $false) {
                # To continue, we need to remove it from the hash and the array
                $gAccounts.Remove("$account")
                $accounts = $accounts | Where-Object {$_ -ne $account}
            }
        }
    }
}

if($gAccounts.Keys.count -eq 0) {
    Write-Warning "No accounts left to use!"
    EXIT 1
}

## Retrieve information about each known account
foreach ($account in $gAccounts.Keys) {
    Write-Verbose "$account : Starting..."

    # Account Name
    try {
        Write-Verbose "$account : Retrieving account name..."
        $accountName = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])/api/accounts/$account" -Headers $headers -Method GET -WebSession $webSessions["$account"] | Select-Object -ExpandProperty name
    }
    catch {
        Write-Warning "$account : Unable to retrieve account name! StatusCode: $($_.Exception.Response.StatusCode.value__)"
        $accountName = "Unknown"
    }

    # Get Clouds
    try {
        Write-Verbose "$account : Retrieving clouds..."
        $clouds = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])/api/clouds?account_href=/api/accounts/$account" -Headers $headers -Method GET -WebSession $webSessions["$account"]
    } 
    catch {
        Write-Warning "$account : Unable to retrieve clouds! StatusCode: $($_.Exception.Response.StatusCode.value__)"
        CONTINUE
    }

    if((($clouds.display_name -like "AWS*").count -gt 0) -or
        (($clouds.display_name -like "Azure*").count -gt 0) -or
        (($clouds.display_name -like "Google*").count -gt 0)){
        # Account has AWS, Azure, or Google connected, get the Account ID
        $originalAPIVersion = $webSessions["$account"].Headers["X_API_VERSION"]
        $webSessions["$account"].Headers.Remove("X_API_VERSION") | Out-Null
        
        try {
            Write-Verbose "$account : AWS, Azure, or Google Clouds Connected - Retrieving Account IDs..."
            $cloudAccounts = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])/api/cloud_accounts" -Headers @{"X-Api-Version"="1.6";"X-Account"=$account} -Method GET -WebSession $webSessions["$account"]
        }
        catch {
            Write-Warning "$account : Unable to retrieve cloud account IDs! StatusCode: $($_.Exception.Response.StatusCode.value__)"
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
        $instances = [System.Collections.ArrayList]@()
        $cloudName = $cloud.display_name
        $cloudHref = $($cloud.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href)
        
        # Get instances within the respective cloud. Use extended view so we get an instance_type href.
        try {
            Write-Verbose "$account : $cloudName : Retrieving instances..."
            $instances = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])$cloudHref/instances?view=extended -Headers $headers -Method GET -WebSession $webSessions["$account"]
        } 
        catch {
            Write-Warning "$account : $cloudName : Unable to retrieve instances! StatusCode: $($_.Exception.Response.StatusCode.value__)"
            CONTINUE
        }

        if (!$instances) {
            Write-Verbose "$account : $cloudName : No instances"
            CONTINUE
        } 
        else {
            # Get Instance Types including Deleted
            try {
                Write-Verbose "$account : $cloudName : Retrieving instance type information..."
                $instanceTypes = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])$cloudHref/instance_types?with_deleted=true -Headers $headers -Method GET -WebSession $webSessions["$account"]
                $instanceTypes = $instanceTypes | Select-Object name, resource_uid, description, memory, cpu_architecture, cpu_count, cpu_speed, @{Name="href";Expression={$_.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href}}
                Write-Verbose "$account : $cloudName : Number of Instance Types = $($instanceTypes.count)"
            } 
            catch {
                Write-Warning "$account : $cloudName : Unable to retrieve instance types! StatusCode: $($_.Exception.Response.StatusCode.value__)"
                CONTINUE
            }

            # Get instance tags for each instance
            foreach ($instance in $instances) {
                Write-Verbose "$account : $cloudName : $($instance.name)"
                
                # Check for ARM Managed Disks
                if(($cloudName -like "AzureRM*") -and ($instance.cloud_specific_attributes.root_volume_type_uid)) {
                    $armManagedDisks = $true
                    Write-Verbose "$account : $cloudName : $($instance.name) : ARM Managed Disks = $armManagedDisks"
                }
                elseif($cloudName -like "AzureRM*") {
                    $armManagedDisks = $false
                    Write-Verbose "$account : $cloudName : $($instance.name) : ARM Managed Disks = $armManagedDisks"
                }
                else {
                    $armManagedDisks = "N/A"
                }
                
                $instanceHref = $instance.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty "href"
                try {
                    Write-Verbose "$account : $cloudName : $($instance.name) : Retrieving tags..."
                    $taginfo = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])/api/tags/by_resource -Headers $headers -Method POST -WebSession $webSessions["$account"] -ContentType application/x-www-form-urlencoded -Body "email=$($RSCredential.UserName)&password=$($RSCredential.GetNetworkCredential().Password)&account_href=/api/accounts/$account&resource_hrefs[]=$instanceHref"
                    Write-Verbose "$account : $cloudName : $($instance.name) : Number of Tags = $($taginfo.tags.name.count)"
                } 
                catch {
                    Write-Warning "$account : $cloudName : $($instance.name) : Unable to retrieve tag information. StatusCode: $($_.Exception.Response.StatusCode.value__)"
                }

                if($ReportAttachedDisks) {
                    # Get the number of attached disks
                    $numberOfAttachedDisks = 0
                    try {
                        Write-Verbose "$account : $cloudName : $($instance.name) : Retrieving volume attachment information..."
                        $instanceVolumeAttachments = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])$instanceHref/volume_attachments -Headers $headers -Method GET -WebSession $webSessions["$account"]
                        Write-Warning "$account : $cloudName : $($instance.name) : Total Volumes Attached = $($instanceVolumeAttachments.count)"
                    } 
                    catch {
                        if($_.Exception.Response.StatusCode.value__ -eq 422) {
                            Write-Verbose "$account : $cloudName : $($instance.name) : No volumes attached"
                        }
                        else {
                            Write-Warning "$account : $cloudName : $($instance.name) : Unable to retrieve volume attachment information. StatusCode: $($_.Exception.Response.StatusCode.value__)"
                        }
                        $instanceVolumeAttachments = $null
                    }
                    
                    if($instanceVolumeAttachments) {
                        #Some clouds show the osDisk as being attached -  we should not count this
                        if($cloudName -like "AzureRM*") {
                            $numberOfAttachedDisks = @($instanceVolumeAttachments | Where-Object {$_.device_id -ne 'osDisk'}).Count
                        } elseif($cloudName -like "Google*") {
                            $numberOfAttachedDisks = @($instanceVolumeAttachments | Where-Object {$_.device_id -ne 'persistent-disk-0'}).Count
                        } elseif(($cloudName -like "AWS*") -or ($cloudName -like "EC2*")) {
                            $numberOfAttachedDisks = @($instanceVolumeAttachments | Where-Object {$_.device_id -ne '/dev/sda1'}).Count
                        } else {
                            $numberOfAttachedDisks = @($instanceVolumeAttachments).Count
                        }
                        Write-Verbose "$account : $cloudName : $($instance.name) : Number of Attached Disks = $numberOfAttachedDisks"
                    }
                    else {
                        $numberOfAttachedDisks = 0
                    }
                    
                }
                else {
                    $numberOfAttachedDisks = "N/A"
                }

                $object = [pscustomobject]@{
                    "Account_ID"                = $account;
                    "Account_Name"              = $accountName;
                    "Cloud_Account_ID"          = $($cloudAccountIds | Where-Object {$_.href -eq $cloudHref} | Select-Object -ExpandProperty tenant_uid);
                    "Cloud"                     = $cloudName;
                    "Instance_Name"             = $instance.name;
                    "Resource_UID"              = $instance.resource_uid;
                    "Private_IPs"               = ($instance.private_ip_addresses -join " ");
                    "Public_IPs"                = ($instance.public_ip_addresses -join " ");
                    "ARM_Managed_Disks"         = $armManagedDisks;
                    "Number_of_Attached_Disks"  = $numberOfAttachedDisks;
                    "State"                     = $instance.state;
                    "OS_Platform"               = $instance.os_platform;
                    "Resource_Group"            = $instance.cloud_specific_attributes.resource_group;
                    "Availability_Set"          = $instance.cloud_specific_attributes.availability_set;
                    "Href"                      = $instanceHref;
                    "Tags"                      = "`"$($taginfo.tags.name -join '","')`"";
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

if(($DebugPreference -eq "SilentlyContinue") -or ($PSBoundParameters.ContainsKey('Debug'))) {
    ## Clear out any variables that were created
    # Useful for testing in an IDE/ISE, shouldn't be necessary for running the script normally
    Write-Verbose "Clearing variables from memory..."
    Clean-Memory
}

$scriptEndTime = Get-Date 
$scriptElapsed = New-TimeSpan -Start $currentTime -End $scriptEndTime
$scriptElapsedMinutes = "{00:N2}" -f $scriptElapsed.TotalMinutes
Write-Verbose "Script End Time: $scriptEndTime"
Write-Verbose "Script Elapsed Time: $scriptElapsedMinutes minute(s)"

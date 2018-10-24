# Source: https://github.com/rs-services/cos_assets

[CmdletBinding()]
param(
    [System.Management.Automation.PSCredential]$RSCredential,
    [alias("ReportName")]
    [string]$CustomerName,
    [string]$Endpoint,
    [string]$OrganizationID,
    [alias("ParentAccount")]
    [string[]]$Accounts,
    [datetime]$InitialStartTime,
    [datetime]$InitialEndTime,
    [bool]$ExportToCsv = $true
)

## Check Runtime environment
if($PSVersionTable.PSVersion.Major -lt 3) {
    throw "This script requires at least PowerShell 3.0."
}

if($RSCredential -eq $null) {
    $RSCredential = Get-Credential -Message "Enter your RightScale credentials"
}

if($CustomerName.Length -eq 0) {
    $CustomerName = Read-Host "Enter Customer/Report Name"
}

if($Endpoint.Length -eq 0) {
    $Endpoint = Read-Host "Enter RS API endpoint (Example: us-3.rightscale.com)"
}

if($OrganizationID.Length -eq 0) {
    $OrganizationID = Read-Host "Enter the Organization ID to gather details from all child accounts. Enter 0 or Leave blank to skip"
}

if($Accounts.Count -eq 0) {
    $Accounts = Read-Host "Enter comma separated list of RS Account Number(s), or Parent Account number if Organization ID was specified (Example: 1234,4321,1111)"
}

if($InitialStartTime -eq $null) {
    $InitialStartTime = Read-Host "Enter beginning of time frame to collect from (Format: YYYY/MM/DD)"
}

if($InitialEndTime -eq $null) {
    $InitialEndTime = Read-Host "Enter end of time frame to collect from (Format: YYYY/MM/DD)"
}

## Instantiate variables
$parent_provided = $false
$child_accounts_present = $false
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
        Write-Warning "$account : Unable to retrieve account information! StatusCode: $($_.Exception.Response.StatusCode.value__)"
        RETURN $false
    }
}

$currentTime = Get-Date
Write-Verbose "Script Start Time: $currentTime"
$csvTime = Get-Date -Date $currentTime -Format dd-MMM-yyyy_hhmmss

# The Monitoring metrics data call expects a start and end time in the form of seconds from now (0)
# Example: To collect metrics for the last 5 minutes, you would specify "start = -300" and "end = 0"
# Need to convert time and date inputs into seconds from now
$startTime = "-" + (($currentTime) - (Get-Date $InitialStartTime) | Select-Object -ExpandProperty TotalSeconds).ToString().Split('.')[0]
if(($InitialEndTime -eq $null) -or ($InitialEndTime -eq "") -or ($InitialEndTime -eq 0) -or !($InitialEndTime)) {
    $InitialEndTime = Get-Date
    $endTime = 0
} else {
    $endTime = "-" + (($currentTime) - (Get-Date $InitialEndTime) | Select-Object -ExpandProperty TotalSeconds).ToString().Split('.')[0]
}

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
        $accountInfoResult = retrieve_rs_account_info -account $parentAccount
        if($accountInfoResult -eq $false) { EXIT 1 }
        # Attempt to pull a list of child accounts (and their account attributes)
        $originalAPIVersion = $webSessions["$parentAccount"].Headers["X_API_VERSION"]
        $webSessions["$parentAccount"].Headers.Remove("X_API_VERSION") | Out-Null
        $childAccountsResult = Invoke-RestMethod -Uri "https://governance.rightscale.com/grs/orgs/$OrganizationID/projects" -Headers @{"X-API-Version"="2.0"} -Method GET -WebSession $webSessions["$parentAccount"]
        $webSessions["$parentAccount"].Headers.Remove("X-API-Version") | Out-Null
        $webSessions["$parentAccount"].Headers.Add("X_API_VERSION",$originalAPIVersion)
        if($childAccountsResult.count -gt 0) {
            $childAccounts = [System.Collections.ArrayList]@()
            $child_accounts_present = $true
            # Organize and store child account attributes
            foreach($childAccountResult in $childAccountsResult) {
                if($childAccountResult.id -notmatch $parentAccount) {
                    $accountNum = $childAccountResult.id
                    $accountEndpoint = $childAccountResult.legacy.account_url.replace('https://','').split('/')[0]
                    $gAccounts["$accountNum"] += @{
                        'endpoint'=$accountEndpoint;
                        'owner'='N/A'
                    }
                    # Establish sessions with and gather information about all of the child accounts individually
                    $childAccountInfoResult = retrieve_rs_account_info -account $accountNum
                    if($childAccountInfoResult -eq $false) {
                        # To continue, we need to remove it from the hash
                        $gAccounts.Remove("$accountNum")
                    }
                    else {
                        #Otherwise add it to the childAccounts array
                        $childAccounts += $accountNum
                    }
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
        # Kickstart the account attributes by giving it the endpoint provided by the user
        $gAccounts["$account"] = @{'endpoint'="$endpoint"}

        # Attempt to establish sessions with the provided accounts and gather the relevant information
        $accountInfoResult = retrieve_rs_account_info -account $account
        if($accountInfoResult -eq $false) {
            # To continue, we need to remove it from the hash and the array
            $gAccounts.Remove("$account")
            $accounts = $accounts | Where-Object {$_ -ne $account}
        }
    }
}

if($gAccounts.Keys.count -eq 0) {
    Write-Warning "No accounts left to use!"
    EXIT 1
}

foreach ($account in $gAccounts.Keys) {
    # Account Name
    try {
        $accountName = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])/api/accounts/$account" -Headers $headers -Method GET -WebSession $webSessions["$account"] | Select-Object -ExpandProperty name
    }
    catch {
        Write-Warning "$account : Unable to retrieve account name! StatusCode: $($_.Exception.Response.StatusCode.value__)"
        $accountName = "Unknown"
    }

    # Get Clouds
    try {
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
        Write-Verbose "$account : AWS, Azure, or Google Clouds Connected - Retrieving Account IDs..."
        $originalAPIVersion = $webSessions["$account"].Headers["X_API_VERSION"]
        $webSessions["$account"].Headers.Remove("X_API_VERSION") | Out-Null
        
        try {
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
            Write-Verbose "$account : $cloudName : Getting instances..."

            # Get Instance Types including Deleted
            try {
                #$instanceTypes = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 index $cloudHref/instance_types | ConvertFrom-Json
                $instanceTypes = Invoke-RestMethod -Uri https://$($gAccounts["$account"]['endpoint'])$cloudHref/instance_types?with_deleted=true -Headers $headers -Method GET -WebSession $webSessions["$account"]
                $instanceTypes = $instanceTypes | Select-Object name, resource_uid, description, memory, cpu_architecture, cpu_count, cpu_speed, @{Name="href";Expression={$_.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href}}
            } 
            catch {
                Write-Warning "$account : $cloudName : Unable to retrieve instance types! StatusCode: $($_.Exception.Response.StatusCode.value__)"
                CONTINUE
            }
            
            foreach ($instance in $instances) {
                Write-Verbose "$account : $cloudName : $($instance.name)"
                $instanceHref = $instance.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty "href"
                $instanceUid = $instance.resource_uid

                # Get total memory from instance_type
                $instanceTypeHref = $instance.links | Where-Object { $_.rel -eq "instance_type" } | Select-Object -ExpandProperty "href"
                $instanceMemory = $instanceTypes | Where-Object { $_.href -eq $instanceTypeHref } | Select-Object -ExpandProperty "memory"
                $instanceTypeName = $instanceTypes | Where-Object { $_.href -eq $instanceTypeHref } | Select-Object -ExpandProperty "name"

                if(!($instanceTypeName)) {
                    Write-Warning "$account : $cloudName : $($instance.name) : Instance Type 'unknown'"
                    $instanceTypeName = "Unknown"
                }

                if($instanceMemory) {
                    if($instanceMemory -match '^\d*$') {
                        # Assume MB if no multiplier
                        $memBaseSize = $instanceMemory
                        $memMultiplier = "MB"
                    }
                    else {
                        # Contains multiplier
                        $memBaseSize = $instanceMemory.Split(' ')[0]
                        $memMultiplier = $instanceMemory.Split(' ')[1]
                    }
                }
                else {
                    $instanceMemory = "Unknown"
                    $memMultiplier = ""
                }   

                Write-Verbose "$account : $cloudName : $($instance.name) : Instance Type = $instanceTypeName : Instance Memory = $instanceMemory $memMultiplier"

                $cpuMax = $null; $cpuAvg = $null; $cpuData = $null; $cpuDataPoints = $null; $cpuDataPointsTotal = $null;
                
                # Get cpu-0:cpu-idle Monitoring Metrics
                try {
                    #$cpuData = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 data $instanceHref/monitoring_metrics/cpu-0:cpu-idle/data "start=$startTime" "end=$endTime" --pp 2>$null | ConvertFrom-Json
                    $cpuData = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])$instanceHref/monitoring_metrics/cpu-0:cpu-idle/data?start=$startTime&end=$endTime" -Headers $headers -Method GET -WebSession $webSessions["$account"]
                } 
                catch {
                    Write-Warning "$account : $cloudName : $($instance.name) : Unable to retrieve cpu monitoring data! StatusCode: $($_.Exception.Response.StatusCode.value__)"
                }
                if ($cpuData) {
                    Write-Verbose "$account : $cloudName : $($instance.name) : Collected CPU metrics"
                    $cpuDataPoints = $cpuData.variables_data.points | Where-Object { $_ } # Trim $null returns
                    $cpuDataPointsTotal = $cpuDataPoints.count
                    
                    ## Calculate CPU max
                    $cpuMaxIdle = $cpuDataPoints | Sort-Object -Descending | Select-Object -Last 1
                    if ($cpuMaxIdle -ne $null) {
                        $cpuMax = "{00:N2}" -f (100 - $cpuMaxIdle) # Convert idle to used and format the number
                    }

                    ## Calculate CPU avg
                    $cpuAvgIdle = $cpuDataPoints | Measure-Object -Average | Select-Object -ExpandProperty Average
                    if ($cpuAvgIdle -ne $null) {
                        $cpuAvg = "{00:N2}" -f (100 - $cpuAvgIdle) # Convert idle to used and format the number
                    }
                }

                $memMax = $null; $memAvg = $null; $memData = $null; $memDataPoints = $null; $memDataPointsTotal = $null;
                if($instanceMemory -ne "Unknown") {
                    # Get memory:memory-used Monitoring Metrics - Memory is not monitored as a percentage but instead as total used
                    try {
                        #$memData = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 data $instanceHref/monitoring_metrics/memory:memory-used/data "start=$startTime" "end=$endTime" --pp 2>$null | ConvertFrom-Json
                        $memData = Invoke-RestMethod -Uri "https://$($gAccounts["$account"]['endpoint'])$instanceHref/monitoring_metrics/memory:memory-used/data?start=$startTime&end=$endTime" -Headers $headers -Method GET -WebSession $webSessions["$account"]
                    } 
                    catch {
                        Write-Warning "$account : $cloudName : $($instance.name) : Unable to retrieve memory monitoring data! StatusCode: $($_.Exception.Response.StatusCode.value__)"
                    }
                    if ($memData) {
                        Write-Verbose "$account : $cloudName : $($instance.name) : Collected Memory metrics"
                        $memDataPoints = $memData.variables_data.points | Where-Object { $_ } # Trim $null returns
                        $memDataPointsTotal = $memDataPoints.count
                        
                        ## Calculate max used memory
                        $memMax = $memDataPoints | Sort-Object -Descending | Select-Object -First 1
                        if ($memMax -ne $null) {
                            $memMax = "{00:N2}" -f ((($memMax / "1$memMultiplier") / $memBaseSize) * 100) # Convert to percentage and format the number
                        }

                        ## Calculate average used memory
                        $memAvg = $memDataPoints | Measure-Object -Average | Select-Object -ExpandProperty Average
                        if ($memAvg -ne $null) {
                            $memAvg = "{00:N2}" -f ((($memAvg / "1$memMultiplier") / $memBaseSize) * 100) # Convert to percentage and format the number
                        }
                    }
                }
                else {
                    Write-Verbose "$account : $cloudName : $($instance.name) : Unable to calculate memory utilization"
                }

                $cpuTimeFrame = $null; $memTimeFrame = $null; $metricTimespan = 0;
                if (($cpuDataPointsTotal -ne $null) -or ($memDataPointsTotal -ne $null)) {
                    # Calculate total time span of metrics returned
                    # TSS default collection period is 20 seconds
                    # Which would mean 4320 data points in a 24 hour period
                    if ($cpuDataPointsTotal -ne $null) {
                        $cpuTimeFrame = $cpuDataPointsTotal / 4320
                    }
                    if ($memDataPointsTotal -ne $null) {
                        $memTimeFrame = $memDataPointsTotal / 4320
                    }

                    if ($cpuTimeFrame -ge $memTimeFrame) {
                        $metricTimespan = "{00:N2}" -f $cpuTimeFrame
                    }
                    elseif ($memTimeFrame -ge $cpuTimeFrame) {
                        $metricTimespan = "{00:N2}" -f $memTimeFrame
                    }
                }

                $object = [pscustomobject]@{
                    "Account_ID"            = $account;
                    "Account_Name"          = $accountName;
                    "Cloud_Account_ID"      = $($cloudAccountIds | Where-Object {$_.href -eq $cloudHref} | Select-Object -ExpandProperty tenant_uid);
                    "Cloud"                 = $cloudName;
                    "Instance_Name"         = $instance.name;
                    "Resource_UID"          = $instance.resource_uid;
                    "Instance_Type"         = $instanceTypeName;
                    "CPU_Max(%)"            = $cpuMax;
                    "CPU_Avg(%)"            = $cpuAvg;
                    "Memory_Max(%)"         = $memMax;
                    "Memory_Avg(%)"         = $memAvg;
                    "Metric_Timespan(Days)" = $metricTimespan;

                }
                $instancesDetail += $object
            }
        }
    }         
}

if($instancesDetail.count -gt 0) {
    if($ExportToCsv) {
        $csv = "$($CustomerName)_OrgUtilizationData_$($csvTime).csv"
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
Write-Verbose "Script End time: $(Get-Date)"
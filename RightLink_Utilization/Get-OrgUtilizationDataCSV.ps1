# This script assumes that the rsc executable is in the working directory
# The output of this script will be a CSV created in the working directory
# If a parent account/org account number is provided, it will attempt to gather metrics from all child accounts.
# Requires enterprise_manager on the parent and observer on the child accounts
# Beginning and end time frame can be entered as just dates, which will set a time of midnight, or fully qualified dates and times.

$customer_name = Read-Host "Enter Customer Name" # Used for name of CSV
$email = Read-Host "Enter RS email address" # email address associated with RS user
$password = Read-Host "Enter RS Password" # RS password
$initialStartTime = Read-host "Enter beginning of time frame to collect from in MM/DD/YYYY HH:MM:SS"
$initialEndTime = Read-Host "Enter end of time frame to collect from in MM/DD/YYYY HH:MM:SS or press enter for now"
$csvFile = Read-Host "Enter the path to the csv to import"

if(Test-Path -Path $csvFile) {
    $importedInstances = Import-Csv -Path $csvFile
}
else {
    Write-Host "File $csvFile does not exist!"
    EXIT 1
}

# The Monitoring metrics data call expects a start and end time in the form of seconds from now (0)
# Example: To collect metrics for the last 5 minutes, you would specify "start = -300" and "end = 0"
# Need to convert time and date inputs into seconds from now
$currentTime = Get-Date
Write-Output "Script Start Time: $currentTime"
$startTime = "-" + (($currentTime) - (Get-Date $initialStartTime) | Select-Object -ExpandProperty TotalSeconds).ToString().Split('.')[0]
if(($initialEndTime -eq $null) -or ($initialEndTime -eq "") -or ($initialEndTime -eq 0) -or !($initialEndTime)) {
    $initialEndTime = Get-Date
    $endTime = 0
}
else {
    $endTime = "-" + (($currentTime) - (Get-Date $initialEndTime) | Select-Object -ExpandProperty TotalSeconds).ToString().Split('.')[0]
}

Write-Host "Collection Start (seconds): $startTime"
Write-Host "Collection End (seconds): $endTime"

$accounts = $importedInstances | Select-Object Account_ID, Account_Endpoint -Unique
$optimaAccount = $($accounts.Account_ID | Select-Object -First 1)
$optimaEndpoint = $($accounts.Account_Endpoint | Select-Object -First 1)

# Use Optima to retrieve Cloud Account Name and Cloud Account ID
try {
    $contentType = "application/json"
    $header = @{"X_API_VERSION"="1.5"}
    $uri = "https://$optimaEndpoint/api/session"
    $body = @{
        "email"=$email
        "password"=$password
        "account_href"="/api/accounts/$optimaAccount"
    } | ConvertTo-Json

    $authResult = Invoke-WebRequest -Uri $uri -Method Post -Headers $header -ContentType $contentType -Body $body -SessionVariable authSession -ErrorAction SilentlyContinue
    $webSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $webSession.cookies = $authSession.cookies

    try {
        #Optima Accounts
        Write-Host "Gathering account detail from Optima..."
        $currentDate = Get-Date
        $optimaStartTime = "$($currentDate.Year)-$($currentDate.Month)-01T00:00:00+0000"
        $optimaEndTime = "$($currentDate.Year)-$(($currentDate.AddMonths(1)).Month)-01T00:00:00+0000"
    
        $optimaHeaders = @{
            "X-API-Version"="1.0"
        }

        $accountPayload = @()
        foreach ($account in $accounts) {
            $object = New-Object -TypeName PSObject
            $object | Add-Member -MemberType NoteProperty -Name kind -Value "ca#filter"
            $object | Add-Member -MemberType NoteProperty -Name type -Value "combined_cost:account_id"
            $object | Add-Member -MemberType NoteProperty -Name value -Value $account.Account_ID
            $object | Add-Member -MemberType NoteProperty -Name negate -Value "false"
            $accountPayload += $object
        }

        $optimaBodyPayload = @{
            "start_time"=$optimaStartTime
            "end_time"=$optimaEndTime
            "group"=@(
                    @("cloud_vendor_account_id","cloud_vendor_account_name","account_id","account_name","cloud_vendor_name"),@("account_id")
            )
            "combined_cost_filters"=@(
                $accountPayload
            )
        } | ConvertTo-Json

        $optimaAccountsResult = Invoke-WebRequest -Uri "https://analytics.rightscale.com/api/combined_costs/actions/grouped_time_series" -WebSession $webSession -Method Post -Headers $optimaHeaders -ContentType $contentType -Body $optimaBodyPayload -ErrorAction SilentlyContinue
        
        if($optimaAccountsResult) {
            Write-Host "Successfully retrieved Account details from Optima!"
            $optimaAccounts = ($optimaAccountsResult | ConvertFrom-Json).results.group
        }
        else {
            Write-Host "No access to Optima(Combined Costs). Continuing..."
            $optimaAccounts = $null
        }
    }
    catch {
        Write-Host "No access to Optima. Continuing..."
        $optimaAccounts = $null
    }

    try {
        # Optima Instances
        Write-Host "Gathering instances detail from Optima..."
        $optimaStartTime = Get-Date -Date $initialStartTime -Format yyyy-MM-ddThh:mm:ss
        $optimaEndTime = Get-Date -Date $initialEndTime -Format yyyy-MM-ddThh:mm:ss
        
        $optimaHeaders = @{
            "X-API-Version"="1.0"
        }

        $accountPayload = @()
        foreach ($account in $accounts) {
            $object = New-Object -TypeName PSObject
            $object | Add-Member -MemberType NoteProperty -Name kind -Value "ca#filter"
            $object | Add-Member -MemberType NoteProperty -Name type -Value "instance:account_id"
            $object | Add-Member -MemberType NoteProperty -Name value -Value $account.Account_ID
            $object | Add-Member -MemberType NoteProperty -Name negate -Value "false"
            $accountPayload += $object
        }

        $optimaBodyPayload = @{
            "start_time"=$optimaStartTime
            "end_time"=$optimaEndTime
            "instance_filters"=@(
                $accountPayload
            )
        } | ConvertTo-Json

        $optimaInstancesResult = Invoke-WebRequest -Uri "https://analytics.rightscale.com/api/instances" -WebSession $webSession -Method Post -Headers $optimaHeaders -ContentType $contentType -Body $optimaBodyPayload -ErrorAction SilentlyContinue
        
        if($optimaInstancesResult) {
            Write-Host "Successfully retrieved Instances detail from Optima!"
            $optimaInstances = ($optimaInstancesResult | ConvertFrom-Json)
        }
        else {
            Write-Host "No access to Optima(Instances). Continuing..."
            $optimaInstances = $null
        }
    }
    catch {
        Write-Host "No access to Optima(Instances). Continuing..."
        $optimaInstances = $null
    }
}
catch {
    Write-Host "No access to Optima. Continuing..."
    $optimaAccounts = $null
    $optimaInstances = $null
}

# Step through each account and collect monitoring metrics
$instancesDetail = @()
foreach ($acct in $accounts) {
    $account = $acct.Account_ID
    $endpoint = $acct.Account_Endpoint
    Write-Host "$account : Getting Account Name..."
    $accountName = (./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 show /api/accounts/$account | ConvertFrom-Json) | Select-Object -ExpandProperty name

    $allAccountInstances = $importedInstances | Where-Object { $_.State -eq "Operational" -and $_.Account_ID -eq $account } | Sort-Object -Property Cloud_Href
    $clouds = $allAccountInstances | Select-Object Cloud_name, Cloud_Href -Unique
        foreach ($cloud in $clouds) {
            $cloudHref = $cloud.Cloud_Href
            $cloudName = $cloud.Cloud_Name

            $instances = $allAccountInstances | Where-Object { $_.Cloud_Href -eq $cloudHref }
            if(!($instances)) {
                Write-Host "$account : $cloudName : No 'Operational' instances"
                CONTINUE
            }
            else {
                # Get instance types
                Write-Host "$account : $cloudName : Getting Instance Types from CM..."
                $instanceTypes = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 index $cloudHref/instance_types | ConvertFrom-Json
                $instanceTypes = $instanceTypes | Select-Object name, resource_uid, description, memory, cpu_architecture, cpu_count, cpu_speed, @{Name="href";Expression={$_.links | Where-Object { $_.rel -eq "self" } | Select-Object -ExpandProperty href}}
            
                foreach ($instanceRef in $instances) {
                    # Get instances. Use extended view so we get an instance_type href.
                    #$instance = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 show $instanceRef.Instance_Href "view=extended"| ConvertFrom-Json
                    $instanceHref = $instanceRef.Instance_Href
                    $instanceUid = $instanceRef.Resource_UID
                    $instanceName = $instanceRef.Instance_Name

                    # Get total memory from instance_type
                    # This should fail and use Optima if the instance call above is remarked
                    $instanceTypeHref = $instance.links | Where-Object { $_.rel -eq "instance_type" } | Select-Object -ExpandProperty "href"
                    $instanceMemory = $instanceTypes | Where-Object { $_.href -eq $instanceTypeHref } | Select-Object -ExpandProperty "memory"
                    $instanceTypeName = $instanceTypes | Where-Object { $_.href -eq $instanceTypeHref } | Select-Object -ExpandProperty "name"

                    if(!($instanceTypeName)) {
                        if($optimaInstances) {
                            #Instance type is unknown in CM, try Optima
                            Write-Host "$account : $cloudName : $instanceName - $instanceUid : Instance Type 'unknown' in CM! Trying Optima..."
                            $instanceTypeName = $optimaInstances | Where-Object { $_.instance_uid -eq $instanceUid } | Select-Object -ExpandProperty "instance_type_name"
                            if($instanceTypeName) {
                                $instanceMemory = $instanceTypes | Where-Object { $_.name -eq $instanceTypeName } | Select-Object -ExpandProperty "memory"
                            }
                            else {
                                Write-Host "$account : $cloudName : $instanceName - $instanceUid : Unable to resolve Instance Type with Optima Data"
                                $instanceTypeName = "Unknown"
                            }
                        }
                        else {
                            Write-Host "$account : $cloudName : $instanceName - $instanceUid : Unable to resolve Instance Type"
                            $instanceTypeName = "Unknown"
                        }
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

                    Write-Host "$account : $cloudName : $instanceName - $instanceUid : Instance Type = $instanceTypeName : Instance Memory = $instanceMemory $memMultiplier"

                    $cpuMax = $null; $cpuAvg = $null; $cpuData = $null; $cpuDataPoints = $null; $cpuDataPointsTotal = $null; $loadMetric = $null;
                    # Test for cpu load metric - Don't trust results, ignoring for now.
                    #$loadMetric = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 index $instanceHref/monitoring_metrics "filter[]=plugin==cpu_avg" "filter[]=view==percent-loadavg" --pp 2>$null | ConvertFrom-Json
                    
                    if($loadMetric) {
                        # Get cpu_avg:percent-loadavg Monitoring Metrics
                        $cpuData = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 data $instanceHref/monitoring_metrics/cpu_avg:percent-loadavg/data "start=$startTime" "end=$endTime" --pp 2>$null | ConvertFrom-Json
                        if ($cpuData) {
                            Write-Host "$account : $cloudName : $instanceName - $instanceUid : Collected CPU metrics"
                            $cpuDataPoints = $cpuData.variables_data.points | Where-Object { $_ } # Trim $null returns
                            $cpuDataPointsTotal = $cpuDataPoints.count
                            
                            ## Calculate CPU max
                            #$cpuMaxLoad = $cpuDataPoints | Where-Object { $_ -ne 0 } | Sort-Object -Descending | Select-Object -First 1
                            $cpuMaxLoad = $cpuDataPoints | Sort-Object -Descending | Select-Object -First 1
                            if ($cpuMaxLoad -ne $null) {
                                $cpuMax = "{00:N3}" -f ($cpuMaxLoad / 1000) # Convert from millipercent and format the number
                            }

                            ## Calculate CPU avg
                            $cpuAvgLoad = $cpuDataPoints | Measure-Object -Average | Select-Object -ExpandProperty Average
                            if ($cpuAvgLoad -ne $null) {
                                $cpuAvg = "{00:N3}" -f ($cpuAvgLoad / 1000) # Convert from millipercent and format the number
                            }
                        }
                        else {
                            Write-Host "$account : $cloudName : $instanceName - $instanceUid : Unable to retrieve cpu monitoring data"
                        }
                    }
                    else {
                        # Get cpu-0:cpu-idle Monitoring Metrics
                        $cpuData = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 data $instanceHref/monitoring_metrics/cpu-0:cpu-idle/data "start=$startTime" "end=$endTime" --pp 2>$null | ConvertFrom-Json
                        if ($cpuData) {
                            Write-Host "$account : $cloudName : $instanceName - $instanceUid : Collected CPU metrics"
                            $cpuDataPoints = $cpuData.variables_data.points | Where-Object { $_ } # Trim $null returns
                            $cpuDataPointsTotal = $cpuDataPoints.count
                            
                            ## Calculate CPU max
                            #$cpuMaxIdle = $cpuDataPoints | Where-Object { $_ -ne 0 } | Sort-Object -Descending | Select-Object -Last 1
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
                        else {
                            Write-Host "$account : $cloudName : $instanceName - $instanceUid : Unable to retrieve cpu monitoring data"
                        }
                    }

                    $memMax = $null; $memAvg = $null; $memData = $null; $memDataPoints = $null; $memDataPointsTotal = $null;
                    if($instanceMemory -ne "Unknown") {
                        # Get memory:memory-used Monitoring Metrics - Memory is not monitored as a percentage but instead as total used
                        $memData = ./rsc -a $account --host=$endpoint --email=$email --pwd=$password cm15 data $instanceHref/monitoring_metrics/memory:memory-used/data "start=$startTime" "end=$endTime" --pp 2>$null | ConvertFrom-Json
                        if ($memData) {
                            Write-Host "$account : $cloudName : $instanceName - $instanceUid : Collected Memory metrics"
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
                        else {
                            Write-Host "$account : $cloudName : $instanceName - $instanceUid : Unable to retrieve memory monitoring data"
                        }
                    }
                    else {
                        Write-Host "$account : $cloudName : $instanceName - $instanceUid : Unable to calculate memory utilization"
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
                    
                    if($optimaAccounts -ne $null) {
                        # Gather cloud vendor data from Optima Result
                        $cloudAccountId = ""
                        $cloudAccountName = ""
                        switch -wildcard ($cloudName) {
                            "Azure*" {$cloud_vendor_name = "Microsoft Azure"}
                            "Google*" {$cloud_vendor_name = "Google"}
                            "AWS*" {$cloud_vendor_name = "Amazon Web Services"}
                            default {$cloud_vendor_name = "Unknown"}
                        }
                        $optimaData = $optimaAccounts | Where-Object { $_.account_id -eq $account } | Where-Object { $_.cloud_vendor_name -eq $cloud_vendor_name } 
                        $cloudAccountId = $optimaData | Where-Object { $_.cloud_vendor_account_id -ne "" } | Where-Object { $_.cloud_vendor_account_name -ne "" } | Select-Object -First 1 -ExpandProperty cloud_vendor_account_id
                        $cloudAccountName = $optimaData | Where-Object { $_.cloud_vendor_account_id -ne "" } | Where-Object { $_.cloud_vendor_account_name -ne "" } | Select-Object -First 1 -ExpandProperty cloud_vendor_account_name
                    }
                    else {
                        $cloudAccountId = ""
                        $cloudAccountName = ""
                    }

                    # Build the object to export to CSV
                    $object = New-Object -TypeName PSObject
                    $object | Add-Member -MemberType NoteProperty -Name "RS_Account_ID" -Value $account
                    $object | Add-Member -MemberType NoteProperty -Name "RS_Account_Name" -Value $accountName
                    $object | Add-Member -MemberType NoteProperty -Name "Vendor_Account_ID" -Value $cloudAccountId
                    $object | Add-Member -MemberType NoteProperty -Name "Vendor_Account_Name" -Value $cloudAccountName
                    $object | Add-Member -MemberType NoteProperty -Name "Cloud" -Value $cloudName
                    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $instanceName
                    $object | Add-Member -MemberType NoteProperty -Name "Resource_UID" -Value $instanceUid
                    $object | Add-Member -MemberType NoteProperty -Name "Instance_Type" -Value $instanceTypeName
                    $object | Add-Member -MemberType NoteProperty -Name "CPU_Max(%)" -Value $cpuMax
                    $object | Add-Member -MemberType NoteProperty -Name "CPU_Avg(%)" -Value $cpuAvg
                    $object | Add-Member -MemberType NoteProperty -Name "Memory_Max(%)"-Value $memMax
                    $object | Add-Member -MemberType NoteProperty -Name "Memory_Avg(%)" -Value $memAvg
                    $object | Add-Member -MemberType NoteProperty -Name "Metric_Timespan(Days)" -Value $metricTimespan
                    $instancesDetail += $object
                }
            }
        }         
}

if ($instancesDetail.count -gt 0){
    $csv_time = Get-Date -Format dd-MMM-yyyy_hhmmss
    $instancesDetail | Export-Csv -Path "./$($customer_name)_UtilizationData($($startTime)_$($endTime))_$($csv_time).csv" -NoTypeInformation
}

Write-Host "Script End Time: $(Get-Date)"

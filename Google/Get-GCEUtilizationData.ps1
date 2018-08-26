$ErrorActionPreference = 'stop'
Write-Output @"

#########################################################
# Steps to allow programmatic access to the Google APIs #
#########################################################

In order to successfully collect StackDriver monitoring data, you need to enable the StackDriver Monitoring API as well as create and authorize OAuth Client credentials.
These steps only need to be performed once.

1. Go to https://console.cloud.google.com/apis/dashboard and make sure the project you want to collect monitoring data from is selected.
2. Go to "Enable APIs and Services" from the Dashboard of your project and enable the "StackDriver Monitoring API"
3. Press the back button and select the "Credentials" item in the left hand navigation
4. Create a Credential with the type of "OAuth Client ID"
    Select "Other" for Application Type
    Save the Client ID and Client Secret in a safe place
5. Replace <Client_ID> with the value obtained in step 4 in the following URL and browse to it in your web browser:
    https://accounts.google.com/o/oauth2/auth?client_id=<CLIENT_ID>&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/monitoring.read&response_type=code
5. Login to your Google account and retrieve the authorization code via the above URL.
    Note: The authorization code is a one time use code.
6. Run the following code, replacing <CLIENT_ID>, <CLIENT_SECRET>, and <AUTHORIZATION_CODE> with the relevant values, to retrieve your refresh token:
        `$tokenParams = @{
           client_id=<CLIENT_ID>;
           client_secret=<CLIENT_SECRET>;
           code=<AUTHORIZATION_CODE>;
           grant_type='authorization_code';
           redirect_uri="urn:ietf:wg:oauth:2.0:oob"
        }
        `$token = Invoke-WebRequest -Uri "https://accounts.google.com/o/oauth2/token" -Method POST -Body `$tokenParams | ConvertFrom-Json
        Write-Output "Refresh Token: `$(`$token.refresh_token)"
7. Save your refresh token in a safe place
8. You are now ready to programmatically retrieve monitoring data!

#########################################################

"@

function Encode-String ($string) {
    $encodedString = $string
    $encodedString = $encodedString.replace(" ", "%20")
    $encodedString = $encodedString.replace("!", "%21")
    $encodedString = $encodedString.replace('"', "%22")
    $encodedString = $encodedString.replace("#", "%23")
    $encodedString = $encodedString.replace("$", "%24")
    $encodedString = $encodedString.replace("&", "%26")
    $encodedString = $encodedString.replace("'", "%27")
    $encodedString = $encodedString.replace("(", "%28")
    $encodedString = $encodedString.replace(")", "%29")
    $encodedString = $encodedString.replace("*", "%2A")
    $encodedString = $encodedString.replace("+", "%2B")
    $encodedString = $encodedString.replace(",", "%2C")
    $encodedString = $encodedString.replace("/", "%2F")
    $encodedString = $encodedString.replace(":", "%3A")
    $encodedString = $encodedString.replace(";", "%3B")
    $encodedString = $encodedString.replace("=", "%3D")
    $encodedString = $encodedString.replace("?", "%3F")
    $encodedString = $encodedString.replace("@", "%40")
    $encodedString = $encodedString.replace("[", "%5B")
    $encodedString = $encodedString.replace("]", "%5D")
    $encodedString
}

function Get-GoogleAccessToken ($clientID, $clientSecret, $refreshToken) {
    $refreshTokenParams = @{
        client_id=$clientID;
        client_secret=$clientSecret;
        refresh_token=$refreshToken;
        grant_type='refresh_token';
      }
  
    $refreshedToken = Invoke-WebRequest -Uri "https://accounts.google.com/o/oauth2/token" -Method POST -Body $refreshTokenParams | ConvertFrom-Json
    $refreshedToken.access_token
}

$customerName = Read-Host 'Customer Name'
$googleProject = Read-Host 'Enter Google Project'
$clientID = Read-Host 'Google Client ID'
$clientPass = Read-Host 'Google Client Secret' -AsSecureString
$clientRefresh = Read-Host 'Google Refresh Token' -AsSecureString
$startTime = Read-Host 'Enter start date (Ex: MM/DD/YYYY)'
$endTime = Read-Host 'Enter end date (Ex: MM/DD/YYYY)'

$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientPass)
$clientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientRefresh)
$refreshToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

Write-Output "`n** Script Start Time: $(Get-Date)`n"
$csvTime = Get-Date -Format dd-MMM-yyyy_hhmmss

$accessToken = Get-GoogleAccessToken -clientID $clientID -clientSecret $clientSecret -refreshToken $refreshToken

$formattedStartTime = (Get-Date $startTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
$encodedStartTime = 'interval.startTime=' + $(Encode-String -string $formattedStartTime)
$formattedEndTime = (Get-Date $endTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
$encodedEndTime = 'interval.endTime=' + $(Encode-String -string $formattedEndTime)
$alignmentPeriod = 'aggregation.alignmentPeriod=' + $(New-TimeSpan -Start $(Get-Date $startTime) -End $(Get-Date $endTime)).TotalSeconds + 's'

$hostCPUPath = 'compute.googleapis.com/instance/cpu/utilization'
$agentCPUPath = 'agent.googleapis.com/cpu/utilization'
$agentMemoryPath = 'agent.googleapis.com/memory/percent_used'
$hostCPUMetric = 'filter=' + $(Encode-String -string "metric.type=`"$hostCPUPath`" AND resource.type=`"gce_instance`"")
$agentCPUMetric = 'filter=' + $(Encode-String -string "metric.type=`"$agentCPUPath`" AND resource.type=`"gce_instance`"")
$agentMemoryMetric = 'filter=' + $(Encode-String -string "metric.type=`"$agentMemoryPath`" AND resource.type=`"gce_instance`"")

$contentType = "application/json"
$header = @{"Authorization"="Bearer $accessToken"}
$baseuri = "https://monitoring.googleapis.com/v3/projects/$googleProject/timeSeries/?"

$meanHostCPUURI = $baseuri + $hostCPUMetric + '&' + $encodedStartTime + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MEAN'
$maxHostCPUURI = $baseuri + $hostCPUMetric + '&' + $encodedStartTime + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MAX'
$meanAgentCPUURI = $baseuri + $agentCPUMetric + '&' + $encodedStartTime + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MEAN'
$maxAgentCPUURI = $baseuri + $agentCPUMetric + '&' + $encodedStartTime + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MIN'
$meanAgentMemoryURI = $baseuri + $agentMemoryMetric + '&' + $encodedStartTime + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MEAN'
$maxAgentMemoryURI = $baseuri + $agentMemoryMetric + '&' + $encodedStartTime + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MAX'

# Gather Metrics
Write-Output "Gathering metric data for MEAN Host CPU..."
$meanHostCPUResult = Invoke-RestMethod -Method Get -Uri $meanHostCPUURI -Headers $header -ContentType $contentType

Write-Output "Gathering metric data for MAX Host CPU..."
$maxHostCPUResult = Invoke-RestMethod -Method Get -Uri $maxHostCPUURI -Headers $header -ContentType $contentType

Write-Output "Gathering metric data for MEAN Agent CPU..."
$meanAgentCPUResult = Invoke-RestMethod -Method Get -Uri $meanAgentCPUURI -Headers $header -ContentType $contentType

Write-Output "Gathering metric data for MAX Agent CPU..."
$maxAgentCPUResult = Invoke-RestMethod -Method Get -Uri $maxAgentCPUURI -Headers $header -ContentType $contentType

Write-Output "Gathering metric data for MEAN Agent Memory..."
$meanAgentMemoryResult = Invoke-RestMethod -Method Get -Uri $meanAgentMemoryURI -Headers $header -ContentType $contentType

Write-Output "Gathering metric data for MAX Agent Memory..."
$maxAgentMemoryResult = Invoke-RestMethod -Method Get -Uri $maxAgentMemoryURI -Headers $header -ContentType $contentType

Write-Output "Processing results..."

# Process Results
## MEAN Host CPU
$meanHostCPUObject = @()
foreach($item in $meanHostCPUResult.timeSeries) {
    $object = New-Object -TypeName PSObject
    $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty project_id)
    $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
    $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $($item.metric | Where-Object {$_.type -eq $hostCPUPath} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_name)
    $object | Add-Member -MemberType NoteProperty -Name "Mean_Host_CPU" -Value $("{00:N3}" -f ($item.points.value.doubleValue * 100))
    $meanHostCPUObject += $object
}

## MAX Host CPU
$maxHostCPUObject = @()
foreach($item in $maxHostCPUResult.timeSeries) {
    $object = New-Object -TypeName PSObject
    $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty project_id)
    $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
    $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $($item.metric | Where-Object {$_.type -eq $hostCPUPath} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_name)
    $object | Add-Member -MemberType NoteProperty -Name "Max_Host_CPU" -Value $("{00:N3}" -f ($item.points.value.doubleValue * 100))
    $maxHostCPUObject += $object
}

## MEAN Agent CPU
$meanAgentCPUObject = @()
foreach($item in $meanAgentCPUResult.timeSeries) {
    if($item.metric.labels.cpu_state -eq 'idle') {
        $object = New-Object -TypeName PSObject
        $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty project_id)
        $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
        $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
        $object | Add-Member -MemberType NoteProperty -Name "Mean_Agent_CPU" -Value $("{00:N3}" -f (100 - $item.points.value.doubleValue))
        $meanAgentCPUObject += $object
    }
}

## MAX Agent CPU
$maxAgentCPUObject = @()
foreach($item in $maxAgentCPUResult.timeSeries) {
    if($item.metric.labels.cpu_state -eq 'idle') {
        $object = New-Object -TypeName PSObject
        $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty project_id)
        $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
        $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
        $object | Add-Member -MemberType NoteProperty -Name "Max_Agent_CPU" -Value $("{00:N3}" -f (100 - $item.points.value.doubleValue))
        $maxAgentCPUObject += $object
    }
}

## MEAN Agent MEMORY
$meanAgentMemoryObject = @()
foreach($item in $meanAgentMemoryResult.timeSeries) {
    if($item.metric.labels.state -eq 'used') {
        $object = New-Object -TypeName PSObject
        $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty project_id)
        $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
        $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
        $object | Add-Member -MemberType NoteProperty -Name "Mean_Agent_Memory" -Value $("{00:N3}" -f ($item.points.value.doubleValue))
        $meanAgentMemoryObject += $object
    }
}

## MAX Agent MEMORY
$maxAgentMemoryObject = @()
foreach($item in $maxAgentMemoryResult.timeSeries) {
    if($item.metric.labels.state -eq 'used') {
        $object = New-Object -TypeName PSObject
        $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty project_id)
        $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
        $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
        $object | Add-Member -MemberType NoteProperty -Name "Max_Agent_Memory" -Value $("{00:N3}" -f ($item.points.value.doubleValue))
        $maxAgentMemoryObject += $object
    }
}

## Concatenate Objects
$allMetricsObject = @()
foreach($item in $meanHostCPUObject) {
    $object = New-Object -TypeName PSObject
    $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $item.Google_Project
    $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $item.Instance_ID
    $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $item.Zone
    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $item.Instance_Name
    $object | Add-Member -MemberType NoteProperty -Name "Mean_Host_CPU(%)" -Value $item.Mean_Host_CPU
    $object | Add-Member -MemberType NoteProperty -Name "Max_Host_CPU(%)" -Value $($maxHostCPUObject | Where-Object {$_.instance_id -eq $item.Instance_ID} | Select-Object -ExpandProperty Max_Host_CPU)
    $object | Add-Member -MemberType NoteProperty -Name "Mean_Agent_CPU(%)" -Value $($meanAgentCPUObject | Where-Object {$_.instance_id -eq $item.Instance_ID} | Select-Object -ExpandProperty Mean_Agent_CPU)
    $object | Add-Member -MemberType NoteProperty -Name "Max_Agent_CPU(%)" -Value $($maxAgentCPUObject | Where-Object {$_.instance_id -eq $item.Instance_ID} | Select-Object -ExpandProperty Max_Agent_CPU)
    $object | Add-Member -MemberType NoteProperty -Name "Mean_Agent_Memory(%)" -Value $($meanAgentMemoryObject | Where-Object {$_.instance_id -eq $item.Instance_ID} | Select-Object -ExpandProperty Mean_Agent_Memory)
    $object | Add-Member -MemberType NoteProperty -Name "Max_Agent_Memory(%)" -Value $($maxAgentMemoryObject | Where-Object {$_.instance_id -eq $item.Instance_ID} | Select-Object -ExpandProperty Max_Agent_Memory)
    $allMetricsObject += $object
}

if ($allMetricsObject.count -gt 0) {
    $metricsCsvFile = "./$($customerName)_gce_metrics_$($csvTime).csv"
    $allMetricsObject | Export-Csv $metricsCsvFile -NoTypeInformation
    $metricsCsvFilePath = Get-item $metricsCsvFile | Select-Object -ExpandProperty FullName  
    Write-Output "`n** Metrics CSV File: $metricsCsvFilePath"
}
else {
    Write-Output "`n** No StackDriver metric records to export to CSV..."
}

Write-Output "`n** Script End Time: $(Get-Date)`n"
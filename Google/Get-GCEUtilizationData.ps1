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

$pass = Read-Host 'Enter Google bearer token' -AsSecureString
$startTime = Read-Host 'Enter start date (Ex: MM/DD/YYYY)'
$endTime = Read-Host 'Enter end date (Ex: MM/DD/YYYY)'
$googleProject = Read-Host 'Enter Google Project'

$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

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
$header = @{"Authorization"="Bearer $password"}
$baseuri = "https://monitoring.googleapis.com/v3/projects/$googleProject/timeSeries/?"

$meanHostCPUURI = $baseuri + $hostCPUMetric + '&' + $encodedStartTime + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MEAN'
$maxHostCPUURI = $baseuri + $hostCPUMetric + '&' + $encodedStartTime + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MAX'
$meanAgentCPUURI = $baseuri + $agentCPUMetric + '&' + $agentCPUMetric + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MEAN'
$maxAgentCPUURI = $baseuri + $agentCPUMetric + '&' + $agentCPUMetric + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MAX'
$meanAgentMemoryURI = $baseuri + $agentMemoryMetric + '&' + $agentCPUMetric + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MEAN'
$maxAgentMemoryURI = $baseuri + $agentMemoryMetric + '&' + $agentCPUMetric + '&' + $encodedEndTime + '&' + $alignmentPeriod + '&' + 'aggregation.perSeriesAligner=ALIGN_MAX'

# Gather Metrics
## MEAN Host CPU
$meanHostCPUResult = Invoke-RestMethod -Method Get -Uri $meanHostCPUURI -Headers $header -ContentType $contentType

## MAX Host CPU
$maxHostCPUResult = Invoke-RestMethod -Method Get -Uri $meanHostCPUURI -Headers $header -ContentType $contentType

## MEAN Agent CPU
$meanAgentCPUResult = Invoke-RestMethod -Method Get -Uri $meanAgentCPUURI -Headers $header -ContentType $contentType

## MAX Agent CPU
$maxAgentCPUResult = Invoke-RestMethod -Method Get -Uri $maxAgentCPUURI -Headers $header -ContentType $contentType

## MEAN Agent MEMORY
$meanAgentMemoryResult = Invoke-RestMethod -Method Get -Uri $meanAgentMemoryURI -Headers $header -ContentType $contentType

## MAX Agent MEMORY
$maxAgentMemoryResult = Invoke-RestMethod -Method Get -Uri $maxAgentMemoryURI -Headers $header -ContentType $contentType


# Process Results
## MEAN Host CPU
$meanHostCPUObject = @()
foreach($item in $meanHostCPUResult.timeSeries) {
    $object = New-Object -TypeName PSObject
    $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $googleProject
    $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
    $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $($item.metric | Where-Object {$_.type -eq $hostCPUPath} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_name)
    $object | Add-Member -MemberType NoteProperty -Name "Mean_Host_CPU(%)" -Value $("{00:N3}" -f ($item.points.value.doubleValue * 100))
    $meanHostCPUObject += $object
}

## MAX Host CPU
$maxHostCPUObject = @()
foreach($item in $maxHostCPUResult.timeSeries) {
    $object = New-Object -TypeName PSObject
    $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $googleProject
    $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
    $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $($item.metric | Where-Object {$_.type -eq $hostCPUPath} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_name)
    $object | Add-Member -MemberType NoteProperty -Name "Max_Host_CPU(%)" -Value $("{00:N3}" -f ($item.points.value.doubleValue * 100))
    $maxHostCPUObject += $object
}

## MEAN Agent CPU
$meanAgentCPUObject = @()
foreach($item in $meanAgentCPUResult.timeSeries) {
    $object = New-Object -TypeName PSObject
    $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $googleProject
    $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
    $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $($item.metric | Where-Object {$_.type -eq $agentCPUPath} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_name)
    $object | Add-Member -MemberType NoteProperty -Name "Mean_Agent_CPU(%)" -Value $("{00:N3}" -f ($item.points.value.doubleValue * 100))
    $meanAgentCPUObject += $object
}

## MAX Agent CPU
$maxAgentCPUObject = @()
foreach($item in $maxAgentCPUResult.timeSeries) {
    $object = New-Object -TypeName PSObject
    $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $googleProject
    $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
    $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $($item.metric | Where-Object {$_.type -eq $agentCPUPath} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_name)
    $object | Add-Member -MemberType NoteProperty -Name "Max_Agent_CPU(%)" -Value $("{00:N3}" -f ($item.points.value.doubleValue * 100))
    $maxAgentCPUObject += $object
}

## MEAN Agent MEMORY
$meanAgentMemoryObject = @()
foreach($item in $meanAgentMemoryResult.timeSeries) {
    $object = New-Object -TypeName PSObject
    $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $googleProject
    $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
    $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $($item.metric | Where-Object {$_.type -eq $agentMemoryPath} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_name)
    $object | Add-Member -MemberType NoteProperty -Name "Mean_Agent_Memory(%)" -Value $("{00:N3}" -f ($item.points.value.doubleValue * 100))
    $meanAgentMemoryObject += $object
}

## MAX Agent MEMORY
$maxAgentMemoryCPUObject = @()
foreach($item in $maxAgentMemoryResult.timeSeries) {
    $object = New-Object -TypeName PSObject
    $object | Add-Member -MemberType NoteProperty -Name "Google_Project" -Value $googleProject
    $object | Add-Member -MemberType NoteProperty -Name "Instance_ID" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_id)
    $object | Add-Member -MemberType NoteProperty -Name "Zone" -Value $($item.resource | Where-Object {$_.type -eq 'gce_instance'} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty zone)
    $object | Add-Member -MemberType NoteProperty -Name "Instance_Name" -Value $($item.metric | Where-Object {$_.type -eq $agentMemoryPath} | Select-Object -ExpandProperty labels | Select-Object -ExpandProperty instance_name)
    $object | Add-Member -MemberType NoteProperty -Name "Max_Agent_Memory(%)" -Value $("{00:N3}" -f ($item.points.value.doubleValue * 100))
    $maxAgentMemoryCPUObject += $object
}
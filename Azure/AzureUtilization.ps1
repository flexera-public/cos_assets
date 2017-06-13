[CmdletBinding()]
param(

    [Parameter(Mandatory=$True)]
    [string]
    $companyName,

    [Parameter(Mandatory=$False)]
    [string]
    $azureUsername,

    [Parameter(Mandatory=$False)]
    [securestring]
    $azurePassword,

    [Parameter(Mandatory=$True, ParameterSetName="CSV")]
    [Parameter(Mandatory=$False, ParameterSetName="Retrieve")]
    [string]
    $csvPath,
    
    [Parameter(Mandatory=$True, ParameterSetName="InLine")]
    [Parameter(Mandatory=$False, ParameterSetName="Retrieve")]
    [string]
    $subscriptionId,

    [Parameter(Mandatory=$False, ParameterSetName="InLine")]
    [Parameter(Mandatory=$False, ParameterSetName="Retrieve")]
    [string]
    $storageAccountName,

    [Parameter(Mandatory=$False, ParameterSetName="InLine")]
    [Parameter(Mandatory=$False, ParameterSetName="Retrieve")]
    [boolean]
    $createStorageAccount = $false,

    [Parameter(Mandatory=$False, ParameterSetName="InLine")]
    [Parameter(Mandatory=$False, ParameterSetName="Retrieve")]
    [string]
    $resourceGroupName = "RSDiagnostics",

    [Parameter(Mandatory=$False, ParameterSetName="InLine")]
    [Parameter(Mandatory=$False, ParameterSetName="Retrieve")]
    [ValidateSet('eastasia','southeastasia','centralus','eastus','eastus2','westus','northcentralus','southcentralus','northeurope','westeurope','japanwest','japaneast','brazilsouth','australiaeast','australiasoutheast','southindia','centralindia','westindia','canadacentral','canadaeast','uksouth','ukwest','westcentralus','westus2','koreacentral','koreasouth')]
    [string]
    $location,

    [Parameter(Mandatory=$False, ParameterSetName="Retrieve")]
    [string[]]
    $customMetricNames,

    [Parameter(Mandatory=$False, ParameterSetName="Retrieve")]
    [int]
    $numberOfDays = 14,

    [Parameter(Mandatory=$False)]
    [switch]
    $checkForExtensions,

    [Parameter(Mandatory=$False)]
    [switch]
    $installExtensions,

    [Parameter(Mandatory=$False)]
    [Parameter(Mandatory=$True, ParameterSetName="Retrieve")]
    [switch]
    $retrieveMetrics

)

#################################
#################################
####### Functions library #######
#################################
#################################

#Complete

function New-StorageAccount($resourceGroupName,$storageAccountName,$storageAccountType){
    $resourceGroup = Get-AzureRmResourceGroup -Name $resourceGroupName
    $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -AccountName $storageAccountName -Location $resourceGroup.Location -Type $storageAccountType
    return $storageAccount
}

function Request-StorageAccountName($storageAccountPrefix){
    $randomResult = ""
    for($i = 0;$i -lt 10;$i++){ $random = Get-Random -Maximum 9 -Minimum 0 ; $randomResult+=$random }
    $storageAccountName = $storageAccountPrefix+$randomResult
    return $storageAccountName
}

function Confirm-DiagnosticsExtension($extensionName, $vmName, $resourceGroupName) {
    $vm = Get-AzureRmVM -Name $vmName -ResourceGroupName $resourceGroupName -WarningAction Ignore
    $extension = Get-AzureRmVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vmName -Name $extensionName -ErrorAction SilentlyContinue
    if ($extension -and ($extension.ProvisioningState -eq "Succeeded") -and ($extension.PublicSettings.Length -gt 300)) {
        return $true
    } else {
        return $false
    }
}

function Enable-DiagnosticsExtension($storageAccountName, $vmName) {
    $sa = Get-AzureRmStorageAccount | Where-Object StorageAccountName -eq $storageAccountName
    $storageAccountKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $sa.ResourceGroupName -Name $storageAccountName
    $storageAccountKey = $storageAccountKeys[0].Value

    $vm = Get-AzureRmVM -WarningAction Ignore | Where-Object Name -eq $vmName 
    $vmId = $vm.Id
    $location = $vm.Location
    $rgName = $vm.ResourceGroupName
    if ($vm.OSProfile.WindowsConfiguration) {
        $osType = "Windows"
    } elseif ($vm.OSProfile.LinuxConfiguration) {
        $osType = "Linux"
    } 

    if ($osType -eq "Windows") {
        $windowsXml ='<?xml version="1.0" encoding="utf-8"?>
    <PublicConfig xmlns="http://schemas.microsoft.com/ServiceHosting/2010/10/DiagnosticsConfiguration">
        <WadCfg>
          <DiagnosticMonitorConfiguration overallQuotaInMB="4096">
            <DiagnosticInfrastructureLogs scheduledTransferLogLevelFilter="Error"/>
            <PerformanceCounters scheduledTransferPeriod="PT1M">
          <PerformanceCounterConfiguration counterSpecifier="\Processor(_Total)\% Processor Time" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU utilization" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor(_Total)\% Privileged Time" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU privileged time" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor(_Total)\% User Time" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU user time" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor Information(_Total)\Processor Frequency" sampleRate="PT15S" unit="Count">
            <annotation displayName="CPU frequency" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\System\Processes" sampleRate="PT15S" unit="Count">
            <annotation displayName="Processes" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Process(_Total)\Thread Count" sampleRate="PT15S" unit="Count">
            <annotation displayName="Threads" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Process(_Total)\Handle Count" sampleRate="PT15S" unit="Count">
            <annotation displayName="Handles" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\% Committed Bytes In Use" sampleRate="PT15S" unit="Percent">
            <annotation displayName="Memory usage" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\Available Bytes" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Memory available" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\Committed Bytes" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Memory committed" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\Commit Limit" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Memory commit limit" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\Pool Paged Bytes" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Memory paged pool" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\Pool Nonpaged Bytes" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Memory non-paged pool" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\% Disk Time" sampleRate="PT15S" unit="Percent">
            <annotation displayName="Disk active time" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\% Disk Read Time" sampleRate="PT15S" unit="Percent">
            <annotation displayName="Disk active read time" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\% Disk Write Time" sampleRate="PT15S" unit="Percent">
            <annotation displayName="Disk active write time" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\Disk Transfers/sec" sampleRate="PT15S" unit="CountPerSecond">
            <annotation displayName="Disk operations" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\Disk Reads/sec" sampleRate="PT15S" unit="CountPerSecond">
            <annotation displayName="Disk read operations" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\Disk Writes/sec" sampleRate="PT15S" unit="CountPerSecond">
            <annotation displayName="Disk write operations" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\Disk Bytes/sec" sampleRate="PT15S" unit="BytesPerSecond">
            <annotation displayName="Disk speed" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\Disk Read Bytes/sec" sampleRate="PT15S" unit="BytesPerSecond">
            <annotation displayName="Disk read speed" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\Disk Write Bytes/sec" sampleRate="PT15S" unit="BytesPerSecond">
            <annotation displayName="Disk write speed" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\Avg. Disk Queue Length" sampleRate="PT15S" unit="Count">
            <annotation displayName="Disk average queue length" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\Avg. Disk Read Queue Length" sampleRate="PT15S" unit="Count">
            <annotation displayName="Disk average read queue length" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk(_Total)\Avg. Disk Write Queue Length" sampleRate="PT15S" unit="Count">
            <annotation displayName="Disk average write queue length" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\LogicalDisk(_Total)\% Free Space" sampleRate="PT15S" unit="Percent">
            <annotation displayName="Disk free space (percentage)" locale="en-us"/>
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\LogicalDisk(_Total)\Free Megabytes" sampleRate="PT15S" unit="Count">
            <annotation displayName="Disk free space (MB)" locale="en-us"/>
          </PerformanceCounterConfiguration>
        </PerformanceCounters>
        <Metrics resourceId="'+$vmId+'" >
            <MetricAggregation scheduledTransferPeriod="PT1H"/>
            <MetricAggregation scheduledTransferPeriod="PT1M"/>
        </Metrics>
        <WindowsEventLog scheduledTransferPeriod="PT1M">
          <DataSource name="Application!*[System[(Level = 1 or Level = 2)]]"/>
          <DataSource name="Security!*[System[(Level = 1 or Level = 2)]"/>
          <DataSource name="System!*[System[(Level = 1 or Level = 2)]]"/>
        </WindowsEventLog>
          </DiagnosticMonitorConfiguration>
        </WadCfg>
    </PublicConfig>'

        $config = [xml]$windowsXml
        $xmlConfigPath = (New-TemporaryFile).FullName
        $config.Save($xmlConfigPath)

        Set-AzureRmVMDiagnosticsExtension -ResourceGroupName $rgName -VMName $vmName -DiagnosticsConfigurationPath $xmlConfigPath -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

    }
    elseif ($osType -eq "Linux") {

        $linuxXml ='<WadCfg>
      <DiagnosticMonitorConfiguration overallQuotaInMB="4096">
        <DiagnosticInfrastructureLogs scheduledTransferPeriod="PT1M" scheduledTransferLogLevelFilter="Warning" />
        <PerformanceCounters scheduledTransferPeriod="PT1M">
          <PerformanceCounterConfiguration counterSpecifier="\Memory\AvailableMemory" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Memory available" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\PercentAvailableMemory" sampleRate="PT15S" unit="Percent">
            <annotation displayName="Mem. percent available" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\UsedMemory" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Memory used" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\PercentUsedMemory" sampleRate="PT15S" unit="Percent">
            <annotation displayName="Memory percentage" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\PercentUsedByCache" sampleRate="PT15S" unit="Percent">
            <annotation displayName="Mem. used by cache" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\PagesPerSec" sampleRate="PT15S" unit="CountPerSecond">
            <annotation displayName="Pages" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\PagesReadPerSec" sampleRate="PT15S" unit="CountPerSecond">
            <annotation displayName="Page reads" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\PagesWrittenPerSec" sampleRate="PT15S" unit="CountPerSecond">
            <annotation displayName="Page writes" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\AvailableSwap" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Swap available" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\PercentAvailableSwap" sampleRate="PT15S" unit="Percent">
            <annotation displayName="Swap percent available" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\UsedSwap" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Swap used" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Memory\PercentUsedSwap" sampleRate="PT15S" unit="Percent">
            <annotation displayName="Swap percent used" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor\PercentIdleTime" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU idle time" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor\PercentUserTime" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU user time" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor\PercentNiceTime" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU nice time" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor\PercentPrivilegedTime" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU privileged time" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor\PercentInterruptTime" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU interrupt time" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor\PercentDPCTime" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU DPC time" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor\PercentProcessorTime" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU percentage guest OS" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\Processor\PercentIOWaitTime" sampleRate="PT15S" unit="Percent">
            <annotation displayName="CPU IO wait time" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk\BytesPerSecond" sampleRate="PT15S" unit="BytesPerSecond">
            <annotation displayName="Disk total bytes" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk\ReadBytesPerSecond" sampleRate="PT15S" unit="BytesPerSecond">
            <annotation displayName="Disk read guest OS" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk\WriteBytesPerSecond" sampleRate="PT15S" unit="BytesPerSecond">
            <annotation displayName="Disk write guest OS" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk\TransfersPerSecond" sampleRate="PT15S" unit="CountPerSecond">
            <annotation displayName="Disk transfers" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk\ReadsPerSecond" sampleRate="PT15S" unit="CountPerSecond">
            <annotation displayName="Disk reads" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk\WritesPerSecond" sampleRate="PT15S" unit="CountPerSecond">
            <annotation displayName="Disk writes" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk\AverageReadTime" sampleRate="PT15S" unit="Seconds">
            <annotation displayName="Disk read time" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk\AverageWriteTime" sampleRate="PT15S" unit="Seconds">
            <annotation displayName="Disk write time" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk\AverageTransferTime" sampleRate="PT15S" unit="Seconds">
            <annotation displayName="Disk transfer time" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\PhysicalDisk\AverageDiskQueueLength" sampleRate="PT15S" unit="Count">
            <annotation displayName="Disk queue length" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\NetworkInterface\BytesTransmitted" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Network out guest OS" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\NetworkInterface\BytesReceived" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Network in guest OS" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\NetworkInterface\PacketsTransmitted" sampleRate="PT15S" unit="Count">
            <annotation displayName="Packets sent" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\NetworkInterface\PacketsReceived" sampleRate="PT15S" unit="Count">
            <annotation displayName="Packets received" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\NetworkInterface\BytesTotal" sampleRate="PT15S" unit="Bytes">
            <annotation displayName="Network total bytes" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\NetworkInterface\TotalRxErrors" sampleRate="PT15S" unit="Count">
            <annotation displayName="Packets received errors" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\NetworkInterface\TotalTxErrors" sampleRate="PT15S" unit="Count">
            <annotation displayName="Packets sent errors" locale="en-us" />
          </PerformanceCounterConfiguration>
          <PerformanceCounterConfiguration counterSpecifier="\NetworkInterface\TotalCollisions" sampleRate="PT15S" unit="Count">
            <annotation displayName="Network collisions" locale="en-us" />
          </PerformanceCounterConfiguration>
        </PerformanceCounters>
        <Metrics resourceId="'+$vmId+'">
          <MetricAggregation scheduledTransferPeriod="PT1H" />
          <MetricAggregation scheduledTransferPeriod="PT1M" />
        </Metrics>
      </DiagnosticMonitorConfiguration>
    </WadCfg>'

        $encodedXml =  [System.Convert]::ToBase64String([system.Text.Encoding]::UTF8.GetBytes($linuxXml))

        $settingsString = '{
            "StorageAccount": "'+$storageAccountName+'",
            "xmlCfg": "'+$encodedXml+'"
}'
        $protectedSettingString = '{
            "storageAccountName": "'+$storageAccountName+'",
            "storageAccountKey": "'+$storageAccountKey+'"
}'

        Set-AzureRmVMExtension -ResourceGroupName $rgName -VMName $vmName -Name "LinuxDiagnostic" -Publisher "Microsoft.OSTCExtensions" -ExtensionType "LinuxDiagnostic" -TypeHandlerVersion "2.3" -Settingstring $settingsString -ProtectedSettingString $protectedSettingString -Location $location
    }

}



#################################
#################################
#######    Main Script    #######
#################################
#################################


if ($azureUsername -and $azurePassword) {
    $azureCred = New-Object System.Management.Automation.PSCredential($azureUsername, $azurePassword)
    Add-AzureRmAccount -Credential $azureCred | Out-Null
} else {
    Add-AzureRmAccount | Out-Null
}

#Stage $accounts variable
$tempObject = New-Object -TypeName psobject
if ($checkForExtensions -AND !$installExtensions -AND !$retrieveMetrics) {
    if ($csvPath) {
        $accounts = Import-Csv -Path $csvPath
    } else {
        if (!$subscriptionId) { 
            Write-Error -Message "Subscription ID not specified"
        } else {
            $tempObject | Add-Member -MemberType NoteProperty -Name subscriptionId -Value $subscriptionId
        }
        $accounts = @()
        $accounts += $tempObject
    }
}

if ($installExtensions) {
    if ($csvPath) {
        $accounts = Import-Csv -Path $csvPath
    } else {
        if (!$subscriptionId) { 
            Write-Error -Message "Subscription ID not specified"
        } else {
            $tempObject | Add-Member -MemberType NoteProperty -Name subscriptionId -Value $subscriptionId
        }
        if ((!$resourceGroupName) -AND ($createStorageAccount -eq $false)) {
            Write-Error -Message "Storage Account not specified" 
        } else {
            $tempObject | Add-Member -MemberType NoteProperty -Name resourceGroupName -Value $resourceGroupName
            $tempObject | Add-Member -MemberType NoteProperty -Name storageAccountName -Value $storageAccountName
            $tempObject | Add-Member -MemberType NoteProperty -Name createStorageAccount -Value $createStorageAccount
            $tempObject | Add-Member -MemberType NoteProperty -Name Location -Value $location
        }
        $accounts = @()
        $accounts += $tempObject
    }
}

#Extension Check
if ($checkForExtensions){
    $extensionStateOutput = @()
    foreach ($account in $accounts) {
        Select-AzureRmSubscription -SubscriptionId $account.subscriptionId
        $vms = Get-AzureRmVM -WarningAction Ignore
        foreach ($vm in $vms) {
            if ($vm.OSProfile.WindowsConfiguration) {
                $extensionName = "IaaSDiagnostics"
            } elseif ($vm.OSProfile.LinuxConfiguration) {
                $extensionName = "LinuxDiagnostic"
            } 
            $extensionState = $null
            $extensionState = Confirm-DiagnosticsExtension -extensionName $extensionName -vmName $vm.Name -resourceGroupName $vm.ResourceGroupName
            $extensionObject = New-Object -TypeName psobject
            $extensionObject | Add-Member -MemberType NoteProperty -Name Name -Value $vm.Name 
            $extensionObject | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $vm.ResourceGroupName
            $extensionObject | Add-Member -MemberType NoteProperty -Name SubscriptionId -Value $account.subscriptionId
            $extensionObject | Add-Member -MemberType NoteProperty -Name ExtensionInstalled -Value $extensionState
            $extensionStateOutput += $extensionObject
        }
    }
    $extensionStateOutput | Export-Csv -Path ".\$companyName-Phase1-AllVMExtensionState.csv" -Force
    $extensionStateOutput | Where-Object ExtensionInstalled -eq $False | Export-Csv -Path ".\$companyName-Phase1-VMsWithoutExtensions.csv" -Force
    
}

#Install Diagnostic Extensions
if ($installExtensions) {
    $vmsRequiringReboot = @()
    $vmsPoweredOff = @()
    if ($checkForExtensions) {
        foreach ($account in $accounts) {
            Select-AzureRmSubscription -SubscriptionId $account.subscriptionId
            $vms = import-csv ".\$companyName-Phase1-VMsWithoutExtensions.csv" | Where-Object SubscriptionId -eq $account.subscriptionId
            if ($createStorageAccount) {
                if (!$account.storageAccountName) {
                    $saName = Request-StorageAccountName -storageAccountPrefix "rsdiag"
                } else {
                    $saName = $account.storageAccountName
                }
                if (!$account.resourceGroupName) {
                    $rgName = "RSDiagnostics"
                } else {
                    $rgName = $account.ResourceGroupName
                }
                $rgTest = Get-AzureRmResourceGroup -Name $rgName -ErrorAction SilentlyContinue
                if (!$rgTest) {
                    $rg = New-AzureRmResourceGroup -Name $rgName -Location $account.Location
                    $rgName = $rg.ResourceGroupName
                } else {
                    $rgName = $rgTest.ResourceGroupName
                }
                $storageAccount = New-StorageAccount -resourceGroupName $rgName -storageAccountName $saName -storageAccountType "Standard_LRS"
            } else {
                $saName = $account.storageAccountName
            }
            
            foreach ($vm in $vms) {
                if ((Get-AzureRmVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Status -WarningAction Ignore).Statuses[1].DisplayStatus -eq "VM running") { 
                    Enable-DiagnosticsExtension -storageAccountName $saName -vmName $vm.Name
                    $vmObject = New-Object -TypeName psobject
                    $vmObject | Add-Member -MemberType NoteProperty -Name VmName -Value $vm.Name 
                    $vmObject | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $vm.ResourceGroupName
                    $vmObject | Add-Member -MemberType NoteProperty -Name SubscriptionId -Value $account.subscriptionId
                    $vmsRequiringReboot += $vmObject
                } else {
                    $vmObject = New-Object -TypeName psobject
                    $vmObject | Add-Member -MemberType NoteProperty -Name VmName -Value $vm.Name 
                    $vmObject | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $vm.ResourceGroupName
                    $vmObject | Add-Member -MemberType NoteProperty -Name SubscriptionId -Value $account.subscriptionId
                    $vmsPoweredOff += $vmObject
                }
            }
        }
    } else {
        foreach ($account in $accounts) {
            Select-AzureRmSubscription -SubscriptionId $account.subscriptionId
            $checkvms = Get-AzureRmVM -WarningAction Ignore
            if ($createStorageAccount) {
                if (!$account.storageAccountName) {
                    $saName = Request-StorageAccountName -storageAccountPrefix "RSDiag"
                } else {
                    $saName = $account.storageAccountName
                }
                if (!$account.resourceGroupName) {
                    $rgName = "RSDiagnostics"
                } else {
                    $rgName = $account.ResourceGroupName
                }
                $rgTest = Get-AzureRmResourceGroup -Name $rgName -ErrorAction SilentlyContinue
                if (!$rgTest) {
                    $rg = New-AzureRmResourceGroup -Name $rgName -Location $account.Location
                    $rgName = $rg.ResourceGroupName
                } else {
                    $rgName = $rgTest.ResourceGroupName
                }
                $storageAccount = New-StorageAccount -resourceGroupName $rgName -storageAccountName $saName -storageAccountType "Standard_LRS"
            } else {
                $saName = $account.storageAccountName
            }
            foreach ($vm in $checkvms) {
                if (($vm | Get-AzureRmVM -Status -WarningAction Ignore).Statuses[1].DisplayStatus -eq "VM running") {
                    if ($vm.OSProfile.WindowsConfiguration) {
                        $extensionName = "IaaSDiagnostics"
                    } elseif ($vm.OSProfile.LinuxConfiguration) {
                        $extensionName = "LinuxDiagnostic"
                    } 
                    $extensionState = $null
                    $extensionState = Confirm-DiagnosticsExtension -extensionName $extensionName -vmName $vm.Name -resourceGroupName $vm.ResourceGroupName
                    if (!$extensionState) {
                        Enable-DiagnosticsExtension -storageAccountName $saName -vmName $vm.Name
                        $vmObject = New-Object -TypeName psobject
                        $vmObject | Add-Member -MemberType NoteProperty -Name VmName -Value $vm.Name 
                        $vmObject | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $vm.ResourceGroupName
                        $vmObject | Add-Member -MemberType NoteProperty -Name SubscriptionId -Value $account.subscriptionId
                        $vmsRequiringReboot += $vmObject
                    }
                } else {
                    $vmObject = New-Object -TypeName psobject
                    $vmObject | Add-Member -MemberType NoteProperty -Name VmName -Value $vm.Name 
                    $vmObject | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $vm.ResourceGroupName
                    $vmObject | Add-Member -MemberType NoteProperty -Name SubscriptionId -Value $account.subscriptionId
                    $vmsPoweredOff += $vmObject
                }
            }
        }
    }
    $vmsRequiringReboot | Export-Csv -Path ".\$companyName-Phase2-VMsRequiringReboot.csv" -Force
    $vmsPoweredOff | Export-Csv -Path ".\$companyName-Phase2-VMsPoweredOff-ExtensionNotInstalled.csv" -Force
}

if ($retrieveMetrics) {
    $defaultWindowsMetrics = @("\Processor Information(_Total)\% Processor Time", "\Memory\Available Bytes", "\Memory\Committed Bytes" )
    $defaultLinuxMetrics =  @("\Processor\PercentProcessorTime", "\Memory\AvailableMemory", "\Memory\UsedMemory")
    $results = @()

    if ($subscriptionId) {
        $accounts = @($subscriptionId)
    } elseif ($csvPath) {
        $accounts = (Import-CSV $csvPath).subscriptionId
    } else {
        $accounts = (Get-AzureRmSubscription).SubscriptionId
    }

    $end = Get-Date
    $start = $end.AddDays(-$numberOfDays)
    $timegrain = "00:01:00" 
    $timespan = "$(get-date $start -format d) - $(get-date $end -format d)"

    foreach ($account in $accounts) {
        Select-AzureRmSubscription -SubscriptionId $account -OutVariable "subscription"
        $vms = Get-AzureRmVM -WarningAction Ignore
        foreach ($vm in $vms) {
            if ($vm.OSProfile.WindowsConfiguration) {
                $extensionName = "IaaSDiagnostics"
            } elseif ($vm.OSProfile.LinuxConfiguration) {
                $extensionName = "LinuxDiagnostic"
            }
            $extensionState = $null
            $extensionState = Confirm-DiagnosticsExtension -extensionName $extensionName -vmName $vm.Name -resourceGroupName $vm.ResourceGroupName
            if ($extensionState) {
                if ($extensionName -eq "IaaSDiagnostics") {
                    $metricNames = $defaultWindowsMetrics
                } else {
                    $metricNames = $defaultLinuxMetrics
                }
                foreach ($metricName in $metricNames) {
                    #Get Default Metrics
                    $metric = Get-AzureRmMetric -ResourceId $vm.Id -TimeGrain $timegrain -StartTime $start -EndTime $end -MetricNames $metricName -WarningAction Ignore
                    
                    #Default Metric Calculations
                    if ($metricName -like "*Processor*") {
                        if (!$metric) { 
                            $avgCPU = "N/A"
                            $maxCPU = "N/A" 
                        } else {
                            $avg, $i = $null
                            $metric.MetricValues | ForEach-Object { $avg += $_.Average ; $i++ }
                            $avgCPU = $avg / $i 
                            $maxCPU = ($metric.MetricValues | Sort-Object Maximum -Descending).Maximum
                        }

                    } elseif ($metricName -like "*Memory*") {
                        if ($metricName -like "*Available*") {
                            if (!$metric) {
                                $availMem = "N/A"
                            } else {
                                $availMem = ($metric.MetricValues | Sort-Object Timestamp | Select-Object -First 1).Maximum
                            }
                        } else {
                            if (!$metric) {
                                $avgMemUsed = "N/A"
                                $maxMemUsed = "N/A"
                                $usedMem = "N/A"
                            } else {
                                $usedMem = ($metric.MetricValues | Sort-Object Timestamp | Select-Object -First 1).Maximum
                                $avg, $i = $null
                                $metric.MetricValues | ForEach-Object { $avg += $_.Average ; $i++ }
                                $avgMemUsed = $avg / $i
                                $maxMemUsed = ($metric.MetricValues | Sort-Object Maximum -Descending).Maximum /1024/1024/1024

                            }
                        }
                    }
                }
                #Calculate Avg Mem %
                if (($usedMem -eq "N/A") -or ($availMem -eq "N/A") -or ($avgMemUsed -eq "N/A")) { 
                    $calcMemUsed = "N/A"
                } else {
                    $totalMemGB = [math]::Round($(($usedMem + $availMem)/1024/1024/1024),1)
                    $calcMemUsed = ($avgMemUsed / $totalMemGB) * 100 
                }
                if ($customMetricNames) {
                    foreach ($customMetric in $customMetricNames) {
                        #Get Custom Metrics
                        $metric = Get-AzureRmMetric -ResourceId $vm.Id -TimeGrain $timegrain -StartTime $start -EndTime $end -MetricNames $customMetric -WarningAction Ignore
                        if ($metric) {
                            $avg, $i = $null
                            $metric.MetricValues | ForEach-Object { $avg += $_.Average ; $i++ }
                            $avgMetric = $avg / $i 
                        } else {
                            $avgMetric = "N/A"
                        }
                        New-Variable -Name "$customMetric" -Value $avgMetric
                    }
                }
            } else {
                #Diagnostics Extension not installed
                $avgCPU = "Ext Not Installed"
                $maxCPU = "Ext Not Installed"
                $calcMemUsed = "Ext Not Installed"
                $avgMemUsed = "Ext Not Installed"
                $maxMemUsed = "Ext Not Installed"
            }
            $psObject = New-Object -TypeName psobject
            $psObject | Add-Member -MemberType NoteProperty -Name "SubscriptionName" -Value $subscription.Subscription.SubscriptionName
            $psObject | Add-Member -MemberType NoteProperty -Name "SubscriptionId" -Value $subscription.Subscription.SubscriptionId
            $psObject | Add-Member -MemberType NoteProperty -Name "VMname" -Value $vm.Name
            $psObject | Add-Member -MemberType NoteProperty -Name "ResourceId" -Value $vm.Id
            $psObject | Add-Member -MemberType NoteProperty -Name "Region" -Value $vm.Location
            $psObject | Add-Member -MemberType NoteProperty -Name "Timespan" -Value $timespan
            $psObject | Add-Member -MemberType NoteProperty -Name "Avg-CPU%" -Value $avgCPU
            $psObject | Add-Member -MemberType NoteProperty -Name "Max-CPU%" -Value $maxCPU 
            $psObject | Add-Member -MemberType NoteProperty -Name "Avg-MemUsed%(Calculated)" -Value $calcMemUsed 
            $psObject | Add-Member -MemberType NoteProperty -Name "Avg-MemUsed(GB)" -Value $avgMemUsed
            $psObject | Add-Member -MemberType NoteProperty -Name "Max-MemUsed(GB)" -Value $maxMemUsed
            foreach ($customMetric in $customMetricNames) {
                $custMetricVal = Get-Variable -Name "$customMetric" -ValueOnly
                $psObject | Add-Member -MemberType NoteProperty -Name "Avg-$customMetric" -Value $custMetricVal
            }
            $results += $psObject
        } 
    }
    $results | Export-Csv -Path ".\$companyName-Metrics.csv" -Force
}


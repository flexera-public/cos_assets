# Azure Utilization Script

## Overview
The purpose of this script is to complete the following tasks.  They can be executed at the same time or separately (see **Usage** for more info):
- Generate list of VMs that do not have the Diagnostics Extension installed
    - IaaSDiagnostics for Windows VMs
    - LinuxDiagnostic for Linux VMs
- Install Diagnostics Extension on VMs
- Retrieve Diagnostics metrics 

## Getting Started
There are 2 main ways to execute the script: using in-line parameters & using a CSV input.  The CSV is the recommended method, as it allows support for multiple subscriptions.

### Pre-Reqs
- Windows Instance
- PowerShell v5.0 or higher
- AzureRM PowerShell Module

## Usage

### Recommended Usage

- If the customer has stated that they alread have the Diagnostics Extension installed on their VMs:
    1. Ask for the XML configs used to enable the Extensions and verify if the **Default Metrics** of this script are listed in their XML configs.
    1. If the **Default Metrics** are in their config, proceed to execute script with `-retrieveMetrics`
    1. If the **Default Metrics** are not in their config, identify which Metrics to gather, and proceed to execute script with `-retrieveMetrics -customMetricNames foo,bar`
- If the customer knows that the Diagnostics Extension is not installed on all of their VMs, or if they are unsure:
    1. Execute script with `-checkForExtensions`
    1. Provide customer with list of VMs that do not have the extension
    1. Schedule time to:
        - Execute script with `-installExtensions`
        - Schedule reboot of VMs
        - **Note:** These 2 steps can be scheduled during different Maintenance Windows
    1. Execute script with `-retrieveMetrics` 

### Parameters
The Parameters listed below have the same purpose, regardless of execution method.

| Parameter Name | Required? | Description | Usage | Type | Notes |
|----------------|-----------|-------------|-------|------|-------|
| companyName | yes | The name of the customer who's Azure subscriptions are being scanned.  This name will be used when naming the output files | CSV & In-Line | string | This value must always be passed In-Line, regardless of whether you are using a CSV input or not |
| azureUsername | no | Email address to authenticate with Azure (note: must be an Azure AD account). If not supplied, the script will prompt for authentication | CSV & In-Line | string | This parameter may not be specified in a CSV input |
| azurePassword | no | Password to authenticate with Azure (note: must be used in conjunction with `azureUsername`) | CSV & In-Line | secure string | This parameter may not be specified in a CSV input |
| csvPath | yes`*` | Absolute or relative path to CSV input file | CSV | string | See **CSV Input Template** below |
| subscriptionId | yes`**` | Azure Subscription ID | In-Line | string | |
| storageAccountName | no | Name of Storage Account to hold Diagnostics data | In-Line | string | If not specified AND if `createStorageAccount` set to `$true`, a randomly named Storage Account will be created |
| createStorageAccount | no | If set to `$true` a new Storage Account will be created | In-Line | boolean | Default value = `$false` | 
| resourceGroupName | no | Name of the Resource Group that will contain the Storage Account for Diagnostics Data | In-Line | string | If the Resource Group doesn't exist, one will be created with the name specified. If not specified AND if `createStorageAccount` set to `$true`, a Resource Group named `RSDiagnostics` will be created | 
| location | no | Azure Region where the Resource Group will be created | In-Line | string | Required if the `resourceGroupName` value is not an existing Resource Group OR if the `resourceGroupName` values is not specified and `createStorageAccount` is set to `$true`.  Valid values: `eastasia`, `southeastasia`, `centralus`, `eastus`, `eastus2`, `westus`, `northcentralus`, `southcentralus`, `northeurope`, `westeurope`, `japanwest`, `japaneast`, `brazilsouth`, `australiaeast`, `australiasoutheast`, `southindia`, `centralindia`, `westindia`, `canadacentral`, `canadaeast`, `uksouth`, `ukwest`, `westcentralus`, `westus2`, `koreacentral`, `koreasouth` | 
| checkForExtensions | no | If set, the portion of the script that discovers VMs without the Diagnostics Extension will executte | CSV & In-Line | switch | Can be used in conjunction with other switches |
| installExtensions | no | If set, the portion of the script that installs the Diagnostics Extension on VMs will executte | CSV & In-Line | switch | Can be used in conjunction with other switches |
| retrieveMetrics | no | If set, the portion of the script that retrieves Diagnostics data will executte | CSV & In-Line | switch | Can be used in conjunction with other switches, although that doesn't sound like a logical use case |
| numberOfDays | no | Identifies how many days to retrieve metrics for | CSV & In-Line | integer | Default value is `14`.  Only needed if `-retrieveMetrics` is set & need to gather metrics for a different timespan | 
| customMetricNames | no | Array of additional Metric Names to be gathered (beyond default metrics) | CSV & In-Line | string[] | Only the average of the specified metrics will be retrieved | 

`*`Only required when executing via the CSV Input method

`**`Only required when executing via the In-Line method

### CSV Input Template
```
subscriptionId,resourceGroupName,storageAccountName,createStorageAccount,location
12345678-1234-1234-1234-123456789012,MyResourceGroup,sa12345foobar,$false,eastus
asdfghjk-asdf-asdf-asdf-asdfghjklasd,,,$true,centralus
qwertyui-qwer-qwer-qwer-qwertyuiopqw,Foobar123,,$true,northeurope
```
- For the first subscription, neither a Resource Group nor Storage Account will be created.  The script assumes that `MyResourceGroup` and `sa12345foobar` already exist and does not attempt to create them.
- For the second subscription, since `createStorageAccount` is set to `$true` AND values are not specified for `resourceGroupName` or `storageAccountName`, the script will create a Resource Group named `RSDiagnostics` and a randomly named Storage Account.
- For the last subscription, a randomly named Storage Account will be created, and will be placed in the `Foobar123` Resource Group.  If that Resource Group does not already exist, one will be created with that name.

**Note:** it is not recommended to set `createStorageAccount` to `$true` AND supply a value for `storageAccountName`.  As Storage Account names must be globally unique, this could result in error.

### Execution Examples
All examples below assume that the `AzureUtilization.ps1` script is in the working directory.

#### CSV Input
##### Example 1
.\AzureUtilization.ps1 -companyName "Kramerica" -csvPath "C:\Users\Kramer\Documents\myazureaccounts.csv" -checkForExtensions -installExtensions

In Example 1, user will be prompted for Azure credentials during script execution. 

##### Example 2
$mycred = Get-Credential

.\AzureUtilization.ps1 -companyName "Kramerica" -csvPath "C:\Users\Kramer\Documents\myazureaccounts.csv" -azureUsername $mycred.UserName -azurePassword $mycred.Password -retrieveMetrics

In Example 2, user will be prompted for credentials prior to executing the AzureUtilization script.

#### In-line Parameters
##### Example 1
.\AzureUtilization.ps1 -companyName "Kramerica" -subscriptionId "12345678-1234-1234-1234-123456789012" -resourceGroupName "MyResourceGroup" -storageAccountName "sa12345foobar" -location eastus -checkForExtensions -installExtensions

##### Example 1
$mycred = Get-Credential

.\AzureUtilization.ps1 -companyName "Kramerica" -subscriptionId "12345678-1234-1234-1234-123456789012" -resourceGroupName "MyResourceGroup" -createStorageAccount $true -azureUsername $mycred.UserName -azurePassword $mycred.Password -location eastus -retrieveMetrics

## Retrieve Metrics - Additional Notes
- In the event that you would like to target specific Subscriptions to retrieve VM Metrics, you may use the `-subscriptionId` or `-csvPath` parameters.  If you would like to retrieve VM Metrics across all Subscriptions (that the user account has access to), you can execute `-retrieveMetrics` without either of these additional parameters.
- The `-customMetricNames` parameter can be used in conjunction with `-retrieveMetrics` if necessary.  The output will only be the Metrics' average, in the format returned by Azure (ie. If Azure returns values in `bytes`, the result will be Average Bytes during the same timespan as the Default Metrics)
- If a VM does not have the Diagnostics Extension installed, the Metric fields will have a value of: `Ext Not Installed`
- If a VM has the Diagnostics Extension installed, but does not return a value for the target metric, the Metric field will have a value of: `N/A`

### Default Metrics
The following are the Default Metrics that will attempt to be gathered when executing the script with `-retrieveMetrics`:

- **Windows:**
    - \Processor Information(_Total)\% Processor Time
    - \Memory\Available Bytes 
    - \Memory\Committed Bytes

- **Linux:**  
    - \Processor\PercentProcessorTime
    - \Memory\AvailableMemory
    - \Memory\UsedMemory


## Outputs
All outputs will appear in the working directory.

### checkForExtensions
- [Company Name]-Phase1-AllVMExtensionState.csv
- [Company Name]-Phase1-VMsWithoutExtensions.csv

### installExtensions
- [Company Name]-Phase2-VMsRequiringReboot.csv
- [Company Name]-Phase2-VMsPoweredOff-ExtensionNotInstalled.csv

### retrieveMetrics
- [Company Name]-Metrics.csv

#### Fields returned in Metrics Output
- SubscriptionName
- SubscriptionId
- VMname
- ResourceId
- Region
- Timespan
- Avg-CPU%
- Max-CPU%
- Avg-MemUsed%(Calculated)
- Avg-MemUsed(GB)
- Max-MemUsed(GB)
**Optional:**
- Avg-[Custom Metric Name]

## Limitations
- Azure Classic is not supported
- VM must be running to install the Diagnostics Extension 
- VM must be rebooted after Diagnostics Extension is installed and before Metrics are retrieved
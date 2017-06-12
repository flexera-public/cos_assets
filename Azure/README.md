# Azure Utilization Script

## Overview
The purpose of this script is to complete the following tasks.  They can be executed at the same time or separately (see [Usage](.\README.md#Usage) for more info):
- Generate list of VMs that do not have the Diagnostics Extension installed
    - IaaSDiagnostics for Windows VMs
    - LinuxDiagnostic for Linux VMs
- Install Diagnostics Extension on VMs
- Retrieve Diagnostics metrics 

## Getting Started
There are 2 main ways to execute the script: using in-line parameters & using a CSV input.  The CSV is the recommended method, as it allows support for multiple subscriptions.

## Usage
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

## Outputs
All outputs will appear in the working directory.

### checkForExtensions
- [Company Name]-Phase1-AllVMExtensionState.csv
- [Company Name]-Phase1-VMsWithoutExtensions.csv

### installExtensions
- [Company Name]-Phase2-VMsRequiringReboot.csv
- [Company Name]-Phase2-VMsPoweredOff-ExtensionNotInstalled.csv

### retrieveMetrics


## Limitations
- VM must be running to install the Diagnostics Extension 
- VM must be rebooted after Diagnostics Extension is installed and before Metrics are retrieved
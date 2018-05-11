# Find the RSC executable, searches in the current working directory, users home directory, and in known locations
Write-Output "Finding RSC executable..."
$rscName = $null; $rscPaths = $null; $rsc = $null
if($PSVersionTable.PSEdition -eq "Core") {
    # We are using PowerShell Core
    if($IsLinux -or $IsOSX -or $IsMacOS) {
        $rscName = 'rsc'
        $rscPaths = $PWD, $HOME, '/usr/local/bin', '/opt/bin/'
    } elseif ($IsWindows) {
        $rscName = 'rsc.exe'
        $rscPaths = $PWD, $HOME, 'C:\Program Files\RightScale\RightLink'
    } else {
        # Fail safe if '$Is...` variables are not-present
        if(Test-Path -Path 'C:\Windows\System32') {
            # Windows
            $rscName = 'rsc.exe'
            $rscPaths = $PWD, $HOME, 'C:\Program Files\RightScale\RightLink'
        }
        else {
            # Linux / OSX
            $rscName = 'rsc'
            $rscPaths = $PWD, $HOME, '/usr/local/bin', '/opt/bin/'
        }
    }
} elseif ($PSVersionTable.PSEdition -eq "Desktop") {
    # We are using PowerShell Desktop, assume windows
    $rscName = 'rsc.exe'
    $rscPaths = $PWD, $HOME, 'C:\Program Files\RightScale\RightLink'
}

if($rscName -and $rscPaths) {
    $rscExecutables = Get-ChildItem -Path $rscPaths -Recurse -File -Filter $rscName -ErrorAction SilentlyContinue
    $rsc = $rscExecutables | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    $rscVersion = &$rsc --version
    Write-Output "Using RSC: $rsc"
    Write-Output "Details: $rscVersion"
} else {
    Write-Output "Unable to determine location of RSC!"
    Write-Output "RSC is required and can be downloaded from: https://github.com/rightscale/rsc"
    EXIT 1
}

# Prompt for user and account details
$email = Read-Host "Enter RS email address" # Email address associated with RS user
$pass = Read-Host "Enter RS Password" -AsSecureString # RS password
$endpoint = Read-Host "Enter RS API endpoint (us-3.rightscale.com -or- us-4.rightscale.com)" # us-3.rightscale.com -or- us-4.rightscale.com
$accounts = Read-Host "Enter RS Account Number(s) (comma-separated if multiple)" # RS account number(s)
$customerName = Read-Host "Enter Customer Name" # For CSV file name
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

Write-Output "** Script Start Time: $(Get-Date)"

if ($accounts -like "*,*") {
    $accounts = $accounts.Split(",")
}

$unattachedVolumes = @()
foreach ($account in $accounts) {
    $account = $account.Trim()
    $clouds = &$rsc --email=$email --pwd=$password --host=$endpoint --account=$account cm15 index clouds | ConvertFrom-json
    if (!($clouds)) {
        Write-Output "$account : No clouds registered to this account."
        CONTINUE
    }
    else {
        foreach ($cloud in $clouds) {
            $cloudName = $cloud.display_name
            if($cloudName -like "AzureRM*") {
                $volumeTypes = &$rsc --email=$email --pwd=$password --host=$endpoint --account=$account cm15 index $($cloud.links | Where-Object { $_.rel -eq 'volume_types' } | Select-Object -ExpandProperty href) | ConvertFrom-Json
                $volumeTypes = $volumeTypes | Select-Object name, resource_uid, @{n='href';e={$_.links | Where-Object {$_.rel -eq 'self'}| Select-Object -ExpandProperty href}}
            }
            if ($($cloud.links | Where-Object { $_.rel -eq 'volumes'})) {                                                                              
                $volumes = @()
                $volumes = &$rsc --email=$email --pwd=$password --host=$endpoint --account=$account cm15 index $($cloud.links | Where-Object { $_.rel -eq 'volumes' } | Select-Object -ExpandProperty href) "view=extended"| ConvertFrom-Json
                if(!($volumes)) {
                    Write-Output "$account : $cloudName : No volumes"
                    CONTINUE
                }
                else {
                    foreach ($volume in $volumes) {
                        if (($volume.status -eq "available") -and ($volume.resource_uid -notlike "*system@Microsoft.Compute/Images/*") -and ($volume.resource_uid -notlike "*@images*")) {
                            Write-Output "$account : $cloudName : $($volume.name) - $($volume.resource_uid) : Unattached"
                            
                            if($cloudName -like "AzureRM*") {
                                $volumeTypeHref = $volume.links | Where-Object { $_.rel -eq "volume_type" } | Select-Object -ExpandProperty href
                                $placementGroupHref = $volume.links | Where-Object { $_.rel -eq "placement_group" } | Select-Object -ExpandProperty href
                                if($placementGroupHref) {
                                    $armDiskType = "Unmanaged"
                                    $placementGroup = &$rsc --email=$email --pwd=$password --host=$endpoint --account=$account cm15 show $placementGroupHref "view=extended" 2>$null| ConvertFrom-Json
                                    if ($placementGroup) {
                                        $armStorageType = $placementGroup.cloud_specific_attributes.account_type
                                    }
                                    else {
                                        Write-Output "$account : $cloudName : $($volume.name) - $($volume.resource_uid) : ERROR retrieving Placement Group!!"
                                        $armStorageType = "ERROR"
                                    }
                                    $armStorageAccountName = $volume.placement_group.name
                                }
                                elseif($volumeTypeHref) {
                                    $armDiskType = "Managed"
                                    $armStorageType = $volumeTypes | Where-Object { $_.href -eq $volumeTypeHref } | Select-Object -ExpandProperty name
                                    $armStorageAccountName = "N/A"
                                }
                                else {
                                    $armDiskType = "Unknown"
                                    $armStorageType = "Unknown"
                                    $armStorageAccountName = "Unknown"
                                }
                            }
                            elseif ($cloudName -like "Azure*") {
                                $armDiskType = "Unmanaged"
                                $armStorageType = "Classic"
                                $armStorageAccountName = $volume.placement_group.name
                                if(!($armStorageAccountName)) {
                                    $armStorageAccountName = "Unknown"
                                }
                            }
                            else {
                                $armDiskType = "N/A"
                                $armStorageType = "N/A"
                                $armStorageAccountName = "N/A"
                            }

                            $object = New-Object -TypeName PSObject
                            $object | Add-Member -MemberType NoteProperty -Name "RS_Account_ID" -Value $account
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
                            $object | Add-Member -MemberType NoteProperty -Name "Created_At" -Value $volume.created_at
                            $object | Add-Member -MemberType NoteProperty -Name "Updated_At" -Value $volume.updated_at
                            $object | Add-Member -MemberType NoteProperty -Name "Cloud_Specific_Attributes" -Value $volume.cloud_specific_attributes
                            $object | Add-Member -MemberType NoteProperty -Name "Href" -Value $($volume.links | Where-Object rel -eq "self").href
                            $unattachedVolumes += $object
                        }
                        else {
                            Write-Output "$account : $cloudName : $($volume.name) - $($volume.resource_uid) : Attached"
                        }
                    }
                }
            }
        }
    }
}

if ($unattachedVolumes.count -gt 0){
    $csvTime = Get-Date -Format dd-MMM-yyyy_hhmmss
    $csvFile = "./$($customerName)_unattached-volumes_$($csvTime).csv"
    $unattachedVolumes | Export-Csv $csvFile -NoTypeInformation
    $csvFilePath = Get-item $csvFile | Select-Object -ExpandProperty FullName  
    Write-Output "** CSV File: $csvFilePath"
}
else {
    Write-Output "** No unattached volumes found!"
}
Write-Output "** Script End Time: $(Get-Date)"
# Splits the results of a CSV into 'n' number of files containing 'n' number of lines
# Pulls out operational instances only

function Split-Array 
{

<#  
  .SYNOPSIS   
    Split an array
  .NOTES
    Version : July 2, 2017 - implemented suggestions from ShadowSHarmon for performance   
  .PARAMETER inArray
   A one dimensional array you want to split
  .EXAMPLE  
   Split-array -inArray @(1,2,3,4,5,6,7,8,9,10) -parts 3
  .EXAMPLE  
   Split-array -inArray @(1,2,3,4,5,6,7,8,9,10) -size 3
#> 

  param($InArray,[int]$Parts,[int]$Size)
  
  if ($Parts) {
    $PartSize = [Math]::Ceiling($inArray.count / $Parts)
  } 
  if ($Size) {
    $PartSize = $Size
    $Parts = [Math]::Ceiling($inArray.count / $Size)
  }

  $outArray = New-Object 'System.Collections.Generic.List[psobject]'

  for ($i=1; $i -le $Parts; $i++) {
    $start = (($i-1)*$PartSize)
    $end = (($i)*$PartSize) - 1
    if ($end -ge $inArray.count) {$end = $inArray.count -1}
	$outArray.Add(@($inArray[$start..$end]))
  }
  return ,$outArray

}

$csvFile = Read-Host "Enter the path to the csv to import"
$numberOfLines = Read-Host "How many lines per file"

if(Test-Path -Path $csvFile) {
    $fileDetails = Get-ChildItem $csvFile
    $csvName = $fileDetails.BaseName
    $importedInstances = Import-Csv -Path $csvFile
}
else {
    Write-Host "File $csvFile does not exist!"
    EXIT 1
}

$operationalInstances = $importedInstances | Where-Object { $_.State -eq "Operational" }

$splitResults = Split-Array -InArray $operationalInstances -Size $numberOfLines
$counter = 1
$totalFiles = $splitResults.count
foreach ($result in $splitResults) {
    $result | Export-Csv -Path "./$($csvName)_Part$($counter)of$($totalFiles).csv" -NoTypeInformation
    $counter++
}
<#
.SYNOPSIS
Creates a Bill Connect in Optima using Cross Account IAM Roles.
.DESCRIPTION
This will create a Bill Connect in Optima using AWS Cross Account IAM Roles.
.PARAMETER OrganizationId
The Flexera CMP Organization Id.
.PARAMETER Endpoint
The Cloud Management endpoint for your account. Valid values: us-3.rightscale.com, us-4.rightscale.com.
.PARAMETER RefreshToken
The users refresh token.
.PARAMETER MasterAccountId
The Master Account ID.
.PARAMETER AWSBillAccountId
Name AWS Bill Account Id.
.PARAMETER AWSBucketName
The name of the S3 bucket where the Hourly Cost and Usage Reports (HCUR) are stored.
.PARAMETER AWSBucketPath
The path within the S3 bucket to the reports.
.PARAMETER AWSRoleARN
The ARN of the role created to access the account.
.PARAMETER AWSRoleSessionName
The session name for the connect. Defaults to flexera-optima and does not need to be changed.
.EXAMPLE
Create-OptimaAWSCrossAccountBillConnect.ps1 -OrganizationID 123 -Endpoint "us-3.rightscale.com" -RefreshToken "abc...123" -MasterAccountId 54321 -AWSBillAccountId "123456789012" -AWSBucketName "reports" -AWSBucketPath "path/to/reports/" -AWSRoleARN "arn:aws:iam::123456789012:role/bill_access_role"
.LINK
https://docs.rightscale.com/
.LINK
https://reference.rightscale.com/optima_front/#/AWSBillConnects/AWSBillConnects_createIAMRole
.LINK
https://docs.rightscale.com/api/general_usage.html
#>

[CmdletBinding()]

param(
    [Parameter(Position=0,mandatory=$true)]
    [Int]
    $OrganizationID,

    [Parameter(Position=1,mandatory=$true)]
    [ValidateSet("us-3.rightscale.com", "us-4.rightscale.com")]
    [String]
    $Endpoint,
    
    [Parameter(Position=2,mandatory=$true)]
    [String]
    $RefreshToken,

    [Parameter(Position=3,mandatory=$true)]
    [String]
    $MasterAccountId,
    
    [Parameter(Position=4,mandatory=$true)]
    [String]
    $AWSBillAccountId,

    [Parameter(Position=5,mandatory=$true)]
    [String]
    $AWSBucketName,

    [Parameter(Position=6,mandatory=$false)]
    [String]
    $AWSBucketPath = "/",

    [Parameter(Position=7,mandatory=$true)]
    [String]
    $AWSRoleARN,

    [Parameter(Position=8,mandatory=$false)]
    [String]
    $AWSRoleSessionName = "flexera-optima"
)

function Get-CMPAccessToken {
    [CmdletBinding()]

    param(
        [Parameter(Position=0,mandatory=$true)]
        [ValidateSet("us-3.rightscale.com", "us-4.rightscale.com")]
        [String]
        $Endpoint,
        
        [Parameter(Position=1,mandatory=$true)]
        [String]
        $RefreshToken,

        [Parameter(Position=2,mandatory=$true)]
        [String]
        $AccountId
    )

    try {
        $contentType = "application/json"
        $oAuthHeader = @{
            "X_API_VERSION" = "1.5";
            "X-Account" = $AccountId
        }

        $oAuthBody = @{
            "grant_type"    = "refresh_token";
            "refresh_token" = $RefreshToken
        } | ConvertTo-Json

        Write-Verbose "Retrieving access token..."

        $oAuthResult = Invoke-RestMethod -Uri "https://$Endpoint/api/oauth2" -Method Post -Headers $oAuthHeader -ContentType $contentType -Body $oAuthBody
        $accessToken = $oAuthResult.access_token

        if (-not($accessToken)) {
            Write-Warning "Error retrieving access token!"
            EXIT 1
        }

        Write-Verbose "Successfully retrieved access token!"
        $accessToken
    }
    catch {
        Write-Warning "Error retrieving access token'! $($_ | Out-String)"
    }
}

$accessToken = Get-CMPAccessToken -Endpoint $Endpoint -RefreshToken $RefreshToken -AccountId $MasterAccountId

# Check for existing bill connect
$contentType = "application/json"

$optimaHeader = @{
    "Api-Version" = "1.0";
    "Authorization" = "Bearer $accessToken"
}

try {
    $getResult = Invoke-RestMethod -Uri "https://onboarding.rightscale.com/api/onboarding/orgs/$OrganizationID/bill_connects/aws/aws-$($AWSBillAccountId)" -Method Get -Headers $optimaHeader -ContentType $contentType -ErrorAction SilentlyContinue -ErrorVariable getResultError
    Write-Warning "There is already a bill connect with that account id!"
    $getResult
    EXIT 1
}
catch {
    $getResultError = $getResultError.Message | ConvertFrom-Json
    if ($getResultError.name -eq "not_found") {
        Write-Verbose "No bill connect exists with that account id. Continuing..."
    }
    else {
        Write-Verbose $($getResultError.message)
    }
}

$bodyPayload = @{
    "aws_bill_account_id"= $AWSBillAccountId;
    "aws_bucket_name"= $AWSBucketName;
    "aws_bucket_path"= $AWSBucketPath;
    "aws_sts_role_arn"= $AWSRoleARN;
    "aws_sts_role_session_name"= $AWSRoleSessionName
} | ConvertTo-Json

try {
    $postResult = Invoke-WebRequest -Uri "https://onboarding.rightscale.com/api/onboarding/orgs/$OrganizationID/bill_connects/aws/iam_role" -Method Post -Headers $optimaHeader -ContentType $contentType -Body $bodyPayload -ErrorAction SilentlyContinue -ErrorVariable postResultError

    if ($postResult.StatusCode -eq 201) {
        Write-Verbose "Successfully created bill connect!"
        Write-Verbose "Note: Costs may take up to 24 hours to populate."
    }
    else {
        Write-Warning "Error creating Bill Connect! Status Code: $($postResult.StatusCode)"
        Write-Warning $postResult
    }
}
catch {
    Write-Warning "Error creating Bill Connect! $($postResultError.message)"
}
# This allows you work on the file as a script
$_privateCommand = Get-Command -Name "__MakeWildcard"
if (!$_privateCommand) {
    . "$PSScriptRoot\QuotePrivateUnquoteFunctions.ps1"
}

function New-EC2KeyPair {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    $_region = __RegionFromName($Region)

    if ($Credentials) {
        $_creds = $Credentials
    }
    else {
        $_creds = Get-AwsCredentials
    }

    $_ec2Client = [Amazon.AWSClientFactory]::CreateAmazonEC2Client($_creds, $_region)

    $_createRequest = New-Object -TypeName Amazon.EC2.Model.CreateKeyPairRequest
    $_createRequest.KeyName = $Name

    $_createResponse = $_ec2Client.CreateKeyPair($_createRequest)

    $_createResponse.CreateKeyPairResult.KeyPair.KeyMaterial
}
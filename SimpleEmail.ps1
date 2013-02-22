# This allows you work on the file as a script
$_privateCommand = Get-Command -Name "__MakeWildcard"
if (!$_privateCommand) {
    . "$PSScriptRoot\QuotePrivateUnquoteFunctions.ps1"
}

$_PoshAwsSESDomain  = "Domain"
$_PoshAwsSESAddress = "EmailAddress"

function Get-SESIdentities {
    
    [CmdletBinding(DefaultParameterSetName = "Fake")]
    param(
        [string]$Filter,
        [Parameter(ParameterSetName = "DomainsOnly")]
        [switch]$Domains,
        [Parameter(ParameterSetName = "AddressesOnly")]
        [switch]$Addresses,
        [Amazon.Runtime.AWSCredentials]$Credentials
    )

    if ($Credentials) {
        $_creds = $Credentials
    } else {
        $_creds = Get-AwsCredentials
    }

    $_filter = __MakeWildcard $Filter

    $_client = New-Object Amazon.SimpleEmail.AmazonSimpleEmailServiceClient -ArgumentList $_creds

    $_nextToken = "";

    do {

        $_req = New-Object Amazon.SimpleEmail.Model.ListIdentitiesRequest
        $_req.NextToken = $_nextToken
        if ($Domains) {
            $_req.IdentityType = $_PoshAwsSESDomain
        } elseif ($Addresses) {
            $_req.IdentityType = $_PoshAwsSESAddress
        }

        $_resp = $_client.ListIdentities($_req)
        $_nextToken = $_resp.ListIdentitiesResult.NextToken

        $_resp.ListIdentitiesResult.Identities `
            | Where-Object { $_filter.IsMatch($_) }

    } while ($_nextToken)

}

function Get-SESVerifiedAddresses {
    
    [CmdletBinding()]
    param(
        [string]$Filter,
        [Amazon.Runtime.AWSCredentials]$Credentials
    )

    if ($Credentials) {
        $_creds = $Credentials
    } else {
        $_creds = Get-AwsCredentials
    }

    $_filter = __MakeWildcard $Filter

    $_client = New-Object Amazon.SimpleEmail.AmazonSimpleEmailServiceClient -ArgumentList $_creds

    $_req = New-Object Amazon.SimpleEmail.Model.ListVerifiedEmailAddressesRequest
    $_resp = $_client.ListVerifiedEmailAddresses($_req)
    $_resp.ListVerifiedEmailAddressesResult.VerifiedEmailAddresses `
        | Where-Object { $_filter.IsMatch($_) }

}
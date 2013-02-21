# This allows you work on the file as a script
$_privateCommand = Get-Command -Name "__MakeWildcard"
if (!$_privateCommand) {
    . "$PSScriptRoot\QuotePrivateUnquoteFunctions.ps1"
}

function Set-Route53CName {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$HostedZoneId,
        [Parameter(Mandatory=$true)]
        [string]$CName,
        [Parameter(Mandatory=$true)]
        [string]$Value,
        [switch]$Force,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    # TODO This is very simple and doesn't handle things like round-robin or latency-based resolution

    $_region = __RegionFromName($Region)

    if ($Credentials) {
        $_creds = $Credentials
    }
    else {
        $_creds = Get-AwsCredentials
    }

    $_r53Client = [Amazon.AWSClientFactory]::CreateAmazonRoute53Client($_creds, $_region)

    $_listRSRequest = New-Object -TypeName Amazon.Route53.Model.ListResourceRecordSetsRequest
    $_listRSRequest.StartRecordName = $CName
    $_listRSRequest.StartRecordType = "CNAME"
    $_listRSRequest.MaxItems = 1
    $_listRSRequest.HostedZoneId = $HostedZoneId

    $_matchingRSes = $_r53Client.ListResourceRecordSets($_listRSRequest).ListResourceRecordSetsResult.ResourceRecordSets | Where { $_.Name -eq $CName }

    $_changeBatch = New-Object -TypeName Amazon.Route53.Model.ChangeBatch
    $_changeBatch.Comment = "This change made by a tool."

    if ($_matchingRSes -and $_matchingRSes.Count -gt 0) {

        if (!$Force) {
            throw "A record for $Name already exists. Use -Force to force the change"
        }

        $_deleteOld = New-Object -TypeName Amazon.Route53.Model.Change
        $_deleteOld.Action = "DELETE"
        $_deleteOld.ResourceRecordSet = $_matchingRSes[0]

        $_changeBatch.Changes.Add($_deleteOld)

    }

    $_createRecord = New-Object -TypeName Amazon.Route53.Model.ResourceRecord
    $_createRecord.Value = $Value
    
    $_createRecordSet = New-Object -TypeName Amazon.Route53.Model.ResourceRecordSet
    $_createRecordSet.Name = $CName
    $_createRecordSet.Type = "CNAME"
    $_createRecordSet.TTL = 300 # Five minutes, I suppose.
    $_createRecordSet.ResourceRecords.Add($_createRecord)

    $_createNew = New-Object -TypeName Amazon.Route53.Model.Change
    $_createNew.Action = "CREATE"
    $_createNew.ResourceRecordSet = $_createRecordSet

    $_changeBatch.Changes.Add($_createNew)

    $_changeRSRequest = New-Object -TypeName Amazon.Route53.Model.ChangeResourceRecordSetsRequest
    $_changeRSRequest.HostedZoneId = $HostedZoneId
    $_changeRSRequest.ChangeBatch = $_changeBatch

    $_changeRSResponse = $_r53Client.ChangeResourceRecordSets($_changeRSRequest)
    $_changeRSResponse.ChangeResourceRecordSetsResult.ChangeInfo.Status
}

function Get-Route53HostedZones {

    [CmdletBinding()]
    param(
        [string]$ExactDomainName,
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

    $_r53Client = [Amazon.AWSClientFactory]::CreateAmazonRoute53Client($_creds, $_region)

    $_next = ""

    do {

        $_listZoneRequest = New-Object -TypeName Amazon.Route53.Model.ListHostedZonesRequest
        $_listZoneRequest.Marker = $_next
        $_listZoneResponse = $_r53Client.ListHostedZones($_listZoneRequest)
        $_listZoneResponse.ListHostedZonesResult.HostedZones | Where { !$ExactDomainName -or ($_.Name -eq $ExactDomainName) }

        $_next = $_listZoneResponse.ListHostedZonesResult.NextMarker

    } while ($_next)
}
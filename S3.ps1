# This allows you work on the file as a script
$_privateCommand = Get-Command -Name "__MakeWildcard"
if (!$_privateCommand) {
    . "$PSScriptRoot\QuotePrivateUnquoteFunctions.ps1"
}

function Get-S3Objects {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName = "ByResourceSummary", ValueFromPipeline = $true)]
        [Amazon.CloudFormation.Model.StackResourceSummary]$ResourceSummary,
        [Parameter(Mandatory=$true, ParameterSetName = "ByBucket", ValueFromPipeline = $true)]
        [Amazon.S3.Model.S3Bucket]$Bucket,
        [Parameter(Mandatory=$true, ParameterSetName = "ByName", ValueFromPipeline = $true)]
        [string]$BucketName,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    BEGIN {
        if ($Credentials) {
            $_creds = $Credentials
        }
        else {
            $_creds = Get-AwsCredentials
        }

        $_region = __RegionFromName $Region

        $_s3Client = [Amazon.AWSClientFactory]::CreateAmazonS3Client($_creds, $_region)
    }
    PROCESS {

        $_bucketName = $null
        if ($ResourceSummary) {
            Write-Debug "Using resource summary."
            if ($ResourceSummary.ResourceType -ne $_cfResourceTypes["S3Bucket"]) {
                throw "Resource is not an S3 bucket!"
            }
            $_bucketName = $ResourceSummary | Select-Object -ExpandProperty PhysicalResourceId
        }
        elseif ($Bucket) {
            Write-Debug "Using bucket."
            $_bucketName = $Bucket | Select-Object -ExpandProperty BucketName
        }
        elseif ($BucketName) {
            Write-Debug "Using bucket name."
            $_bucketName = $BucketName
        }
        else {
            throw "Wha?!"
        }
           

        $_bucketName `
            | ForEach-Object {

                $_again = $true
                $_marker = $null

                while ($_again) {
                    $_req = New-Object -TypeName Amazon.S3.Model.ListObjectsRequest
                    $_req.Marker = $_marker
                    $_req.BucketName = $_

                    $_resp = $_s3Client.ListObjects($_req)

                    $_again = $_resp.IsTruncated
                    $_marker = $_resp.NextMarker
                    $_resp.S3Objects
                }
            }
    }
    END {}

}

function Remove-S3Object {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByKey", ValueFromPipeline = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true, ParameterSetName = "ByKey")]
        [string]$BucketName,
        [Parameter(Mandatory = $true, ParameterSetName = "ByObject", ValueFromPipeline = $true)]
        [Amazon.S3.Model.S3Object[]]$Object,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    BEGIN {
        if ($Credentials) {
            $_creds = $Credentials
        }
        else {
            $_creds = Get-AwsCredentials
        }

        $_region = __RegionFromName $Region

        $_s3Client = [Amazon.AWSClientFactory]::CreateAmazonS3Client($_creds, $_region)
    }
    PROCESS {

        # There's a multi-object delete, but I don't think we care about
        # that level of optimization right now.

        if ($Key) {
            Write-Debug "Key-based delete"
            $_toRemove = $Key | ForEach-Object { @{ "Key" = $_; "Bucket" = $BucketName } }
        }
        elseif ($Object) {
            Write-Debug "Object-based delete"
            $_toRemove = $Object | ForEach-Object { @{ "Key" = $_.Key; "Bucket" = $_.BucketName } }
        }
        else {
            throw "Wha?!"
        }

        $_toRemove `
            | ForEach-Object {
                
                $_bucket = $_["Bucket"]
                $_key = $_["Key"]

                Write-Debug "Deleting '$_key' from '$_bucket'"

                $_req = New-Object Amazon.S3.Model.DeleteObjectRequest
                $_req.BucketName = $_bucket
                $_req.Key = $_key
                
                $_s3Client.DeleteObject($_req) | Out-Null
            }
    }
    END {}

}

function New-S3Bucket {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(ParameterSetName = "WithCannedAcl")]
        [Amazon.S3.Model.S3CannedACL]$CannedAcl,
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
    
    $_s3Client = [Amazon.AWSClientFactory]::CreateAmazonS3Client($_creds, $_region)

    $_putRequest = New-Object -TypeName Amazon.S3.Model.PutBucketRequest
    $_putRequest.BucketName = $Name
    $_putRequest.UseClientRegion = $true

    if ($CannedAcl) {
        $_putRequest.CannedACL = $CannedAcl
    }
    else {
        $_putRequest.CannedACL = [Amazon.S3.Model.S3CannedACL]::Private
    }
    
    $_s3Client.PutBucket($_putRequest) | Out-Null
}

function Get-S3Buckets {

    [CmdletBinding()]
    param(
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
    
    $_s3Client = [Amazon.AWSClientFactory]::CreateAmazonS3Client($_creds, $_region)
    $_req = New-Object -TypeName Amazon.S3.Model.ListBucketsRequest
    $_s3Client.ListBuckets($_req).Buckets `
        | Where-Object {
            if ($Name) {
                $_wo = [System.Management.Automation.WildcardOptions]::IgnoreCase
                $_wc = New-Object -TypeName System.Management.Automation.WildcardPattern -ArgumentList $Name, $_wo
                $_wc.IsMatch($_.BucketName)
            }
            else {
                $true
            }
        }

}

function Test-S3Bucket {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    $_escapedName = [System.Management.Automation.WildcardPattern]::Escape($Name)

    $_buckets = Get-S3Buckets -Name $_escapedName -Credentials $Credentials -Region $Region

    if ($_buckets) {
        $true
    }
    else {
        $false
    }

}

function Remove-S3Bucket {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByBucket", ValueFromPipeline = $true)]
        [Amazon.S3.Model.S3Bucket]$Bucket,
        [Parameter(Mandatory = $true, ParameterSetName = "ByName", ValueFromPipeline = $true)]
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

    if ($Bucket) {
        Write-Debug "By bucket."
        $_bucketName = $Bucket.BucketName
    }
    elseif ($Name) {
        Write-Debug "By name."
        $_bucketName = $Name
    }
    else {
        throw "Wha?!"
    }

    $_s3Client = [Amazon.AWSClientFactory]::CreateAmazonS3Client($_creds, $_region)
    $_req = New-Object -TypeName Amazon.S3.Model.DeleteBucketRequest
    $_req.BucketName = $_bucketName
    $_s3Client.DeleteBucket($_req) | Out-Null

}

function Send-FileToS3 {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AwsAccessKeyId,
        [Parameter(Mandatory=$true)]
        [string]$AwsSecretAccessKey,
        [Parameter(Mandatory=$true)]
        [string]$BucketName,
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [string]$Region
    )

    if ($Region) {
        $_regions = [Amazon.RegionEndpoint]::EnumerableAllRegions | Where { $_.SystemName -eq $Region }
        $_region = $_regions[0]
    } else { 
        $_region = [Amazon.RegionEndpoint]::USEast1
    }
    
    $_s3Client = [Amazon.AWSClientFactory]::CreateAmazonS3Client($AwsAccessKeyId, $AwsSecretAccessKey, $_region)

    $_putRequest = New-Object -TypeName Amazon.S3.Model.PutObjectRequest
    $_putRequest.BucketName = $BucketName
    $_putRequest.Key = [System.IO.Path]::GetFileName($PackagePath)
    $_putRequest.FilePath = $FilePath

    $_putResponse = $_s3Client.PutObject($_putRequest)

    return $_putResponse.ETag
}
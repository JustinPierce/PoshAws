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

        $_bucketName = $BucketName
        if ($ResourceSummary) {
            Write-Debug "Using resource summary to get bucket name"

            $_resourceType = $ResourceSummary.ResourceType
            $_resourceLogicalId = $ResourceSummary.LogicalResourceId
            $_resourcePhysicalId = $ResourceSummary.PhysicalResourceId

            if ($ResourceSummary.ResourceType -ne "AWS::S3::Bucket") {    
                throw "Stack resource $_resourceLogicalId ($_resourcePhysicalId) is not an S3 bucket!"
            }

            $_bucketName = $_resourcePhysicalId
        }
        elseif ($Bucket) {
            Write-Debug "Using bucket object to get bucket name"
            $_bucketName = $Bucket | Select-Object -ExpandProperty BucketName
        }
        
        $_marker = $null

        do {
            $_req = New-Object -TypeName Amazon.S3.Model.ListObjectsRequest
            $_req.Marker = $_marker
            $_req.BucketName = $_bucketName

            $_resp = $_s3Client.ListObjects($_req)

            if ($_resp.IsTruncated) {
                $_marker = $_resp.NextMarker
            } else {
                $_marker = $null
            }

            $_resp.S3Objects

        } while ($_marker)
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
        [Amazon.S3.Model.S3Object]$Object,
        [string]$VersionId,
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

        $_key = $Key
        $_bucketName = $BucketName

        if ($Object) {
            Write-Debug "Using S3 object to get key and bucket name"
            $_key = $Object.Key
            $_bucketName = $Object.BucketName
        }

        Write-Debug "Removing $_key from $_bucketName"

        $_req = New-Object Amazon.S3.Model.DeleteObjectRequest
        $_req.BucketName = $_bucketName
        $_req.Key = $_key
        if ($VersionId) {
            Write-Debug "Removing version ID $VersionId"
            $_req.VersionId = $VersionId
        }
                
        $_s3Client.DeleteObject($_req) | Out-Null
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

    $_nameWildcard = __MakeWildcard -Pattern $Name
    
    $_s3Client = [Amazon.AWSClientFactory]::CreateAmazonS3Client($_creds, $_region)
    $_req = New-Object -TypeName Amazon.S3.Model.ListBucketsRequest
    $_s3Client.ListBuckets($_req).Buckets `
        | Where-Object { $_nameWildcard.IsMatch($_.BucketName) }

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

    $_bucketName = $Name
    if ($Bucket) {
        Write-Debug "Using object to get bucket name"
        $_bucketName = $Bucket.BucketName
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
        [string]$BucketName,
        [string]$Key,
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
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

    if ($Key) {
        $_key = $Key
    } else {
        $_key = [System.IO.Path]::GetFileName($PackagePath)
    }

    $_putRequest = New-Object -TypeName Amazon.S3.Model.PutObjectRequest
    $_putRequest.BucketName = $BucketName
    $_putRequest.Key = $_key
    $_putRequest.FilePath = $FilePath

    $_s3Client.PutObject($_putRequest) | Out-Null

}

function Copy-S3Object {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByKey")]
        [string]$FromBucket,
        [Parameter(Mandatory = $true, ParameterSetName = "ByKey")]
        [string]$FromKey,
        [Parameter(Mandatory = $true, ParameterSetName = "ByObject", ValueFromPipeline = $true)]
        [Amazon.S3.Model.S3Object]$FromObject,
        [string]$ToBucket,
        [string]$ToKey,
        [switch]$PreserveAcl,
        [hashtable]$ReplaceMetadataWith,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    BEGIN {
        
        $_region = __RegionFromName($Region)

        if ($Credentials) {
            $_creds = $Credentials
        }
        else {
            $_creds = Get-AwsCredentials
        }

        $_client = [Amazon.AWSClientFactory]::CreateAmazonS3Client($_creds, $_region)

    }
    PROCESS {

        if (!$ToBucket -and !$ToKey) {
            throw "ToBucket, ToKey, or both must be provided!"
        }
        
        $_fromBucket = $FromBucket
        $_fromKey = $FromKey
        if ($FromObject) {
            Write-Debug "Using 'FromObject' to get object bucket and key"
            $_fromBucket = $FromObject.BucketName
            $_fromKey = $FromObject.Key
        }

        $_toBucket = $_fromBucket
        $_toKey = $_fromKey

        if ($ToBucket) {
            $_toBucket = $ToBucket
        } 
        if ($ToKey) {
            $_toKey = $ToKey
        }

        Write-Verbose "Copying $_fromBucket/$_fromKey to $_toBucket/$_toKey ..."

        $_request = New-Object Amazon.S3.Model.CopyObjectRequest
        $_request.SourceBucket = $_fromBucket
        $_request.SourceKey = $_fromKey
        $_request.DestinationBucket = $_toBucket
        $_request.DestinationKey = $_toKey
        if ($ReplaceMetadataWith) {
            Write-Verbose "Replacing object metadata ..."
            $_request.Directive = "REPLACE"
            $ReplaceMetadataWith.GetEnumerator() `
                | ForEach-Object {
                    $_headerName = $_.Key.ToString()
                    $_headerValue = $_.Value.ToString()
                    $_request.AddHeader($_headerName, $_headerValue)
                    Write-Verbose "Added header $_headerName : $_headerValue"
                }
        } else {
            $_request.Directive = "COPY"
        }

        if ($PreserveAcl) {
            Write-Verbose "Copying ACL ..."
            $_aclRequest = New-Object Amazon.S3.Model.GetACLRequest
            $_aclRequest.BucketName = $_fromBucket
            $_aclRequest.Key = $_fromKey
            [Amazon.S3.Model.GetACLResponse]$_aclResponse = $_client.GetACL($_aclRequest)
            $_request.Grants = $_aclResponse.AccessControlList.Grants
        }

        $_client.CopyObject($_request) | Out-Null

        Write-Verbose "Copy complete."
    }
    END {}

}
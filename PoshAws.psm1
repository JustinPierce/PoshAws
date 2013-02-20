$_cfResourceTypes = @{
    "S3Bucket" = "AWS::S3::Bucket"
}

$_cfStackStatuses = @{
    "CREATE_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $true };
    "CREATE_COMPLETE" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $false };
    "CREATE_FAILED" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
    "ROLLBACK_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $true };
    "ROLLBACK_FAILED" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
    "ROLLBACK_COMPLETE" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
    "DELETE_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $true };
    "DELETE_FAILED" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
    "DELETE_COMPLETE" = @{ "Active" = $false; "Failed" = $false; "InFlux" = $false };
    "UPDATE_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $true };
    "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $true };
    "UPDATE_COMPLETE" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $false };
    "UPDATE_ROLLBACK_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $true };
    "UPDATE_ROLLBACK_FAILED" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
    "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $true };
    "UPDATE_ROLLBACK_COMPLETE" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
}

#region "Private" functions

function __StackStatusMap([string]$StackStatus) {
    if(!$_cfStackStatuses.ContainsKey($StackStatus)) {
        throw "$StackStatus is not a recognized stack status."
    }
    $_cfStackStatuses[$StackStatus]
}

function __IsStackActive([string]$StackStatus) {
    $_map = __StackStatusMap($StackStatus)
    $_map["Active"]
}

function __IsStackFailed([string]$StackStatus) {
    $_map = __StackStatusMap($StackStatus)
    $_map["Failed"]
}

function __MakeWildcard([string]$Pattern) {
    [string]$_pattern = "*"
    if ($Pattern) {
        $_pattern = $Pattern
    }
    $_wo = [System.Management.Automation.WildcardOptions]::IgnoreCase
    New-Object System.Management.Automation.WildcardPattern -ArgumentList $_pattern, $_wo
}

function __RegionFromName([string] $systemName) {
    if ($systemName -and $systemName -ne "") {
        $_regions = [Amazon.RegionEndpoint]::EnumerableAllRegions | Where { $_.SystemName -eq $systemName }
        $_region = $_regions[0]
    } else { 
        $_region = [Amazon.RegionEndpoint]::USEast1
    }
    return $_region
}

#endregion

#region Utility

function Import-AwsSdk {

    [CmdletBinding()]
    param(
        [string]$SearchPath,
        [switch]$Force
    )

    $_needToLoad = $Force.ToBool()

    try {
        New-Object Amazon.S3.Model.ListObjectsRequest | Out-Null
    } catch {
        $_needToLoad = $true
    }

    if ($_needToLoad) {

        $_lookIn = $PWD
        if ($SearchPath) {
            $_lookIn = $SearchPath
        }

        Write-Debug "Searching $_lookIn for AWS SDK."

        $_sdkAssembly = Get-ChildItem -Path $_lookIn -Filter "AWSSDK.dll" -Recurse `
                            | Sort-Object -Descending -Property VersionInfo `
                            | Select-Object -First 1

        if ($_sdkAssembly) {

            $_sdkAssemblyName = $_sdkAssembly.FullName

            Write-Debug "Using AWS SDK from $_sdkAssemblyName."

            # Copy it to prevent file locking issues.
            $_shadowPath = Join-Path (Join-Path $env:TEMP (Get-Random)) .\awscommands\AWSSDK.dll

            New-Item -Path (Split-Path $_shadowPath) -ItemType directory -ErrorAction SilentlyContinue

            Copy-Item $_sdkAssemblyName $_shadowPath -Force

            Add-Type -Path $_shadowPath

        }
        else {
            throw "Could not locate AWS SDK!"
        }

    }

}

#endregion

. $PSScriptRoot\Credentials.ps1
. $PSScriptRoot\SimpleEmail.ps1

#region CloudFormation

function Remove-CFStack {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName = "ByStackSummary", ValueFromPipeline = $true)]
        [Amazon.CloudFormation.Model.StackSummary]$StackSummary,
        [Parameter(Mandatory=$true, ParameterSetName = "ByName", ValueFromPipeline = $true)]
        [string]$StackName,
        [switch]$SkipConfirmation,
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

        $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)
    }
    PROCESS {

        if ($StackSummary) {
            Write-Debug "Using stack summary."
            $_stackName = $StackSummary | Select-Object -ExpandProperty StackName
        }
        elseif ($StackName) {
            Write-Debug "Using stack name."
            $_stackName = $StackName
        }
        else {
            throw "Wha?!"
        }
        
        $_stackName `
            | ForEach-Object {

                if (!$SkipConfirmation) {
                    Write-Host "You are about to remove a CloudFormation stack, which is potentially very, very bad." `
                        -ForegroundColor White `
                        -BackgroundColor Red
                    Write-Host "Please confirm you want the stack removed by typing the stack name exactly." `
                        -ForegroundColor White `
                        -BackgroundColor Red
                    $_confirmed = Read-Host "Stack Name"
                    if ($_confirmed -cne $_) {
                        throw "Confirmation did not match stack name!"
                    }
                }

                $_req = New-Object Amazon.CloudFormation.Model.DeleteStackRequest
                $_req.StackName = $_
                $_cfClient.DeleteStack($_req)
            }
    }
    END {
    }

}

function Get-CFStackResources {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName = "ByStackSummary", ValueFromPipeline = $true)]
        [Amazon.CloudFormation.Model.StackSummary]$StackSummary,
        [Parameter(Mandatory=$true, ParameterSetName = "ByName", ValueFromPipeline = $true)]
        [string]$StackName,
        [string]$LogicalId,
        [string]$ResourceType,
        [string]$ResourceStatus,
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

        $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)
    }
    PROCESS {

        if ($StackSummary) {
            Write-Debug "Using stack summary."
            $_stackName = $StackSummary | Select-Object -ExpandProperty StackName
        }
        elseif ($StackName) {
            Write-Debug "Using stack name."
            $_stackName = $StackName
        }
        else {
            throw "Wha?!"
        }
        
        $_stackName `
            | ForEach-Object {
                $_req = New-Object Amazon.CloudFormation.Model.ListStackResourcesRequest
                $_req.StackName = $_
                $_resp = $_cfClient.ListStackResources($_req)

                $_logicalWildcard = __MakeWildcard($LogicalId)
                $_typeWildcard = __MakeWildcard($ResourceType)
                $_statusWildcard = __MakeWildcard($ResourceStatus)

                $_resp.ListStackResourcesResult.StackResourceSummaries `
                    | Where-Object {
                        $_logicalWildcard.IsMatch($_.LogicalResourceId)
                    } `
                    | Where-Object {
                        $_typeWildcard.IsMatch($_.ResourceType)
                    } `
                    | Where-Object {
                        $_statusWildcard.IsMatch($_.ResourceStatus)
                    }
            }
    }
    END {
    }

}

function Get-CFStacks {

    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$ExactName,
        [switch]$IncludeInactive,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    if ($Credentials) {
        $_creds = $Credentials
    }
    else {
        $_creds = Get-AwsCredentials
    }

    $_region = __RegionFromName $Region

    $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)

    $_req = New-Object -TypeName Amazon.CloudFormation.Model.ListStacksRequest

    $_resp = $_cfClient.ListStacks($_req)

    $_nameWildcard = __MakeWildcard($Name)

    $_resp.ListStacksResult.StackSummaries `
        | Where-Object {
            if ($IncludeInactive) {
                $true
            }
            else {
                __IsStackActive($_.StackStatus)
            }
        } `
        | Where-Object {
            !$ExactName -or ($ExactName -eq $_.StackName)
        } `
        | Where-Object {
            $_nameWildcard.IsMatch($_.StackName)
        }

}

function Test-CFTemplate {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TemplatePath,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    $_region = __RegionFromName($Region)

    Write-Verbose "Validating $TemplatePath ..."

    if (!(Test-Path $TemplatePath)) {
        throw "Template not found at $TemplatePath!"
    }

    if ($Credentials) {
        $_creds = $Credentials
    }
    else {
        $_creds = Get-AwsCredentials
    }    

    $_templateBody = Get-Content $TemplatePath

    $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)

    $_req = New-Object Amazon.CloudFormation.Model.ValidateTemplateRequest
    $_req.TemplateBody = $_templateBody
    
    $_cfClient.ValidateTemplate($_req) `
        | Select-Object -ExpandProperty ValidateTemplateResult `
        | Select-Object -Property Capabilities, Parameters
}

function Set-CFStack {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$TemplatePath,
        [switch]$Force,
        [hashtable]$TemplateParams,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    if (!(Test-Path $TemplatePath)) {
        throw "Template not found at $TemplatePath!"
    }

    if ($Credentials) {
        $_creds = $Credentials
    }
    else {
        $_creds = Get-AwsCredentials
    }

    $_region = __RegionFromName($Region)

    $_templateBody = Get-Content $TemplatePath

    $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)

    $_alreadyExists = Get-CFStacks -ExactName $Name -Credentials $_creds

    if ($_alreadyExists -and -not $Force) {
        throw "Stack '$Name' already exists. Use -Force to update an existing stack."
    }

    $_testedTemplate = Test-CFTemplate -TemplatePath $TemplatePath -Credentials $_creds
    
    $_capabilities = $_testedTemplate.Capabilities
    $_foundParameters = $_testedTemplate.Parameters

    # PS and generic lists. Whee.
    $_parameterType = [Amazon.CloudFormation.Model.Parameter]
    $_parameterListType = [System.Collections.Generic.List``1].MakeGenericType(@($_parameterType))
    $_parameterList = [Activator]::CreateInstance($_parameterListType)

    $_foundParameters | ForEach-Object {

        $_currParam = New-Object -TypeName Amazon.CloudFormation.Model.Parameter
        $_currParam.ParameterKey = $_.ParameterKey

        if ($TemplateParams -and $TemplateParams.ContainsKey($_currParam.ParameterKey)) {
            $_currParam.ParameterValue = $TemplateParams[$_currParam.ParameterKey]
        } elseif ($_.DefaultValue -and $_.DefaultValue -ne "") {
            $_currParam.ParameterValue = $_.DefaultValue
        } else {
            throw "Missing parameter value for " + $_currParam.ParameterKey
        }

        $_parameterList.Add($_currParam)
    }

    if ($_alreadyExists) {
        
        Write-Host "Updating stack $Name ..."

        $_updateRequest = New-Object -TypeName Amazon.CloudFormation.Model.UpdateStackRequest
        $_updateRequest.Capabilities = $_capabilities
        $_updateRequest.StackName = $Name
        $_updateRequest.TemplateBody = $_templateBody
        $_updateRequest.Parameters = $_parameterList

        $_updateResponse = $_cfClient.UpdateStack($_updateRequest)

        Write-Host "Updated " + $_updateResponse.UpdateStackResult.StackId

    } else {

        Write-Host "Creating stack $Name ..."

        $_createRequest = New-Object -TypeName Amazon.CloudFormation.Model.CreateStackRequest
        $_createRequest.Capabilities = $_capabilities
        $_createRequest.StackName = $Name
        $_createRequest.TemplateBody = $_templateBody
        $_createRequest.Parameters = $_parameterList

        $_createResponse = $_cfClient.CreateStack($_createRequest)

        Write-Host "Created " + $_createResponse.CreateStackResult.StackId

    }
}

function Get-CFStackOutputs {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "BySummary", ValueFromPipeline = $true)]
        [Amazon.CloudFormation.Model.StackSummary]$StackSummary,
        [Parameter(Mandatory = $true, ParameterSetName = "ByName", ValueFromPipeline = $true)]
        [string]$StackName,
        [string]$Key,
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
    
    if ($StackSummary) {
        Write-Debug "By summary."
        $_stackName = $StackSummary.StackName
    }
    elseif ($StackName) {
        Write-Debug "By name."
        $_stackName = $StackName
    }

    $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)

    $_outputReq = New-Object -TypeName Amazon.CloudFormation.Model.DescribeStacksRequest
    $_outputReq.StackName = $_stackName

    [Amazon.CloudFormation.Model.Stack]$_stack = $_cfClient.DescribeStacks($_outputReq).DescribeStacksResult.Stacks `
                                                    | Select-Object -First 1

    if (!$_stack) {
        throw "Stack $Name not found."
    }

    $_keyWildcard = __MakeWildcard($Key)

    $_stack.Outputs | Where-Object { $_keyWildcard.IsMatch($_.OutputKey) }
}

#endregion

#region S3

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

#endregion

#region EC2

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

#endregion

#region Route53

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

#endregion

Export-ModuleMember -Function *-*
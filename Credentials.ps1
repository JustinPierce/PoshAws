$_credentialsPath = Join-Path (Split-Path $profile) .psaws

[System.Collections.Stack]$global:PsAwsCredentialsStack = New-Object System.Collections.Stack

function New-AwsCredentials {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccessKeyId,
        [Parameter(Mandatory = $true)]
        [string]$SecretAccessKey
    )

    New-Object Amazon.Runtime.BasicAWSCredentials -ArgumentList $AccessKeyId, $SecretAccessKey

}

function Add-StoredAwsCredentials {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true, ParameterSetName = "ByCredentials", ValueFromPipeline = $true)]
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [Parameter(Mandatory = $true, ParameterSetName = "ByKeyAndSecret")]
        [string]$AccessKeyId,
        [Parameter(Mandatory = $true, ParameterSetName = "ByKeyAndSecret")]
        [string]$SecretAccessKey,
        [switch]$Force
    )

    if (!(Test-Path $_credentialsPath)) {
        New-Item $_credentialsPath -ItemType directory
    }

    $_filePath = Join-Path $_credentialsPath "$Name.creds"

    if ((Test-Path $_filePath) -and (!$Force)) {
        throw "Existing credentials named '$Name'!"
    }

    if ($Credentials) {
        $_keyId = $Credentials.GetCredentials().AccessKey
        $_secret = $Credentials.GetCredentials().ClearSecretKey
    }
    elseif ($AccessKeyId -and $SecretAccessKey) {
        $_keyId = $AccessKeyId
        $_secret = $SecretAccessKey
    }
    else {
        throw "Wha?!"
    }

    @{ "KeyId" = $_keyId; "Secret" = $_secret } `
        | ConvertTo-Json `
        | Out-File -FilePath $_filePath -Encoding utf8 -Force

}

function Get-StoredAwsCredentials {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $_filePath = Join-Path $_credentialsPath "$Name.creds"

    if (Test-Path $_filePath) {
        $_stored = Get-Content -Path $_filePath -Encoding UTF8 -Raw | ConvertFrom-Json
        New-AwsCredentials -AccessKeyId $_stored.KeyId -SecretAccessKey $_stored.Secret
    }
    else {
        throw "No stored credentials named '$Name'!"
    }

}

function Get-StoredAwsCredentialNames {

    [CmdletBinding()]
    param()

    Get-ChildItem -Path $_credentialsPath -Filter *.creds `
        | Select-Object -ExpandProperty Name `
        | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) }
}

function Get-AwsCredentials {

    [CmdletBinding()]
    param()

    # Look in the stack first
    if ($global:PsAwsCredentialsStack.Count -ne 0) {
        [Amazon.Runtime.AWSCredentials] $global:PsAwsCredentialsStack.Peek()
    }
    else {
        try {
            New-Object -TypeName Amazon.Runtime.EnvironmentAWSCredentials
        }
        catch {
            New-Object -TypeName Amazon.Runtime.InstanceProfileAWSCredentials
        }
    }

}

function Push-AwsCredentials {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Amazon.Runtime.AWSCredentials]$Credentials
    )

    $global:PsAwsCredentialsStack.Push($Credentials)

}

function Pop-AwsCredentials {

    [CmdletBinding()]
    param(
    )

    if ($global:PsAwsCredentialsStack.Count -ne 0) {
        [void] $global:PsAwsCredentialsStack.Pop()
    }

}
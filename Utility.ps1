# This allows you work on the file as a script
$_privateCommand = Get-Command -Name "__MakeWildcard"
if (!$_privateCommand) {
    . "$PSScriptRoot\QuotePrivateUnquoteFunctions.ps1"
}

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
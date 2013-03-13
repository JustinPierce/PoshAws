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

            New-Item -Path (Split-Path $_shadowPath) -ItemType directory -ErrorAction SilentlyContinue | Out-Null

            Copy-Item $_sdkAssemblyName $_shadowPath -Force

            Add-Type -Path $_shadowPath

        }
        else {
            throw "Could not locate AWS SDK!"
        }

    }

}

function ConvertTo-Hashtable {

    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Position = 0)]
        $InputObject,
        [switch]$TreatFalseyAsEmpty
    )

    if ($InputObject) {
        if ($InputObject -is [hashtable]) {
            $InputObject
        } elseif ($InputObject -is [PSCustomObject]) {
            $_table = @{}
            $InputObject.PSObject.Properties `
                | Where-Object {
                    $_.IsGettable -and $_.IsInstance
                } `
                | ForEach-Object {
                    $_table.Add($_.Name, $_.Value)
                }
            $_table
        } else {
            $_inputType = $InputObject.GetType()
            throw "Can't convert $_inputType to a hashtable."
        }
    } elseif ($TreatFalseyAsEmpty) {
        @{}
    } else {
        [hashtable]$null
    }

}

function Merge-Objects {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        $InputObject,
        [Parameter(Position = 1)]
        $AdditionalValues,
        [ValidateSet("Hashtable", "PSCustomObject", IgnoreCase = $true)]
        [Parameter(Position = 2)]
        $OutputType = "Hashtable"
    )

    [hashtable]$_inputHashtable = ConvertTo-Hashtable -InputObject $InputObject
    [hashtable]$_additionalHashtable = ConvertTo-Hashtable -InputObject $AdditionalValues -TreatFalseyAsEmpty

    $_merged = @{}

    $_inputHashtable.GetEnumerator() `
        | ForEach-Object {
            $_merged.Add($_.Key, $_.Value)
        }

    $_additionalHashtable.GetEnumerator() `
        | ForEach-Object {
            $_merged[$_.Key] = $_.Value
        }

    if ($OutputType -eq "Hashtable") {
        $_merged
    } else {
        New-Object psobject -Property $_merged
    }
}
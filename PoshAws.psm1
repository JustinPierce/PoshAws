$ErrorActionPreference = "Stop"

$_includedFiles = @(
    "QuotePrivateUnquoteFunctions.ps1";
    "Utility.ps1";
    "Credentials.ps1";
    "SimpleEmail.ps1";
    "CloudFormation.ps1";
    "S3.ps1";
    "EC2.ps1";
    "Route53.ps1";
)

$_includedFiles | ForEach-Object {
    $_includePath = Join-Path $PSScriptRoot $_
    Write-Verbose "Including '$_includePath'."
    . $_includePath
}

Export-ModuleMember -Function *-*